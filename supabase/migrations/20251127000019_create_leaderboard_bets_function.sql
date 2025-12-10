-- Create a function to fetch all resolved bets for leaderboard
-- This bypasses RLS to ensure consistent results
CREATE OR REPLACE FUNCTION get_all_resolved_bets_for_leaderboard()
RETURNS TABLE (
  bet_id BIGINT,
  status TEXT,
  outcome TEXT,
  proposer_id BIGINT,
  acceptor_id BIGINT,
  stake_proposer_cents BIGINT,
  stake_acceptor_cents BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    db.bet_id,
    db.status,
    db.outcome,
    db.proposer_id,
    db.acceptor_id,
    db.stake_proposer_cents,
    db.stake_acceptor_cents
  FROM direct_bets db
  WHERE db.status = 'RESOLVED'
  ORDER BY db.bet_id ASC;
END;
$$;

COMMENT ON FUNCTION get_all_resolved_bets_for_leaderboard() IS 'Returns all resolved bets for leaderboard calculation. Bypasses RLS for consistent results.';

