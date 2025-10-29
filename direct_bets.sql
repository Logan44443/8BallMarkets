/* ============================================================================
 Direct Bets Guru — COMPLETE Postgres schema & business logic
 ------------------------------------------------------------------------------
 - Table `direct_bets` with strict constraints and a well-defined status machine.
 - Minimal double-entry-style ledger (`ledger_transactions`, `ledger_postings`)
   that moves money between AVAILABLE and HELD “buckets”.
 - Full audit trail (`bet_audit_log`) + link table tying ledger txs to bets.
 - Triggers to enforce:
     * acceptance rules + stake/terms immutability
     * valid status transitions (PENDING→ACTIVE→RESOLVED/DISPUTED etc.)
     * authorization for RESOLVED/DISPUTED (arbiter or admin)
     * automatic wallet postings on accept / resolve / cancel-expire paths
 - Convenience functions: propose / accept / resolve / dispute / cancel-expire
 - Fees + odds-based payout math implemented (house user via app_settings)
 - Stronger wallet balance enforcement for AVAILABLE debits.

 HOW AUTH WORKS INSIDE THE DB
 - The app sets two GUCs (session variables) per transaction:
     * app.current_user_id   (BIGINT) — who is calling
     * app.current_is_admin  ('on'/'off') — admin override for certain actions
   Example:
     SELECT set_config('app.current_user_id','12345', true);
     SELECT set_config('app.current_is_admin','off', true);

============================================================================ */


/* ---------------------------------------------------------------------------
CORE TABLE: direct_bets
    - stores the bet offer, acceptance, and resolution data
    - enforces identity and state validity with constraints
---------------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS direct_bets (
  bet_id               BIGSERIAL PRIMARY KEY,

  -- participants
  proposer_id          BIGINT NOT NULL REFERENCES users(user_id),
  acceptor_id          BIGINT     REFERENCES users(user_id),   -- NULL until accepted
  arbiter_id           BIGINT     REFERENCES users(user_id),   -- optional impartial resolver

  -- lifecycle / state
  status               TEXT NOT NULL DEFAULT 'PENDING'
                       CHECK (status IN ('PENDING','ACTIVE','RESOLVED','DISPUTED','CANCELED','EXPIRED')),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  accepted_at          TIMESTAMPTZ,
  resolved_at          TIMESTAMPTZ,

  -- description & odds (DECIMAL odds required for ODDS model)
  event_description    TEXT NOT NULL,
  odds_format          TEXT NOT NULL DEFAULT 'DECIMAL'
                       CHECK (odds_format IN ('DECIMAL','AMERICAN','FRACTIONAL')),
  odds_proposer        NUMERIC(10,4),   -- proposer’s decimal odds when payout_model='ODDS'
  odds_acceptor        NUMERIC(10,4),   -- acceptor’s decimal odds when payout_model='ODDS'

  -- payout model & fees
  payout_model         TEXT NOT NULL DEFAULT 'EVENS'
                       CHECK (payout_model IN ('EVENS','ODDS')),
  fee_bps              INT  NOT NULL DEFAULT 0
                       CHECK (fee_bps BETWEEN 0 AND 10000),

  -- money fields (integer cents avoids float rounding)
  stake_proposer_cents BIGINT NOT NULL CHECK (stake_proposer_cents > 0),
  stake_acceptor_cents BIGINT          CHECK (stake_acceptor_cents IS NULL OR stake_acceptor_cents > 0),
  currency_code        CHAR(3) NOT NULL DEFAULT 'USD',

  -- outcome fields (set on RESOLVED; VOID = no winner, just releases)
  outcome              TEXT
                       CHECK (outcome IN ('PROPOSER_WIN','ACCEPTOR_WIN','VOID')),
  resolved_by          BIGINT REFERENCES users(user_id),  -- who marked it resolved
  outcome_notes        TEXT,                              -- optional notes/dispute info

  -- identity sanity checks
  CHECK (proposer_id IS DISTINCT FROM acceptor_id),
  CHECK (
    arbiter_id IS NULL OR
    (arbiter_id IS DISTINCT FROM proposer_id AND arbiter_id IS DISTINCT FROM acceptor_id)
  ),

  -- if there is an acceptor, there must be an acceptor stake
  CHECK (
    (acceptor_id IS NULL AND stake_acceptor_cents IS NULL)
    OR (acceptor_id IS NOT NULL AND stake_acceptor_cents IS NOT NULL)
  ),

  -- odds presence only when payout_model='ODDS'; and require DECIMAL odds
  CONSTRAINT chk_odds_presence CHECK (
    (payout_model = 'EVENS')
    OR (
         payout_model = 'ODDS'
     AND odds_format  = 'DECIMAL'
     AND odds_proposer IS NOT NULL AND odds_proposer > 1.0
     AND odds_acceptor IS NOT NULL AND odds_acceptor > 1.0
    )
  )
);

-- helpful indexes for common filters
CREATE INDEX IF NOT EXISTS idx_direct_bets_status      ON direct_bets(status);
CREATE INDEX IF NOT EXISTS idx_direct_bets_proposer    ON direct_bets(proposer_id);
CREATE INDEX IF NOT EXISTS idx_direct_bets_acceptor    ON direct_bets(acceptor_id);
CREATE INDEX IF NOT EXISTS idx_direct_bets_created_at  ON direct_bets(created_at);
CREATE INDEX IF NOT EXISTS idx_direct_bets_resolved_at ON direct_bets(resolved_at);

-- partials for “my active bets” dashboards
CREATE INDEX IF NOT EXISTS idx_direct_bets_user_active
  ON direct_bets(proposer_id, created_at DESC)
  WHERE status IN ('PENDING','ACTIVE');

CREATE INDEX IF NOT EXISTS idx_direct_bets_counterparty_active
  ON direct_bets(acceptor_id, created_at DESC)
  WHERE status IN ('ACTIVE');

/* ---------------------------------------------------------------------------
  LEDGER TABLES
    - ledger_transactions: logical “envelope” for a money movement
    - ledger_postings: actual postings impacting a user’s bucket (AVAILABLE/HELD)
    - bet_ledger_links: connects a ledger tx to its originating bet
    - bet_audit_log: human-friendly audit of bet mutations
---------------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS ledger_transactions (
  tx_id          BIGSERIAL PRIMARY KEY,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by     BIGINT,               -- app.current_user_id (auditing only)
  currency_code  CHAR(3) NOT NULL,
  tx_type        TEXT NOT NULL CHECK (tx_type IN ('HOLD','RELEASE','PAYOUT','REFUND')),
  memo           TEXT
);

CREATE TABLE IF NOT EXISTS ledger_postings (
  posting_id   BIGSERIAL PRIMARY KEY,
  tx_id        BIGINT NOT NULL REFERENCES ledger_transactions(tx_id) ON DELETE CASCADE,
  user_id      BIGINT NOT NULL REFERENCES users(user_id),
  amount_cents BIGINT NOT NULL,        -- +credit to user bucket; -debit from user bucket
  balance_kind TEXT NOT NULL CHECK (balance_kind IN ('AVAILABLE','HELD')),
  -- each (tx, user, bucket) appears at most once
  UNIQUE (tx_id, user_id, balance_kind)
);

CREATE TABLE IF NOT EXISTS bet_ledger_links (
  bet_id BIGINT NOT NULL REFERENCES direct_bets(bet_id) ON DELETE CASCADE,
  tx_id  BIGINT NOT NULL REFERENCES ledger_transactions(tx_id) ON DELETE CASCADE,
  PRIMARY KEY (bet_id, tx_id)
);

CREATE TABLE IF NOT EXISTS bet_audit_log (
  audit_id   BIGSERIAL PRIMARY KEY,
  bet_id     BIGINT NOT NULL REFERENCES direct_bets(bet_id) ON DELETE CASCADE,
  at_time    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actor_id   BIGINT,
  action     TEXT NOT NULL,
  details    JSONB
);

/* ---------------------------------------------------------------------------
App settings (for house account, etc.)
---------------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS app_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

/* ---------------------------------------------------------------------------
View for quick wallet inspection by user.
   - Sums postings across all transactions to show current bucket balances.
   - In production, consider a materialized view or precomputed balances table.
---------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW wallet_balances AS
SELECT
  p.user_id,
  SUM(CASE WHEN p.balance_kind='AVAILABLE' THEN p.amount_cents ELSE 0 END) AS available_cents,
  SUM(CASE WHEN p.balance_kind='HELD'      THEN p.amount_cents ELSE 0 END) AS held_cents
FROM ledger_postings p
GROUP BY p.user_id;

/* ---------------------------------------------------------------------------
HELPERS: read app auth flags (GUCs) and house account
---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION app__current_user_id() RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v TEXT; BEGIN
  v := current_setting('app.current_user_id', true);
  IF v IS NULL THEN RETURN NULL; END IF;
  RETURN v::BIGINT;
END $$;

CREATE OR REPLACE FUNCTION app__current_is_admin() RETURNS BOOLEAN
LANGUAGE plpgsql AS $$
DECLARE v TEXT; BEGIN
  v := current_setting('app.current_is_admin', true);
  RETURN COALESCE(v,'off') IN ('on','true','1');
END $$;

CREATE OR REPLACE FUNCTION app__house_user_id() RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v TEXT; BEGIN
  SELECT value INTO v FROM app_settings WHERE key='house_user_id';
  IF v IS NULL THEN
    RAISE EXCEPTION 'Missing app_settings.house_user_id';
  END IF;
  RETURN v::BIGINT;
END $$;

/* ---------------------------------------------------------------------------
  BEFORE UPDATE TRIGGER ON direct_bets
   ENFORCES:
   - Accept flow (NULL→NOT NULL acceptor): require stake, set accepted_at, set ACTIVE
   - Currency immutability after acceptance
   - Status state machine + authorizations:
       * PENDING→ACTIVE requires acceptor_id set
       * ACTIVE→RESOLVED requires outcome and arbiter/admin authorization
       * ACTIVE→DISPUTED requires notes and party/arbiter/admin authorization
       * DISPUTED→RESOLVED requires outcome and arbiter/admin authorization
       * RESOLVED/CANCELED/EXPIRED are terminal (immutable)
   - Stake/terms immutability after acceptance (including odds & fee_bps)
---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION trg_direct_bets_before_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  actor BIGINT := app__current_user_id();
  admin BOOLEAN := app__current_is_admin();
BEGIN
  /* -- Accepting a bet: acceptor_id transitions from NULL to NOT NULL */
  IF TG_OP = 'UPDATE'
     AND OLD.acceptor_id IS NULL
     AND NEW.acceptor_id IS NOT NULL THEN

    IF NEW.stake_acceptor_cents IS NULL OR NEW.stake_acceptor_cents <= 0 THEN
      RAISE EXCEPTION 'stake_acceptor_cents must be > 0 when accepting';
    END IF;

    IF NEW.currency_code <> OLD.currency_code THEN
      RAISE EXCEPTION 'currency_code cannot change on acceptance';
    END IF;

    -- ODDS model guardrails at accept time (DECIMAL odds only for now)
    IF COALESCE(NEW.payout_model,'EVENS') = 'ODDS' THEN
      IF NEW.odds_format <> 'DECIMAL' THEN
        RAISE EXCEPTION 'For payout_model=ODDS, odds_format must be DECIMAL';
      END IF;
      IF NEW.odds_acceptor IS NULL OR NEW.odds_acceptor <= 1.0 THEN
        RAISE EXCEPTION 'odds_acceptor must be > 1.0 for ODDS';
      END IF;
      IF NEW.odds_proposer IS NULL OR NEW.odds_proposer <= 1.0 THEN
        RAISE EXCEPTION 'odds_proposer must be > 1.0 for ODDS';
      END IF;
    END IF;

    -- freeze core terms right at accept time
    IF NEW.stake_proposer_cents <> OLD.stake_proposer_cents
       OR NEW.odds_format <> OLD.odds_format
       OR NEW.odds_proposer <> OLD.odds_proposer
       OR NEW.event_description <> OLD.event_description
       OR NEW.payout_model <> OLD.payout_model
       OR NEW.fee_bps <> OLD.fee_bps
       OR COALESCE(NEW.odds_acceptor, OLD.odds_acceptor) <> COALESCE(OLD.odds_acceptor, NEW.odds_acceptor)
    THEN
      RAISE EXCEPTION 'Terms are immutable upon acceptance';
    END IF;

    NEW.accepted_at := NOW();
    NEW.status := 'ACTIVE';
  END IF;

  /* -- Currency cannot change after acceptance */
  IF OLD.acceptor_id IS NOT NULL AND NEW.currency_code <> OLD.currency_code THEN
    RAISE EXCEPTION 'currency_code cannot change after acceptance';
  END IF;

  /* -- Status transition rules & authorization */
  IF NEW.status <> OLD.status THEN
    CASE OLD.status
      WHEN 'PENDING' THEN
        IF NEW.status NOT IN ('PENDING','ACTIVE','CANCELED','EXPIRED') THEN
          RAISE EXCEPTION 'Invalid transition from PENDING to %', NEW.status;
        END IF;
        IF NEW.status = 'ACTIVE' AND NEW.acceptor_id IS NULL THEN
          RAISE EXCEPTION 'Cannot set ACTIVE without an acceptor';
        END IF;

      WHEN 'ACTIVE' THEN
        IF NEW.status NOT IN ('ACTIVE','RESOLVED','DISPUTED','CANCELED','EXPIRED') THEN
          RAISE EXCEPTION 'Invalid transition from ACTIVE to %', NEW.status;
        END IF;

        IF NEW.status = 'RESOLVED' THEN
          IF NEW.outcome IS NULL THEN
            RAISE EXCEPTION 'Outcome must be set to resolve';
          END IF;
          NEW.resolved_at := COALESCE(NEW.resolved_at, NOW());
          IF NOT (admin OR (actor IS NOT NULL AND actor = NEW.arbiter_id)) THEN
            RAISE EXCEPTION 'Only arbiter or admin can RESOLVE';
          END IF;
          NEW.resolved_by := COALESCE(NEW.resolved_by, actor);
        END IF;

        IF NEW.status = 'DISPUTED' THEN
          IF NEW.outcome_notes IS NULL OR length(trim(NEW.outcome_notes)) = 0 THEN
            RAISE EXCEPTION 'Outcome notes required to open a dispute';
          END IF;
          IF NOT (admin OR actor IN (NEW.proposer_id, NEW.acceptor_id, NEW.arbiter_id)) THEN
            RAISE EXCEPTION 'Only parties or arbiter/admin can DISPUTE';
          END IF;
        END IF;

      WHEN 'DISPUTED' THEN
        IF NEW.status NOT IN ('DISPUTED','ACTIVE','RESOLVED','CANCELED') THEN
          RAISE EXCEPTION 'Invalid transition from DISPUTED to %', NEW.status;
        END IF;

        IF NEW.status = 'RESOLVED' THEN
          IF NEW.outcome IS NULL THEN
            RAISE EXCEPTION 'Outcome must be set to resolve from DISPUTED';
          END IF;
          NEW.resolved_at := COALESCE(NEW.resolved_at, NOW());
          IF NOT (admin OR (actor IS NOT NULL AND actor = NEW.arbiter_id)) THEN
            RAISE EXCEPTION 'Only arbiter or admin can RESOLVE a dispute';
          END IF;
          NEW.resolved_by := COALESCE(NEW.resolved_by, actor);
        END IF;

      WHEN 'RESOLVED','CANCELED','EXPIRED' THEN
        IF NEW.status <> OLD.status THEN
          RAISE EXCEPTION 'Terminal state % is immutable', OLD.status;
        END IF;

      ELSE
        RAISE EXCEPTION 'Unknown previous status %', OLD.status;
    END CASE;
  END IF;

  /* -- Terms become immutable after acceptance */
  IF OLD.acceptor_id IS NOT NULL THEN
    IF NEW.stake_proposer_cents <> OLD.stake_proposer_cents
       OR NEW.stake_acceptor_cents <> OLD.stake_acceptor_cents
       OR NEW.odds_acceptor <> OLD.odds_acceptor
       OR NEW.payout_model <> OLD.payout_model
       OR NEW.fee_bps <> OLD.fee_bps
    THEN
      RAISE EXCEPTION 'Stake/odds/fee fields are immutable after acceptance';
    END IF;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS direct_bets_before_update ON direct_bets;
CREATE TRIGGER direct_bets_before_update
BEFORE UPDATE ON direct_bets
FOR EACH ROW
EXECUTE FUNCTION trg_direct_bets_before_update();

/* ---------------------------------------------------------------------------
  AFTER UPDATE TRIGGER ON direct_bets
   DOES:
   - Writes a JSON diff to bet_audit_log on any update
   - On PENDING→ACTIVE (accept): HOLD both users’ stakes (AVAILABLE→HELD)
   - On RESOLVED:
       * RELEASE both holds (HELD→AVAILABLE)
       * If VOID: stop there
       * Else: PAYOUT winner with winnings (EVENS or ODDS model) minus fee
         (fee credited to house account from app_settings.house_user_id)
   - On DISPUTED: just audit (funds remain HELD)
   - On PENDING→CANCELED/EXPIRED: audit; add refund releases if you pre-hold
   - Emits NOTIFY hooks you can subscribe to in your worker (optional)
---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION trg_direct_bets_after_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  actor BIGINT := app__current_user_id();
  tx BIGINT;
BEGIN
  /* -- Always write a human-friendly audit record with before/after snapshots */
  INSERT INTO bet_audit_log(bet_id, actor_id, action, details)
  VALUES (NEW.bet_id, actor, 'UPDATE',
          jsonb_build_object('from', to_jsonb(OLD), 'to', to_jsonb(NEW)));

  /* -- OPTIONAL notifications for your async worker / websocket layer */
  PERFORM pg_notify('bets_changed', json_build_object(
    'bet_id', NEW.bet_id, 'old_status', OLD.status, 'new_status', NEW.status
  )::text);

  /* ----------------------
     ACCEPTANCE: PENDING→ACTIVE
     - place holds for both parties
  ----------------------- */
  IF OLD.status = 'PENDING' AND NEW.status = 'ACTIVE' THEN
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES (NEW.currency_code, 'HOLD', actor, 'Bet accepted: place holds')
    RETURNING tx_id INTO tx;

    -- Move funds: AVAILABLE(-) and HELD(+) for each participant
    INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES
        (tx, NEW.proposer_id, -NEW.stake_proposer_cents, 'AVAILABLE'),
        (tx, NEW.proposer_id,  NEW.stake_proposer_cents, 'HELD'),
        (tx, NEW.acceptor_id, -NEW.stake_acceptor_cents, 'AVAILABLE'),
        (tx, NEW.acceptor_id,  NEW.stake_acceptor_cents, 'HELD');

    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);

    RETURN NEW;
  END IF;

  /* ----------------------
     PRE-ACCEPT CANCELED/EXPIRED
     - If you pre-hold on proposal (not in this baseline), RELEASE here.
     - We only audit & notify.
  ----------------------- */
  IF OLD.status = 'PENDING' AND NEW.status IN ('CANCELED','EXPIRED') THEN
    PERFORM pg_notify('bets_canceled_or_expired', NEW.bet_id::text);
    RETURN NEW;
  END IF;

  /* ----------------------
     RESOLUTION: ACTIVE/DISPUTED → RESOLVED
     - 1) RELEASE both HELD balances back to AVAILABLE
     - 2) Compute winnings by model, apply fee, move funds to winner & house
  ----------------------- */
  IF NEW.status = 'RESOLVED' AND OLD.status IN ('ACTIVE','DISPUTED') THEN
    /* 1) RELEASE both HELD balances back to AVAILABLE */
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES (NEW.currency_code, 'RELEASE', NEW.resolved_by, 'Bet resolved: release holds')
    RETURNING tx_id INTO tx;

    INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES
        (tx, NEW.proposer_id, -NEW.stake_proposer_cents, 'HELD'),
        (tx, NEW.proposer_id,  NEW.stake_proposer_cents, 'AVAILABLE'),
        (tx, NEW.acceptor_id, -NEW.stake_acceptor_cents, 'HELD'),
        (tx, NEW.acceptor_id,  NEW.stake_acceptor_cents, 'AVAILABLE');

    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);

    -- VOID: nothing else to move after releasing holds
    IF NEW.outcome = 'VOID' THEN
      PERFORM pg_notify('bets_resolved_void', NEW.bet_id::text);
      RETURN NEW;
    END IF;

    /* 2) Compute winnings, fees, and move net money (winner gains, loser pays, house gets fee) */
    DECLARE
      winner_id BIGINT;
      loser_id  BIGINT;
      stake_winner BIGINT;
      stake_loser  BIGINT;
      winnings BIGINT;
      fee BIGINT := 0;
      house BIGINT := app__house_user_id();
      odds NUMERIC(10,4);
    BEGIN
      IF NEW.outcome = 'PROPOSER_WIN' THEN
        winner_id := NEW.proposer_id; loser_id := NEW.acceptor_id;
        stake_winner := NEW.stake_proposer_cents; stake_loser := NEW.stake_acceptor_cents;
        odds := CASE WHEN NEW.payout_model='ODDS' THEN NEW.odds_proposer ELSE NULL END;
      ELSE
        winner_id := NEW.acceptor_id; loser_id := NEW.proposer_id;
        stake_winner := NEW.stake_acceptor_cents; stake_loser := NEW.stake_proposer_cents;
        odds := CASE WHEN NEW.payout_model='ODDS' THEN NEW.odds_acceptor ELSE NULL END;
      END IF;

      IF COALESCE(NEW.payout_model,'EVENS') = 'EVENS' THEN
        winnings := stake_loser;  -- classic even-money transfer
      ELSE
        -- ODDS: decimal odds already validated > 1.0; cap by opponent stake
        winnings := LEAST( FLOOR(stake_winner * (odds - 1.0)), stake_loser );
      END IF;

      -- Fee on winnings
      IF NEW.fee_bps > 0 THEN
        fee := (winnings * NEW.fee_bps) / 10000;  -- integer division floors
      END IF;

      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES (NEW.currency_code, 'PAYOUT', NEW.resolved_by, 'Bet resolved: transfer winnings and fee')
      RETURNING tx_id INTO tx;

      -- Winner gets winnings minus fee; loser pays full winnings; house gets fee
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind) VALUES
        (tx, winner_id, winnings - fee, 'AVAILABLE'),
        (tx, loser_id,  -winnings,      'AVAILABLE');

      IF fee > 0 THEN
        INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
        VALUES (tx, house, fee, 'AVAILABLE');
      END IF;

      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);
    END;

    PERFORM pg_notify('bets_resolved', NEW.bet_id::text);
    RETURN NEW;
  END IF;

  /* ----------------------
     DISPUTED: audit/notify only (funds remain HELD)
  ----------------------- */
  IF NEW.status = 'DISPUTED' AND OLD.status = 'ACTIVE' THEN
    PERFORM pg_notify('bets_disputed', NEW.bet_id::text);
    RETURN NEW;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS direct_bets_after_update ON direct_bets;
CREATE TRIGGER direct_bets_after_update
AFTER UPDATE ON direct_bets
FOR EACH ROW
EXECUTE FUNCTION trg_direct_bets_after_update();

/* ---------------------------------------------------------------------------
  API FUNCTIONS
   - bet_propose: creates a PENDING bet (now supports payout model + fee)
   - bet_accept:  accepts a bet (locks funds via trigger; may set odds_acceptor)
   - bet_resolve: resolves a bet (releases & pays via trigger)
   - bet_dispute: marks a bet DISPUTED (funds remain HELD)
   - bet_cancel_or_expire: cancels/auto-expires a PENDING bet
---------------------------------------------------------------------------- */

-- Create a new bet proposal in PENDING
CREATE OR REPLACE FUNCTION bet_propose(
  p_proposer_id BIGINT,
  p_event_description TEXT,
  p_odds_format TEXT,
  p_odds_proposer NUMERIC,
  p_stake_proposer_cents BIGINT,
  p_currency CHAR(3),
  p_arbiter_id BIGINT DEFAULT NULL,
  p_payout_model TEXT DEFAULT 'EVENS',   -- NEW
  p_fee_bps INT DEFAULT 0                -- NEW
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE new_id BIGINT; BEGIN
  INSERT INTO direct_bets(
    proposer_id, event_description, odds_format, odds_proposer,
    stake_proposer_cents, currency_code, arbiter_id,
    payout_model, fee_bps
  )
  VALUES (
    p_proposer_id, p_event_description, p_odds_format, p_odds_proposer,
    p_stake_proposer_cents, p_currency, p_arbiter_id,
    p_payout_model, p_fee_bps
  )
  RETURNING bet_id INTO new_id;

  INSERT INTO bet_audit_log(bet_id, actor_id, action, details)
  VALUES (new_id, p_proposer_id, 'PROPOSE',
          jsonb_build_object('stake', p_stake_proposer_cents,
                             'currency', p_currency,
                             'payout_model', p_payout_model,
                             'fee_bps', p_fee_bps));

  RETURN new_id;
END $$;

-- Accept a pending bet; trigger will set ACTIVE and place holds
CREATE OR REPLACE FUNCTION bet_accept(
  p_bet_id BIGINT,
  p_acceptor_id BIGINT,
  p_stake_acceptor_cents BIGINT,
  p_odds_acceptor NUMERIC DEFAULT NULL    -- NEW (used if payout_model='ODDS')
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE b direct_bets; BEGIN
  SELECT * INTO b FROM direct_bets WHERE bet_id = p_bet_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bet % not found', p_bet_id;
  END IF;
  IF b.status <> 'PENDING' OR b.acceptor_id IS NOT NULL THEN
    RAISE EXCEPTION 'Bet % is not available to accept', p_bet_id;
  END IF;

  UPDATE direct_bets
     SET acceptor_id = p_acceptor_id,
         stake_acceptor_cents = p_stake_acceptor_cents,
         odds_acceptor = COALESCE(p_odds_acceptor, b.odds_acceptor)
   WHERE bet_id = p_bet_id;
END $$;

-- Resolve a bet with outcome ('PROPOSER_WIN'|'ACCEPTOR_WIN'|'VOID')
-- Only arbiter/admin is allowed; trigger enforces and moves money.
CREATE OR REPLACE FUNCTION bet_resolve(
  p_bet_id BIGINT,
  p_outcome TEXT,
  p_notes TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE direct_bets
     SET status = 'RESOLVED',
         outcome = p_outcome,
         outcome_notes = p_notes
   WHERE bet_id = p_bet_id;
END $$;

-- Open a dispute; parties/arbiter/admin may do this; funds stay HELD
CREATE OR REPLACE FUNCTION bet_dispute(
  p_bet_id BIGINT,
  p_notes TEXT
) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE direct_bets
     SET status = 'DISPUTED',
         outcome_notes = p_notes
   WHERE bet_id = p_bet_id;
END $$;

-- Cancel (user-initiated) or expire (system-initiated) a PENDING bet
CREATE OR REPLACE FUNCTION bet_cancel_or_expire(
  p_bet_id BIGINT,
  p_new_status TEXT  -- must be 'CANCELED' or 'EXPIRED'
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE s TEXT; BEGIN
  IF p_new_status NOT IN ('CANCELED','EXPIRED') THEN
    RAISE EXCEPTION 'Invalid terminal status %', p_new_status;
  END IF;
  SELECT status INTO s FROM direct_bets WHERE bet_id = p_bet_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bet % not found', p_bet_id;
  END IF;
  IF s <> 'PENDING' THEN
    RAISE EXCEPTION 'Only PENDING bets can be %', p_new_status;
  END IF;
  UPDATE direct_bets SET status = p_new_status WHERE bet_id = p_bet_id;
END $$;

/* ---------------------------------------------------------------------------
  Wallet guard: prevent AVAILABLE from going negative on debits
---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION trg_ledger_postings_before_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE cur_avail BIGINT; BEGIN
  -- Only guard AVAILABLE debits (amount_cents < 0)
  IF NEW.balance_kind = 'AVAILABLE' AND NEW.amount_cents < 0 THEN
    SELECT COALESCE(available_cents,0)
      INTO cur_avail
      FROM wallet_balances
     WHERE user_id = NEW.user_id
     FOR SHARE;  -- prevent concurrent writer starvation

    IF cur_avail + NEW.amount_cents < 0 THEN
      RAISE EXCEPTION 'Insufficient AVAILABLE funds for user %', NEW.user_id;
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS ledger_postings_before_insert ON ledger_postings;
CREATE TRIGGER ledger_postings_before_insert
BEFORE INSERT ON ledger_postings
FOR EACH ROW
EXECUTE FUNCTION trg_ledger_postings_before_insert();

/* ---------------------------------------------------------------------------
  Bootstrap note:
  -  must insert your house account user_id before resolving bets with fees:
      INSERT INTO app_settings(key, value) VALUES ('house_user_id','<USER_ID>');
---------------------------------------------------------------------------- */
