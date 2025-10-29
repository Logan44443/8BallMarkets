-- MVP Cleanup: Remove non-essential features

-- Drop Achievements table (not MVP)
DROP TABLE IF EXISTS Achievements CASCADE;

-- Drop head_to_head_stats view (not MVP)
DROP VIEW IF EXISTS head_to_head_stats CASCADE;

-- Drop User_Statistics table (not MVP - can calculate on the fly if needed)
DROP TABLE IF EXISTS User_Statistics CASCADE;

-- Drop Reputation_Logs table (not MVP - keep the score itself)
DROP TABLE IF EXISTS Reputation_Logs CASCADE;

-- Remove reputation_score column from users views if it exists
-- (actually, let's keep it on the table, just don't track changes)

-- Update the public profile view to remove stats references
DROP VIEW IF EXISTS v_user_public_profile;
CREATE OR REPLACE VIEW v_user_public_profile AS
SELECT 
  u.user_id,
  u.username,
  u.display_name,
  u.profile_picture_url,
  u.bio,
  u.reputation_score,
  u.created_at
FROM users u
WHERE u.is_active = TRUE;

-- Drop the leaderboard view since we removed stats
DROP VIEW IF EXISTS v_leaderboard CASCADE;

