import { supabase } from './supabase'

/**
 * Set the authenticated user context for RLS policies
 * This sets session variables that the database RLS policies use to determine access
 */
export async function setAuthContext(userId: number, isAdmin: boolean = false) {
  // Set the current user ID for RLS policies
  await supabase.rpc('set_auth_context', {
    p_user_id: userId,
    p_is_admin: isAdmin
  })
}

/**
 * Clear the auth context (on logout)
 */
export async function clearAuthContext() {
  await supabase.rpc('set_auth_context', {
    p_user_id: null,
    p_is_admin: false
  })
}

/**
 * Helper to get current user from localStorage
 */
export function getCurrentUser(): { id: number; username: string; balance: number; is_admin?: boolean } | null {
  const userData = localStorage.getItem('user')
  if (!userData) return null
  return JSON.parse(userData)
}

/**
 * Helper to check if current user is admin
 */
export function isCurrentUserAdmin(): boolean {
  const user = getCurrentUser()
  return user?.is_admin === true
}

