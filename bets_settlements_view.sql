-- View: bets_settlements
-- Purpose: Aggregate resolved bets for social stats and leaderboards
-- Used by: social.sql head_to_head_stats view

CREATE OR REPLACE VIEW bets_settlements AS
SELECT 
  bet_id,
  proposer_id,
  acceptor_id,
  CASE 
    WHEN outcome = 'PROPOSER_WIN' THEN proposer_id
    WHEN outcome = 'ACCEPTOR_WIN' THEN acceptor_id
    ELSE NULL
  END AS winner_id,
  stake_proposer_cents + COALESCE(stake_acceptor_cents, 0) AS amount_cents,
  status,
  resolved_at
FROM direct_bets
WHERE status = 'RESOLVED' 
  AND outcome IN ('PROPOSER_WIN', 'ACCEPTOR_WIN');

