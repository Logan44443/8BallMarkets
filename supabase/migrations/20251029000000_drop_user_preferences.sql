-- Drop User_Preferences table and related triggers
-- Not needed for MVP demo

-- Drop the trigger that creates preferences
DROP TRIGGER IF EXISTS trg_create_user_preferences ON users;
DROP FUNCTION IF EXISTS fn_create_user_preferences;

-- Drop the trigger that updates timestamp
DROP TRIGGER IF EXISTS trg_preferences_update_timestamp ON User_Preferences;

-- Drop the table
DROP TABLE IF EXISTS User_Preferences CASCADE;

