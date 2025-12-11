-- ============================================================================
-- Create function to get all bets for a specific user (for profile viewing)
-- This bypasses RLS so users can view other users' profiles and see their bets
-- ============================================================================

CREATE OR REPLACE FUNCTION get_user_bets_for_profile(p_user_id BIGINT)
RETURNS TABLE (
  bet_id BIGINT,
  event_description TEXT,
  status TEXT,
  stake_proposer_cents BIGINT,
  stake_acceptor_cents BIGINT,
  proposer_id BIGINT,
  acceptor_id BIGINT,
  arbiter_id BIGINT,
  outcome TEXT,
  created_at TIMESTAMPTZ,
  proposer_username TEXT,
  acceptor_username TEXT,
  arbiter_username TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    db.bet_id,
    db.event_description,
    db.status,
    db.stake_proposer_cents,
    db.stake_acceptor_cents,
    db.proposer_id,
    db.acceptor_id,
    db.arbiter_id,
    db.outcome,
    db.created_at,
    proposer.username::TEXT AS proposer_username,
    acceptor.username::TEXT AS acceptor_username,
    arbiter.username::TEXT AS arbiter_username
  FROM direct_bets db
  LEFT JOIN users proposer ON db.proposer_id = proposer.user_id
  LEFT JOIN users acceptor ON db.acceptor_id = acceptor.user_id
  LEFT JOIN users arbiter ON db.arbiter_id = arbiter.user_id
  WHERE db.proposer_id = p_user_id 
     OR db.acceptor_id = p_user_id 
     OR db.arbiter_id = p_user_id
  ORDER BY db.created_at DESC;
END;
$$;

COMMENT ON FUNCTION get_user_bets_for_profile(BIGINT) IS 'Returns all bets for a specific user (proposer, acceptor, or arbiter). Bypasses RLS for profile viewing.';

