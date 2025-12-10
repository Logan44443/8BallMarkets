-- ============================================================================
-- Sync wallet_balance with ledger system
-- ============================================================================
-- This migration ensures that users.wallet_balance is always in sync with
-- the actual ledger postings (the source of truth for betting)

-- Function to calculate a user's total balance from ledger postings
CREATE OR REPLACE FUNCTION calculate_user_balance(p_user_id BIGINT)
RETURNS NUMERIC AS $$
DECLARE
  v_available_cents BIGINT;
  v_held_cents BIGINT;
BEGIN
  -- Get sum of AVAILABLE and HELD balances from ledger
  SELECT 
    COALESCE(SUM(CASE WHEN balance_kind='AVAILABLE' THEN amount_cents ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN balance_kind='HELD' THEN amount_cents ELSE 0 END), 0)
  INTO v_available_cents, v_held_cents
  FROM ledger_postings
  WHERE user_id = p_user_id;
  
  -- Total balance = AVAILABLE + HELD (convert cents to dollars)
  RETURN (v_available_cents + v_held_cents) / 100.0;
END;
$$ LANGUAGE plpgsql;

-- Function to sync wallet_balance after ledger posting changes
CREATE OR REPLACE FUNCTION sync_wallet_balance_from_ledger()
RETURNS TRIGGER AS $$
DECLARE
  affected_user_id BIGINT;
BEGIN
  -- Get the user_id from the NEW or OLD record
  IF TG_OP = 'DELETE' THEN
    affected_user_id := OLD.user_id;
  ELSE
    affected_user_id := NEW.user_id;
  END IF;
  
  -- Update the user's wallet_balance to match ledger
  UPDATE users
  SET wallet_balance = calculate_user_balance(affected_user_id),
      updated_at = NOW()
  WHERE user_id = affected_user_id;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger: Sync wallet_balance whenever ledger_postings change
DROP TRIGGER IF EXISTS trg_sync_wallet_balance ON ledger_postings;
CREATE TRIGGER trg_sync_wallet_balance
AFTER INSERT OR UPDATE OR DELETE ON ledger_postings
FOR EACH ROW
EXECUTE FUNCTION sync_wallet_balance_from_ledger();

-- One-time sync: Update all existing users' balances from ledger
DO $$
DECLARE
  user_record RECORD;
  new_balance NUMERIC;
BEGIN
  FOR user_record IN SELECT user_id FROM users LOOP
    new_balance := calculate_user_balance(user_record.user_id);
    
    UPDATE users
    SET wallet_balance = new_balance,
        updated_at = NOW()
    WHERE user_id = user_record.user_id;
  END LOOP;
  
  RAISE NOTICE 'Synced wallet balances for all users from ledger';
END $$;

-- Add helpful comment
COMMENT ON FUNCTION calculate_user_balance(BIGINT) IS 
  'Calculates user total balance (AVAILABLE + HELD) from ledger_postings in dollars';
  
COMMENT ON FUNCTION sync_wallet_balance_from_ledger() IS 
  'Trigger function that keeps users.wallet_balance in sync with ledger_postings';

