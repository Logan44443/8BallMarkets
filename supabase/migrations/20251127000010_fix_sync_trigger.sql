-- ============================================================================
-- Fix sync trigger to use SECURITY DEFINER and add logging
-- ============================================================================

-- Function to sync wallet_balance after ledger posting changes
CREATE OR REPLACE FUNCTION sync_wallet_balance_from_ledger()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  affected_user_id BIGINT;
  new_balance NUMERIC;
BEGIN
  -- Get the user_id from the NEW or OLD record
  IF TG_OP = 'DELETE' THEN
    affected_user_id := OLD.user_id;
  ELSE
    affected_user_id := NEW.user_id;
  END IF;
  
  -- Calculate new balance from ledger
  SELECT 
    (COALESCE(SUM(CASE WHEN balance_kind='AVAILABLE' THEN amount_cents ELSE 0 END), 0) +
     COALESCE(SUM(CASE WHEN balance_kind='HELD' THEN amount_cents ELSE 0 END), 0)) / 100.0
  INTO new_balance
  FROM ledger_postings
  WHERE user_id = affected_user_id;
  
  -- Update the user's wallet_balance to match ledger
  UPDATE users
  SET wallet_balance = new_balance,
      updated_at = NOW()
  WHERE user_id = affected_user_id;
  
  RAISE NOTICE 'Synced wallet_balance for user % to $%', affected_user_id, new_balance;
  
  RETURN COALESCE(NEW, OLD);
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error syncing wallet_balance for user %: %', affected_user_id, SQLERRM;
    RETURN COALESCE(NEW, OLD);
END $$;

-- Ensure trigger exists
DROP TRIGGER IF EXISTS trg_sync_wallet_balance ON ledger_postings;
CREATE TRIGGER trg_sync_wallet_balance
AFTER INSERT OR UPDATE OR DELETE ON ledger_postings
FOR EACH ROW
EXECUTE FUNCTION sync_wallet_balance_from_ledger();

COMMENT ON FUNCTION sync_wallet_balance_from_ledger() IS 
  'Trigger function that keeps users.wallet_balance in sync with ledger_postings. Uses SECURITY DEFINER to bypass RLS.';

