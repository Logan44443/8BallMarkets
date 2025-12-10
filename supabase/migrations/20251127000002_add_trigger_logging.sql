-- ============================================================================
-- Add logging to trigger to debug why it's not working
-- ============================================================================

-- Trigger function to hold funds when bet is created
CREATE OR REPLACE FUNCTION trg_direct_bets_after_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  actor BIGINT := app__current_user_id();
  tx BIGINT;
  available_balance_cents BIGINT;
  wallet_balance_cents BIGINT;
  has_ledger_entries BOOLEAN;
BEGIN
  RAISE NOTICE 'Trigger fired for bet_id: %, proposer_id: %, status: %', NEW.bet_id, NEW.proposer_id, NEW.status;
  
  -- When a bet is created in PENDING status, hold the proposer's funds
  IF NEW.status = 'PENDING' THEN
    RAISE NOTICE 'Bet is PENDING, checking balance...';
    
    -- Check if proposer has ledger entries
    SELECT COUNT(*) > 0 INTO has_ledger_entries
    FROM ledger_postings
    WHERE user_id = NEW.proposer_id;
    
    RAISE NOTICE 'Has ledger entries: %', has_ledger_entries;
    
    -- Calculate available balance from ledger
    SELECT COALESCE(SUM(CASE WHEN balance_kind='AVAILABLE' THEN amount_cents ELSE 0 END), 0)
    INTO available_balance_cents
    FROM ledger_postings
    WHERE user_id = NEW.proposer_id;
    
    RAISE NOTICE 'Available balance from ledger: % cents', available_balance_cents;
    
    -- If no ledger entries exist, we need to create initial balance from wallet_balance
    IF NOT has_ledger_entries THEN
      RAISE NOTICE 'No ledger entries, checking wallet_balance...';
      
      -- Get wallet_balance from users table
      SELECT (wallet_balance * 100)::BIGINT
      INTO wallet_balance_cents
      FROM users
      WHERE user_id = NEW.proposer_id;
      
      RAISE NOTICE 'Wallet balance: % cents', wallet_balance_cents;
      
      -- If user has wallet_balance but no ledger entries, create initial DEPOSIT
      IF wallet_balance_cents > 0 THEN
        RAISE NOTICE 'Creating initial deposit transaction...';
        
        -- Create initial deposit transaction to establish AVAILABLE balance
        INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
        VALUES (NEW.currency_code, 'DEPOSIT', COALESCE(actor, NEW.proposer_id), 
                'Initial balance from wallet')
        RETURNING tx_id INTO tx;
        
        RAISE NOTICE 'Created deposit transaction: tx_id = %', tx;
        
        -- Create AVAILABLE balance entry
        INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
        VALUES (tx, NEW.proposer_id, wallet_balance_cents, 'AVAILABLE');
        
        RAISE NOTICE 'Created AVAILABLE posting: % cents', wallet_balance_cents;
        
        -- Now available_balance_cents equals wallet_balance_cents
        available_balance_cents := wallet_balance_cents;
      END IF;
    END IF;
    
    -- Check if user has enough funds
    IF available_balance_cents < NEW.stake_proposer_cents THEN
      RAISE EXCEPTION 'Insufficient funds. Available: $%, Required: $%',
        (available_balance_cents / 100.0)::NUMERIC(12,2),
        (NEW.stake_proposer_cents / 100.0)::NUMERIC(12,2);
    END IF;
    
    RAISE NOTICE 'Creating HOLD transaction for % cents...', NEW.stake_proposer_cents;
    
    -- Create ledger transaction to hold funds
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES (NEW.currency_code, 'HOLD', COALESCE(actor, NEW.proposer_id), 
            'Bet proposed: hold proposer funds')
    RETURNING tx_id INTO tx;
    
    RAISE NOTICE 'Created HOLD transaction: tx_id = %', tx;
    
    -- Move funds from AVAILABLE to HELD for proposer
    INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
    VALUES
      (tx, NEW.proposer_id, -NEW.stake_proposer_cents, 'AVAILABLE'),
      (tx, NEW.proposer_id,  NEW.stake_proposer_cents, 'HELD');
    
    RAISE NOTICE 'Created ledger postings: -% AVAILABLE, +% HELD', NEW.stake_proposer_cents, NEW.stake_proposer_cents;
    
    -- Link transaction to bet
    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);
    
    RAISE NOTICE 'Linked transaction to bet';
  END IF;
  
  RAISE NOTICE 'Trigger completed successfully';
  RETURN NEW;
END $$;

