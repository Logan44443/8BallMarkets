-- ============================================================================
-- Create initial ledger entries for users who have wallet_balance but no ledger entries
-- ============================================================================
-- This ensures all users have proper ledger entries matching their wallet_balance

DO $$
DECLARE
  user_record RECORD;
  tx_id_val BIGINT;
  wallet_cents BIGINT;
BEGIN
  -- Loop through all users
  FOR user_record IN 
    SELECT user_id, wallet_balance 
    FROM users 
    WHERE wallet_balance > 0
  LOOP
    -- Check if user has any ledger entries
    IF NOT EXISTS (
      SELECT 1 FROM ledger_postings WHERE user_id = user_record.user_id
    ) THEN
      -- User has balance but no ledger entries - create initial deposit
      wallet_cents := (user_record.wallet_balance * 100)::BIGINT;
      
      -- Create deposit transaction
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES ('USD', 'DEPOSIT', user_record.user_id, 'Initial balance migration')
      RETURNING tx_id INTO tx_id_val;
      
      -- Create AVAILABLE balance entry
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES (tx_id_val, user_record.user_id, wallet_cents, 'AVAILABLE');
      
      RAISE NOTICE 'Created initial ledger entry for user % with balance $%', 
        user_record.user_id, user_record.wallet_balance;
    END IF;
  END LOOP;
  
  RAISE NOTICE 'Migration complete: All users with wallet_balance now have ledger entries';
END $$;

