-- ============================================================================
-- Expose calculate_user_balance as an RPC function so frontend can call it
-- ============================================================================

-- The function already exists, we just need to make sure it's accessible
-- It's already a regular function, but let's verify it works as RPC

-- Function is already created in 20251125000500_sync_wallet_balance.sql
-- Just add a comment that it can be called via RPC

COMMENT ON FUNCTION calculate_user_balance(BIGINT) IS 
  'Calculates user total balance (AVAILABLE + HELD) from ledger_postings in dollars. Can be called via RPC.';

