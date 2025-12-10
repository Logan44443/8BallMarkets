-- Fix RLS policies to allow authentication (login/signup)
-- The issue: users can't SELECT their own data during login/signup because they're not authenticated yet

-- Drop the restrictive public select policy and replace with a more permissive one
DROP POLICY IF EXISTS "users_select_public" ON users;

-- Allow anyone to select active users (needed for login and public profiles)
CREATE POLICY "users_select_active" ON users
  FOR SELECT
  USING (is_active = TRUE);

-- This allows:
-- 1. Login flow: query user by username before auth
-- 2. Signup flow: query user after insert to get user_id
-- 3. Public profiles: view any active user

COMMENT ON POLICY "users_select_active" ON users IS 'Allow selecting active users for authentication and public profiles';

