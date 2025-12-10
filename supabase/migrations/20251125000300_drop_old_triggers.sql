-- Drop triggers that reference deleted tables (User_Statistics, User_Preferences)
-- These were causing INSERT errors on user signup

-- Drop the user creation triggers that try to insert into deleted tables
DROP TRIGGER IF EXISTS trg_create_user_statistics ON users;
DROP TRIGGER IF EXISTS trg_create_user_preferences ON users;

-- Drop the associated functions
DROP FUNCTION IF EXISTS fn_create_user_statistics();
DROP FUNCTION IF EXISTS fn_create_user_preferences();

COMMENT ON TABLE users IS 'Users table - auto-creation triggers for stats/preferences removed after MVP cleanup';

