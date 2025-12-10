-- Add SECURITY DEFINER to bet functions so they can bypass RLS when needed
-- This allows the functions to insert into ledger_transactions and other system tables

-- Drop existing functions first to avoid conflicts
DROP FUNCTION IF EXISTS bet_accept CASCADE;
DROP FUNCTION IF EXISTS bet_propose CASCADE;
DROP FUNCTION IF EXISTS bet_resolve CASCADE;
DROP FUNCTION IF EXISTS bet_dispute CASCADE;

-- Recreate bet_accept with SECURITY DEFINER
CREATE OR REPLACE FUNCTION bet_accept(
  p_bet_id BIGINT,
  p_acceptor_id BIGINT,
  p_stake_acceptor_cents BIGINT,
  p_odds_acceptor NUMERIC DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

-- Recreate bet_propose with SECURITY DEFINER
CREATE OR REPLACE FUNCTION bet_propose(
  p_proposer_id BIGINT,
  p_event_description TEXT,
  p_odds_format TEXT,
  p_odds_proposer NUMERIC,
  p_stake_proposer_cents BIGINT,
  p_currency TEXT,
  p_arbiter_id BIGINT DEFAULT NULL,
  p_payout_model TEXT DEFAULT 'EVENS',
  p_fee_bps INT DEFAULT 0
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE new_id BIGINT; BEGIN
  INSERT INTO direct_bets(
    proposer_id, event_description, status,
    odds_format, odds_proposer,
    stake_proposer_cents, currency_code,
    arbiter_id,
    payout_model, fee_bps
  ) VALUES (
    p_proposer_id, p_event_description, 'PENDING',
    p_odds_format, p_odds_proposer,
    p_stake_proposer_cents, p_currency,
    p_arbiter_id,
    p_payout_model, p_fee_bps
  ) RETURNING bet_id INTO new_id;

  INSERT INTO bet_audit_log(bet_id, actor_id, action, details)
  VALUES (new_id, p_proposer_id, 'PROPOSE',
          jsonb_build_object('stake', p_stake_proposer_cents,
                             'currency', p_currency,
                             'payout_model', p_payout_model,
                             'fee_bps', p_fee_bps));

  RETURN new_id;
END $$;

-- Recreate bet_resolve with SECURITY DEFINER
CREATE OR REPLACE FUNCTION bet_resolve(
  p_bet_id BIGINT,
  p_outcome TEXT,
  p_notes TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE direct_bets
     SET status = 'RESOLVED',
         outcome = p_outcome,
         outcome_notes = p_notes
   WHERE bet_id = p_bet_id;
END $$;

-- Recreate bet_dispute with SECURITY DEFINER
CREATE OR REPLACE FUNCTION bet_dispute(
  p_bet_id BIGINT,
  p_notes TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE direct_bets
     SET status = 'DISPUTED',
         outcome_notes = p_notes
   WHERE bet_id = p_bet_id;
END $$;

COMMENT ON FUNCTION bet_accept IS 'Accept a pending bet - runs with elevated privileges to manage ledger';
COMMENT ON FUNCTION bet_propose IS 'Propose a new bet - runs with elevated privileges to manage ledger';
COMMENT ON FUNCTION bet_resolve IS 'Resolve a bet - runs with elevated privileges to manage ledger';
COMMENT ON FUNCTION bet_dispute IS 'Dispute a bet - runs with elevated privileges';

