-- ============================================================================
-- Simplify trigger and ensure it works - add explicit error handling
-- ============================================================================

-- First, let's make absolutely sure the trigger is dropped and recreated
DROP TRIGGER IF EXISTS direct_bets_after_insert ON direct_bets CASCADE;

-- Trigger function to hold funds when bet is created
CREATE OR REPLACE FUNCTION trg_direct_bets_after_insert()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor BIGINT;
  tx BIGINT;
  available_balance_cents BIGINT;
  wallet_balance_cents BIGINT;
  has_ledger_entries BOOLEAN;
  v_error_text TEXT;
BEGIN
  -- Get actor, fallback to proposer_id if app__current_user_id() returns NULL
  BEGIN
    actor := app__current_user_id();
  EXCEPTION WHEN OTHERS THEN
    actor := NULL;
  END;
  
  IF actor IS NULL THEN
    actor := NEW.proposer_id;
  END IF;
  
  -- When a bet is created in PENDING status, hold the proposer's funds
  IF NEW.status = 'PENDING' THEN
    -- Check if proposer has ledger entries
    BEGIN
      SELECT COUNT(*) > 0 INTO has_ledger_entries
      FROM ledger_postings
      WHERE user_id = NEW.proposer_id;
    EXCEPTION WHEN OTHERS THEN
      has_ledger_entries := FALSE;
    END;
    
    -- Calculate available balance from ledger
    BEGIN
      SELECT COALESCE(SUM(CASE WHEN balance_kind='AVAILABLE' THEN amount_cents ELSE 0 END), 0)
      INTO available_balance_cents
      FROM ledger_postings
      WHERE user_id = NEW.proposer_id;
    EXCEPTION WHEN OTHERS THEN
      available_balance_cents := 0;
    END;
    
    -- If no ledger entries exist, we need to create initial balance from wallet_balance
    IF NOT has_ledger_entries OR available_balance_cents = 0 THEN
      BEGIN
        -- Get wallet_balance from users table
        SELECT (wallet_balance * 100)::BIGINT
        INTO wallet_balance_cents
        FROM users
        WHERE user_id = NEW.proposer_id;
        
        -- If user has wallet_balance but no ledger entries, create initial DEPOSIT
        IF wallet_balance_cents > 0 THEN
          -- Create initial deposit transaction to establish AVAILABLE balance
          INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
          VALUES (NEW.currency_code, 'DEPOSIT', actor, 'Initial balance from wallet')
          RETURNING tx_id INTO tx;
          
          -- Create AVAILABLE balance entry
          INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
          VALUES (tx, NEW.proposer_id, wallet_balance_cents, 'AVAILABLE');
          
          -- Now available_balance_cents equals wallet_balance_cents
          available_balance_cents := wallet_balance_cents;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error_text = MESSAGE_TEXT;
        RAISE EXCEPTION 'Error creating initial balance: %', v_error_text;
      END;
    END IF;
    
    -- Check if user has enough funds
    IF available_balance_cents < NEW.stake_proposer_cents THEN
      RAISE EXCEPTION 'Insufficient funds. Available: $%, Required: $%',
        (available_balance_cents / 100.0)::NUMERIC(12,2),
        (NEW.stake_proposer_cents / 100.0)::NUMERIC(12,2);
    END IF;
    
    -- Create ledger transaction to hold funds
    BEGIN
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES (NEW.currency_code, 'HOLD', actor, 'Bet proposed: hold proposer funds')
      RETURNING tx_id INTO tx;
      
      -- Move funds from AVAILABLE to HELD for proposer
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES
        (tx, NEW.proposer_id, -NEW.stake_proposer_cents, 'AVAILABLE'),
        (tx, NEW.proposer_id,  NEW.stake_proposer_cents, 'HELD');
      
      -- Link transaction to bet
      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_error_text = MESSAGE_TEXT;
      RAISE EXCEPTION 'Error creating hold transaction: %', v_error_text;
    END;
  END IF;
  
  RETURN NEW;
END $$;

-- Recreate the trigger
CREATE TRIGGER direct_bets_after_insert
AFTER INSERT ON direct_bets
FOR EACH ROW
EXECUTE FUNCTION trg_direct_bets_after_insert();

COMMENT ON FUNCTION trg_direct_bets_after_insert() IS 
  'Holds proposer funds when bet is created. Runs with SECURITY DEFINER to bypass RLS.';

