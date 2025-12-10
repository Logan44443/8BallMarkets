-- ============================================================================
-- Fix balance calculation to show AVAILABLE only (not AVAILABLE + HELD)
-- Users should see their spendable balance, not total including held funds
-- ============================================================================

-- Function to calculate a user's AVAILABLE balance from ledger postings
CREATE OR REPLACE FUNCTION calculate_user_balance(p_user_id BIGINT)
RETURNS NUMERIC 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_available_cents BIGINT;
BEGIN
  -- Get sum of AVAILABLE balance only (not HELD - those are locked in bets)
  SELECT 
    COALESCE(SUM(CASE WHEN balance_kind='AVAILABLE' THEN amount_cents ELSE 0 END), 0)
  INTO v_available_cents
  FROM ledger_postings
  WHERE user_id = p_user_id;
  
  -- Return AVAILABLE balance only (convert cents to dollars)
  RETURN v_available_cents / 100.0;
END $$;

-- Update sync trigger to use AVAILABLE only
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
  
  -- Calculate new balance from ledger (AVAILABLE only)
  SELECT 
    COALESCE(SUM(CASE WHEN balance_kind='AVAILABLE' THEN amount_cents ELSE 0 END), 0) / 100.0
  INTO new_balance
  FROM ledger_postings
  WHERE user_id = affected_user_id;
  
  -- Update the user's wallet_balance to match AVAILABLE balance
  UPDATE users
  SET wallet_balance = new_balance,
      updated_at = NOW()
  WHERE user_id = affected_user_id;
  
  RAISE NOTICE 'Synced wallet_balance for user % to $% (AVAILABLE only)', affected_user_id, new_balance;
  
  RETURN COALESCE(NEW, OLD);
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error syncing wallet_balance for user %: %', affected_user_id, SQLERRM;
    RETURN COALESCE(NEW, OLD);
END $$;

COMMENT ON FUNCTION calculate_user_balance(BIGINT) IS 
  'Calculates user AVAILABLE balance (spendable funds) from ledger_postings in dollars. HELD funds are excluded.';

COMMENT ON FUNCTION sync_wallet_balance_from_ledger() IS 
  'Trigger function that keeps users.wallet_balance in sync with AVAILABLE ledger_postings only.';

