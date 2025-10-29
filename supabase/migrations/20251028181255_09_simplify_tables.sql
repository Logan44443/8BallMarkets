-- Further simplify tables for school project demo

-- Simplify Comments: drop reactions, mentions, reports
DROP TABLE IF EXISTS Comment_Reactions CASCADE;
DROP TABLE IF EXISTS Comment_Mentions CASCADE;
DROP TABLE IF EXISTS Comment_Reports CASCADE;

-- Drop the trigger that enforces private post rules (simplify for demo)
DROP TRIGGER IF EXISTS trg_private_post ON Comments;
DROP FUNCTION IF EXISTS fn_enforce_private_post;

-- Simplify Support: drop tags system
DROP TABLE IF EXISTS Ticket_Tag_Map CASCADE;
DROP TABLE IF EXISTS Ticket_Tags CASCADE;

-- Remove internal notes field (simplify)
ALTER TABLE Ticket_Messages 
  DROP COLUMN IF EXISTS is_internal_note;

-- Simplify Social: drop circles and daily leaderboard snapshots
DROP TABLE IF EXISTS circle_members CASCADE;
DROP TABLE IF EXISTS circles CASCADE;
DROP TABLE IF EXISTS leaderboards_user_daily CASCADE;

-- Remove is_blocked from friends (keep it simple)
ALTER TABLE friends 
  DROP COLUMN IF EXISTS is_blocked;

-- Keep: friend_requests, friends, head_to_head_stats view

