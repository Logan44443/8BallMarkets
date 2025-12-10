-- ============================================================================
-- Auth Context Management Function
-- ============================================================================
-- This function is called from the frontend to set the current user context
-- for RLS policies to use

CREATE OR REPLACE FUNCTION set_auth_context(
  p_user_id BIGINT,
  p_is_admin BOOLEAN DEFAULT FALSE
)
RETURNS void AS $$
BEGIN
  -- Set the user ID (or clear it if NULL)
  IF p_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', p_user_id::TEXT, false);
  ELSE
    PERFORM set_config('app.current_user_id', '', false);
  END IF;
  
  -- Set admin flag
  IF p_is_admin THEN
    PERFORM set_config('app.current_is_admin', 'on', false);
  ELSE
    PERFORM set_config('app.current_is_admin', 'off', false);
  END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION set_auth_context IS 'Sets session variables for RLS policies to identify the authenticated user';

