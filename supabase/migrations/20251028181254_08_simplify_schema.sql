-- Simplified schema for school project demo
-- Remove overcomplicated enterprise features

-- Drop unnecessary tables
DROP TABLE IF EXISTS User_Sessions CASCADE;
DROP TABLE IF EXISTS Password_Reset_Tokens CASCADE;
DROP TABLE IF EXISTS Email_Verification_Tokens CASCADE;

-- Remove 2FA columns from users table
ALTER TABLE users 
  DROP COLUMN IF EXISTS two_factor_enabled,
  DROP COLUMN IF EXISTS two_factor_secret,
  DROP COLUMN IF EXISTS last_login_at;

-- Simplify the users table further for demo purposes
ALTER TABLE users
  DROP COLUMN IF EXISTS is_verified;

-- Also simplify User_Preferences (keep for future but reduce fields)
ALTER TABLE User_Preferences
  DROP COLUMN IF EXISTS email_notifications,
  DROP COLUMN IF EXISTS push_notifications,
  DROP COLUMN IF EXISTS bet_notifications,
  DROP COLUMN IF EXISTS friend_notifications,
  DROP COLUMN IF EXISTS marketing_emails;

-- Drop the views that referenced the dropped columns
DROP VIEW IF EXISTS v_active_sessions CASCADE;

-- Update the public profile view to remove references to dropped columns
DROP VIEW IF EXISTS v_user_public_profile;
CREATE OR REPLACE VIEW v_user_public_profile AS
SELECT 
  u.user_id,
  u.username,
  u.display_name,
  u.profile_picture_url,
  u.bio,
  u.reputation_score,
  u.created_at,
  s.total_bets_won,
  s.total_bets_lost,
  s.total_profit_loss,
  s.current_win_streak,
  s.longest_win_streak,
  s.arbiter_accuracy_rate
FROM users u
LEFT JOIN User_Statistics s ON s.user_id = u.user_id
WHERE u.is_active = TRUE;

