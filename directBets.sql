CREATE TABLE direct_bets (
  bet_id               BIGSERIAL PRIMARY KEY,

  proposer_id          BIGINT NOT NULL REFERENCES users(user_id),
  acceptor_id          BIGINT     REFERENCES users(user_id),  
  arbiter_id           BIGINT     REFERENCES users(user_id),  

  
  status               TEXT NOT NULL DEFAULT 'PENDING'
                       CHECK (status IN ('PENDING','ACTIVE','RESOLVED','DISPUTED','CANCELED','EXPIRED')),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  accepted_at          TIMESTAMPTZ,
  resolved_at          TIMESTAMPTZ,

 
  event_description    TEXT NOT NULL,
  odds_format          TEXT NOT NULL DEFAULT 'DECIMAL'
                       CHECK (odds_format IN ('DECIMAL','AMERICAN','FRACTIONAL')),
  odds_proposer        NUMERIC(10,4),  

  
  stake_proposer_cents BIGINT NOT NULL CHECK (stake_proposer_cents > 0),
  stake_acceptor_cents BIGINT          CHECK (stake_acceptor_cents IS NULL OR stake_acceptor_cents > 0),
  currency_code        CHAR(3) NOT NULL DEFAULT 'USD',

  
  outcome              TEXT
                       CHECK (outcome IN ('PROPOSER_WIN','ACCEPTOR_WIN','VOID')),
  resolved_by          BIGINT REFERENCES users(user_id),
  outcome_notes        TEXT,

  
  CHECK (proposer_id IS DISTINCT FROM acceptor_id),
  CHECK (
    arbiter_id IS NULL OR
    (arbiter_id IS DISTINCT FROM proposer_id AND arbiter_id IS DISTINCT FROM acceptor_id)
  )
);


CREATE INDEX idx_direct_bets_status      ON direct_bets(status);
CREATE INDEX idx_direct_bets_proposer    ON direct_bets(proposer_id);
CREATE INDEX idx_direct_bets_acceptor    ON direct_bets(acceptor_id);
CREATE INDEX idx_direct_bets_created_at  ON direct_bets(created_at);
CREATE INDEX idx_direct_bets_resolved_at ON direct_bets(resolved_at);

-- -------------------------------------------------------------------
-- triggers:
-- -------------------------------------------------------------------
-- 1) BEFORE UPDATE: accepting a bet
--    - Fires when acceptor_id transitions from NULL -> NOT NULL.
--    - Validate stake_acceptor_cents > 0.
--    - Set accepted_at = NOW() and status = 'ACTIVE'.
--    - (Optional) Prevent changes to proposer terms after acceptance.

-- 2) BEFORE UPDATE: enforcing valid status transitions
--    - PENDING -> ACTIVE requires acceptor_id set.
--    - ACTIVE -> RESOLVED requires outcome NOT NULL; set resolved_at = NOW().
--    - Block any transitions out of RESOLVED (immutable terminal state).

-- 3) BEFORE UPDATE: authorization guard for resolution
--    - Only arbiter_id (or an admin/system role) may change status to RESOLVED/DISPUTED.
--    - Set resolved_by = arbiter_id (or actor).

-- 4) BEFORE UPDATE/INSERT: stake immutability & currency
--    - Disallow changing stake_* fields after acceptance.
--    - Enforce both stakes share the same currency_code.

-- 5) AFTER UPDATE: auto-expire/cancel handling
--    - If status becomes CANCELED/EXPIRED before acceptance, emit an event
--      (or call a function) to refund/clear any provisional holds upstream.

-- 6) AFTER UPDATE: audit hook
--    - On RESOLVED, emit an event for the ledger module to create payouts/refunds,
--      ensuring atomic wallet updates occur in the same DB transaction.

-- 7) BEFORE UPDATE: dispute entry rules
--    - Allow status -> DISPUTED only from ACTIVE.
--    - Optionally require outcome_notes describing the dispute context.
