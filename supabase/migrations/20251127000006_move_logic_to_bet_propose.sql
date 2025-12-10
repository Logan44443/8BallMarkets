-- ============================================================================
-- Move the fund holding logic directly into bet_propose function
-- This way we can see errors and have more control
-- ============================================================================

-- Update bet_propose to hold funds immediately
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
DECLARE 
  new_id BIGINT;
  tx BIGINT;
  available_balance_cents BIGINT;
  wallet_balance_cents BIGINT;
  has_ledger_entries BOOLEAN;
BEGIN
  -- Create the bet first
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

  -- Audit log
  INSERT INTO bet_audit_log(bet_id, actor_id, action, details)
  VALUES (new_id, p_proposer_id, 'PROPOSE',
          jsonb_build_object('stake', p_stake_proposer_cents,
                             'currency', p_currency,
                             'payout_model', p_payout_model,
                             'fee_bps', p_fee_bps));

  -- Now hold the funds
  -- Check if proposer has ledger entries
  SELECT COUNT(*) > 0 INTO has_ledger_entries
  FROM ledger_postings
  WHERE user_id = p_proposer_id;
  
  -- Calculate available balance from ledger
  SELECT COALESCE(SUM(CASE WHEN balance_kind='AVAILABLE' THEN amount_cents ELSE 0 END), 0)
  INTO available_balance_cents
  FROM ledger_postings
  WHERE user_id = p_proposer_id;
  
  -- If no ledger entries exist, create initial balance from wallet_balance
  IF NOT has_ledger_entries OR available_balance_cents = 0 THEN
    -- Get wallet_balance from users table
    SELECT (wallet_balance * 100)::BIGINT
    INTO wallet_balance_cents
    FROM users
    WHERE user_id = p_proposer_id;
    
    -- If user has wallet_balance but no ledger entries, create initial DEPOSIT
    IF wallet_balance_cents > 0 THEN
      -- Create initial deposit transaction to establish AVAILABLE balance
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES (p_currency, 'DEPOSIT', p_proposer_id, 'Initial balance from wallet')
      RETURNING tx_id INTO tx;
      
      -- Create AVAILABLE balance entry
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES (tx, p_proposer_id, wallet_balance_cents, 'AVAILABLE');
      
      -- Now available_balance_cents equals wallet_balance_cents
      available_balance_cents := wallet_balance_cents;
    END IF;
  END IF;
  
  -- Check if user has enough funds
  IF available_balance_cents < p_stake_proposer_cents THEN
    RAISE EXCEPTION 'Insufficient funds. Available: $%, Required: $%',
      (available_balance_cents / 100.0)::NUMERIC(12,2),
      (p_stake_proposer_cents / 100.0)::NUMERIC(12,2);
  END IF;
  
  -- Create ledger transaction to hold funds
  INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
  VALUES (p_currency, 'HOLD', p_proposer_id, 'Bet proposed: hold proposer funds')
  RETURNING tx_id INTO tx;
  
  -- Move funds from AVAILABLE to HELD for proposer
  INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
  VALUES
    (tx, p_proposer_id, -p_stake_proposer_cents, 'AVAILABLE'),
    (tx, p_proposer_id,  p_stake_proposer_cents, 'HELD');
  
  -- Link transaction to bet
  INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (new_id, tx);

  RETURN new_id;
END $$;

COMMENT ON FUNCTION bet_propose IS 'Propose a new bet and hold proposer funds immediately';

