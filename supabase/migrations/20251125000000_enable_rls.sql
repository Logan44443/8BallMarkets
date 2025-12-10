-- ============================================================================
-- MILESTONE 4: Enable Row Level Security (RLS) - MVP Tables Only
-- ============================================================================
-- This migration enables RLS on tables that actually exist after MVP cleanup
-- Tables that were dropped: User_Sessions, Password_Reset_Tokens,
-- Email_Verification_Tokens, User_Preferences, Reputation_Logs, 
-- Achievements, User_Statistics

-- ============================================================================
-- ENABLE RLS ON EXISTING MVP TABLES
-- ============================================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE Transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE direct_bets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledger_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledger_postings ENABLE ROW LEVEL SECURITY;
ALTER TABLE bet_ledger_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE bet_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE Bet_Threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE Comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE friends ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION auth_user_id() RETURNS BIGINT AS $$
BEGIN
  RETURN NULLIF(current_setting('app.current_user_id', true), '')::BIGINT;
EXCEPTION
  WHEN OTHERS THEN RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION auth_is_admin() RETURNS BOOLEAN AS $$
DECLARE
  v_user_id BIGINT;
BEGIN
  v_user_id := auth_user_id();
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;
  
  RETURN EXISTS (
    SELECT 1 FROM users 
    WHERE user_id = v_user_id 
    AND is_admin = TRUE 
    AND is_active = TRUE
  );
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- USERS TABLE POLICIES
-- ============================================================================

CREATE POLICY "users_select_public" ON users
  FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "users_update_own" ON users
  FOR UPDATE
  USING (user_id = auth_user_id())
  WITH CHECK (user_id = auth_user_id());

CREATE POLICY "users_admin_all" ON users
  FOR ALL
  USING (auth_is_admin())
  WITH CHECK (auth_is_admin());

CREATE POLICY "users_insert_signup" ON users
  FOR INSERT
  WITH CHECK (true);

-- ============================================================================
-- TRANSACTIONS TABLE POLICIES
-- ============================================================================

CREATE POLICY "transactions_select_own" ON Transactions
  FOR SELECT
  USING (user_id = auth_user_id());

CREATE POLICY "transactions_admin_select" ON Transactions
  FOR SELECT
  USING (auth_is_admin());

CREATE POLICY "transactions_system_insert" ON Transactions
  FOR INSERT
  WITH CHECK (true);

-- ============================================================================
-- DIRECT BETS POLICIES
-- ============================================================================

CREATE POLICY "direct_bets_select_participant" ON direct_bets
  FOR SELECT
  USING (
    proposer_id = auth_user_id() 
    OR acceptor_id = auth_user_id() 
    OR arbiter_id = auth_user_id()
  );

CREATE POLICY "direct_bets_select_pending" ON direct_bets
  FOR SELECT
  USING (status = 'PENDING' AND acceptor_id IS NULL);

CREATE POLICY "direct_bets_insert_own" ON direct_bets
  FOR INSERT
  WITH CHECK (proposer_id = auth_user_id());

CREATE POLICY "direct_bets_update_accept" ON direct_bets
  FOR UPDATE
  USING (status = 'PENDING' AND acceptor_id IS NULL)
  WITH CHECK (acceptor_id = auth_user_id());

CREATE POLICY "direct_bets_update_cancel_proposer" ON direct_bets
  FOR UPDATE
  USING (status = 'PENDING' AND proposer_id = auth_user_id())
  WITH CHECK (status IN ('CANCELED', 'PENDING'));

CREATE POLICY "direct_bets_update_arbiter" ON direct_bets
  FOR UPDATE
  USING (arbiter_id = auth_user_id() AND status IN ('ACTIVE', 'DISPUTED'))
  WITH CHECK (arbiter_id = auth_user_id());

CREATE POLICY "direct_bets_update_dispute" ON direct_bets
  FOR UPDATE
  USING (
    status = 'ACTIVE' 
    AND (proposer_id = auth_user_id() OR acceptor_id = auth_user_id())
  )
  WITH CHECK (status = 'DISPUTED');

CREATE POLICY "direct_bets_admin_all" ON direct_bets
  FOR ALL
  USING (auth_is_admin())
  WITH CHECK (auth_is_admin());

-- ============================================================================
-- LEDGER TABLES POLICIES (System-managed via triggers)
-- ============================================================================

CREATE POLICY "ledger_postings_select_own" ON ledger_postings
  FOR SELECT
  USING (user_id = auth_user_id());

CREATE POLICY "ledger_postings_system_all" ON ledger_postings
  FOR ALL
  WITH CHECK (true);

CREATE POLICY "ledger_transactions_system_all" ON ledger_transactions
  FOR ALL
  WITH CHECK (true);

CREATE POLICY "bet_ledger_links_system_all" ON bet_ledger_links
  FOR ALL
  WITH CHECK (true);

CREATE POLICY "bet_audit_log_select_participant" ON bet_audit_log
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM direct_bets 
      WHERE direct_bets.bet_id = bet_audit_log.bet_id 
      AND (
        direct_bets.proposer_id = auth_user_id() 
        OR direct_bets.acceptor_id = auth_user_id() 
        OR direct_bets.arbiter_id = auth_user_id()
      )
    )
  );

CREATE POLICY "bet_audit_log_system_insert" ON bet_audit_log
  FOR INSERT
  WITH CHECK (true);

-- ============================================================================
-- APP SETTINGS POLICIES
-- ============================================================================

CREATE POLICY "app_settings_select_public" ON app_settings
  FOR SELECT
  USING (true);

CREATE POLICY "app_settings_admin_all" ON app_settings
  FOR ALL
  USING (auth_is_admin())
  WITH CHECK (auth_is_admin());

-- ============================================================================
-- BET THREADS AND COMMENTS POLICIES
-- ============================================================================

CREATE POLICY "bet_threads_select_participant" ON Bet_Threads
  FOR SELECT
  USING (
    visibility = 'PUBLIC'
    OR EXISTS (
      SELECT 1 FROM direct_bets 
      WHERE direct_bets.bet_id = Bet_Threads.bet_id 
      AND (
        direct_bets.proposer_id = auth_user_id() 
        OR direct_bets.acceptor_id = auth_user_id() 
        OR direct_bets.arbiter_id = auth_user_id()
      )
    )
  );

CREATE POLICY "bet_threads_system_insert" ON Bet_Threads
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY "comments_select_thread_access" ON Comments
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM Bet_Threads bt
      JOIN direct_bets db ON db.bet_id = bt.bet_id
      WHERE bt.thread_id = Comments.thread_id
      AND (
        bt.visibility = 'PUBLIC'
        OR db.proposer_id = auth_user_id()
        OR db.acceptor_id = auth_user_id()
        OR db.arbiter_id = auth_user_id()
      )
    )
  );

CREATE POLICY "comments_insert_thread_access" ON Comments
  FOR INSERT
  WITH CHECK (
    author_id = auth_user_id()
    AND EXISTS (
      SELECT 1 FROM Bet_Threads bt
      JOIN direct_bets db ON db.bet_id = bt.bet_id
      WHERE bt.thread_id = Comments.thread_id
      AND (
        bt.visibility = 'PUBLIC'
        OR db.proposer_id = auth_user_id()
        OR db.acceptor_id = auth_user_id()
        OR db.arbiter_id = auth_user_id()
      )
    )
  );

CREATE POLICY "comments_update_own" ON Comments
  FOR UPDATE
  USING (author_id = auth_user_id())
  WITH CHECK (author_id = auth_user_id());

CREATE POLICY "comments_delete_own" ON Comments
  FOR DELETE
  USING (author_id = auth_user_id());

-- ============================================================================
-- FRIENDS AND FRIEND REQUESTS POLICIES
-- ============================================================================

CREATE POLICY "friend_requests_select_own" ON friend_requests
  FOR SELECT
  USING (sender_id = auth_user_id() OR receiver_id = auth_user_id());

CREATE POLICY "friend_requests_insert_own" ON friend_requests
  FOR INSERT
  WITH CHECK (sender_id = auth_user_id());

CREATE POLICY "friend_requests_update_own" ON friend_requests
  FOR UPDATE
  USING (sender_id = auth_user_id() OR receiver_id = auth_user_id())
  WITH CHECK (sender_id = auth_user_id() OR receiver_id = auth_user_id());

CREATE POLICY "friends_select_own" ON friends
  FOR SELECT
  USING (user_id = auth_user_id() OR friend_id = auth_user_id());

CREATE POLICY "friends_system_all" ON friends
  FOR ALL
  WITH CHECK (true);

-- ============================================================================
-- DONE! RLS is now enabled on all MVP tables
-- ============================================================================
