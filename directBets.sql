/* ============================================================================
 Direct Bets Guru — COMPLETE Postgres schema & business logic
 ------------------------------------------------------------------------------
 - Table `direct_bets` with strict constraints and a well-defined status machine.
 - Minimal double-entry-style ledger (`ledger_transactions`, `ledger_postings`)
   that moves money between AVAILABLE and HELD “buckets”.
 - Full audit trail (`bet_audit_log`) + link table tying ledger txs to bets.
 - Triggers to enforce:
     * acceptance rules + stake immutability
     * valid status transitions (PENDING→ACTIVE→RESOLVED/DISPUTED etc.)
     * authorization for RESOLVED/DISPUTED (arbiter or admin)
     * automatic wallet postings on accept / resolve / cancel-expire paths
 - Convenience functions: propose / accept / resolve / dispute / cancel-expire
 - Optional hooks & notes for: fees, odds-based payout math, notifications,
   and stronger wallet balance enforcement.

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

  -- description & odds (odds not used for payout in baseline)
  event_description    TEXT NOT NULL,
  odds_format          TEXT NOT NULL DEFAULT 'DECIMAL'
                       CHECK (odds_format IN ('DECIMAL','AMERICAN','FRACTIONAL')),
  odds_proposer        NUMERIC(10,4),  -- proposer’s view of odds; informational for now

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
HELPERS: read app auth flags (GUCs)
   - app.current_user_id: BIGINT (nullable)
   - app.current_is_admin: 'on'/'off' (defaults to 'off' if missing)
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

/* ---------------------------------------------------------------------------
 4) BEFORE UPDATE TRIGGER ON direct_bets
   ENFORCES:
   - Accept flow (NULL→NOT NULL acceptor): require stake, set accepted_at, set ACTIVE
   - Currency immutability after acceptance
   - Status state machine + authorizations:
       * PENDING→ACTIVE requires acceptor_id set
       * ACTIVE→RESOLVED requires outcome and arbiter/admin authorization
       * ACTIVE→DISPUTED requires notes and party/arbiter/admin authorization
       * DISPUTED→RESOLVED requires outcome and arbiter/admin authorization
       * RESOLVED/CANCELED/EXPIRED are terminal (immutable)
   - Stake/terms immutability after acceptance
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

    -- freeze core terms right at accept time
    IF NEW.stake_proposer_cents <> OLD.stake_proposer_cents
       OR NEW.odds_format <> OLD.odds_format
       OR NEW.odds_proposer <> OLD.odds_proposer
       OR NEW.event_description <> OLD.event_description THEN
      RAISE EXCEPTION 'Proposer terms are immutable upon acceptance';
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

  /* -- Stakes become immutable after acceptance */
  IF OLD.acceptor_id IS NOT NULL THEN
    IF NEW.stake_proposer_cents <> OLD.stake_proposer_cents
       OR NEW.stake_acceptor_cents <> OLD.stake_acceptor_cents THEN
      RAISE EXCEPTION 'Stake fields are immutable after acceptance';
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
 5) AFTER UPDATE TRIGGER ON direct_bets
   DOES:
   - Writes a JSON diff to bet_audit_log on any update
   - On PENDING→ACTIVE (accept): HOLD both users’ stakes (AVAILABLE→HELD)
   - On RESOLVED:
       * RELEASE both holds (HELD→AVAILABLE)
       * If VOID: stop there
       * Else: PAYOUT the winner with the total pot
         (baseline math; odds/fees hooks included as TODO)
   - On DISPUTED: just audit (funds remain HELD)
   - On PENDING→CANCELED/EXPIRED: audit; add refund releases if you pre-hold
   - Emits NOTIFY hooks you can subscribe to in your worker (optional)
---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION trg_direct_bets_after_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  actor BIGINT := app__current_user_id();
  tx BIGINT;
  pot BIGINT;
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
     - 1) RELEASE both holds back to AVAILABLE (unlocks money)
     - 2) If VOID, stop. Otherwise PAYOUT winner with total pot.
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

    -- VOID outcome: no payout after releasing holds
    IF NEW.outcome = 'VOID' THEN
      PERFORM pg_notify('bets_resolved_void', NEW.bet_id::text);
      RETURN NEW;
    END IF;

    /* 2) PAYOUT winner with the full pot (baseline, odds ignored) */
    pot := NEW.stake_proposer_cents + NEW.stake_acceptor_cents;

    /* --------------------------------------------------------------------
       TODO (Fees): If charging fees, compute fee_cents here and post
       an extra line to a house account. E.g. fee_cents := (pot * fee_bps)/10000
       Then pay (pot - fee_cents) to winner, and credit fee to house.
       You would also add house_account_user_id to users and reference it here.
       -------------------------------------------------------------------- */

    /* --------------------------------------------------------------------
       TODO (Odds-based settlement): If you want to honor odds, replace the
       simple 'pot' payout below with odds math that computes each side’s
       risk & win and pays the correct amount (cap by stakes). The state
       machine and holds remain correct; only payout math changes.
       -------------------------------------------------------------------- */

    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES (NEW.currency_code, 'PAYOUT', NEW.resolved_by, 'Bet resolved: payout winner')
    RETURNING tx_id INTO tx;

    IF NEW.outcome = 'PROPOSER_WIN' THEN
      -- credit winner’s AVAILABLE with the total pot, balance with losers’ offsets
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
        VALUES
          (tx, NEW.proposer_id,  pot, 'AVAILABLE'),
          (tx, NEW.proposer_id, -NEW.stake_proposer_cents, 'AVAILABLE'),
          (tx, NEW.acceptor_id, -NEW.stake_acceptor_cents, 'AVAILABLE');
    ELSIF NEW.outcome = 'ACCEPTOR_WIN' THEN
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
        VALUES
          (tx, NEW.acceptor_id,  pot, 'AVAILABLE'),
          (tx, NEW.proposer_id, -NEW.stake_proposer_cents, 'AVAILABLE'),
          (tx, NEW.acceptor_id, -NEW.stake_acceptor_cents, 'AVAILABLE');
    END IF;

    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);

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
   - bet_propose: creates a PENDING bet
   - bet_accept:   accepts a bet (locks funds via trigger)
   - bet_resolve:  resolves a bet (releases & pays via trigger)
   - bet_dispute:  marks a bet DISPUTED (funds remain HELD)
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
  p_arbiter_id BIGINT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE new_id BIGINT; BEGIN
  INSERT INTO direct_bets(
    proposer_id, event_description, odds_format, odds_proposer,
    stake_proposer_cents, currency_code, arbiter_id
  )
  VALUES (p_proposer_id, p_event_description, p_odds_format, p_odds_proposer,
          p_stake_proposer_cents, p_currency, p_arbiter_id)
  RETURNING bet_id INTO new_id;

  INSERT INTO bet_audit_log(bet_id, actor_id, action, details)
  VALUES (new_id, p_proposer_id, 'PROPOSE',
          jsonb_build_object('stake', p_stake_proposer_cents, 'currency', p_currency));

  RETURN new_id;
END $$;

-- Accept a pending bet; trigger will set ACTIVE and place holds
CREATE OR REPLACE FUNCTION bet_accept(
  p_bet_id BIGINT,
  p_acceptor_id BIGINT,
  p_stake_acceptor_cents BIGINT
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
         stake_acceptor_cents = p_stake_acceptor_cents
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


