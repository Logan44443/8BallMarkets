-- ============================================================================
-- Fix RLS policy for bet_ledger_links to allow SELECT
-- ============================================================================

-- Drop the existing policy
DROP POLICY IF EXISTS "bet_ledger_links_system_all" ON bet_ledger_links;

-- Create separate policies for different operations
-- Allow SELECT for users who are participants in the bet
CREATE POLICY "bet_ledger_links_select_participant" ON bet_ledger_links
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM direct_bets 
      WHERE direct_bets.bet_id = bet_ledger_links.bet_id 
      AND (
        direct_bets.proposer_id = auth_user_id() 
        OR direct_bets.acceptor_id = auth_user_id() 
        OR direct_bets.arbiter_id = auth_user_id()
      )
    )
  );

-- Allow all system operations (INSERT/UPDATE/DELETE) - for triggers/functions
CREATE POLICY "bet_ledger_links_system_modify" ON bet_ledger_links
  FOR ALL
  WITH CHECK (true);

