-- Add target_user_id for private/direct bets
-- NULL = marketplace bet (anyone can accept)
-- NOT NULL = direct bet (only that specific user can accept)

ALTER TABLE direct_bets 
  ADD COLUMN target_user_id BIGINT REFERENCES users(user_id) ON DELETE SET NULL;

-- Add index for querying bets targeted at a specific user
CREATE INDEX idx_direct_bets_target_user ON direct_bets(target_user_id) 
  WHERE target_user_id IS NOT NULL AND status = 'PENDING';

-- Add check constraint: if there's a target user, they can't be the proposer
ALTER TABLE direct_bets
  ADD CONSTRAINT chk_target_not_proposer CHECK (
    target_user_id IS NULL OR target_user_id != proposer_id
  );

