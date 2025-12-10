'use client'

import { useState } from 'react'
import { supabase } from '@/lib/supabase'
import { setAuthContext } from '@/lib/auth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { useRouter } from 'next/navigation'

export default function LoginPage() {
  const [isSignUp, setIsSignUp] = useState(false)
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [loading, setLoading] = useState(false)
  const router = useRouter()

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setSuccess('')
    setLoading(true)

    try {
      // Check if username already exists
      const { data: existingUser } = await supabase
        .from('users')
        .select('user_id')
        .eq('username', username)
        .single()

      if (existingUser) {
        setError('Username already taken')
        setLoading(false)
        return
      }

      // Create new user with $1000 starting balance
      const { error: insertError } = await supabase
        .from('users')
        .insert({
          username: username,
          email: `${username}@demo.com`, // Demo email
          password_hash: password, // MVP: storing plain text (NOT for production!)
          wallet_balance: 1000.00,
          is_active: true,
          is_admin: false
        })

      if (insertError) {
        console.error('Insert error:', insertError)
        setError('Failed to create account. Please try again.')
        setLoading(false)
        return
      }

      setSuccess('Account created successfully! Logging you in...')
      
      // Auto-login after 1 second - query the user to get their ID
      setTimeout(async () => {
        // Now fetch the user we just created
        const { data: createdUser } = await supabase
          .from('users')
          .select('user_id, username, wallet_balance, is_admin')
          .eq('username', username)
          .single()

        if (createdUser) {
          await setAuthContext(createdUser.user_id, false)
          localStorage.setItem('user', JSON.stringify({
            id: createdUser.user_id,
            username: createdUser.username,
            wallet_balance: createdUser.wallet_balance,
            balance: createdUser.wallet_balance,
            is_admin: false
          }))
          router.push('/dashboard')
        }
      }, 1000)
      
    } catch (err) {
      console.error('Sign up error:', err)
      setError('Sign up failed. Please try again.')
      setLoading(false)
    }
  }

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setSuccess('')
    setLoading(true)

    try {
      // Query user by username
      const { data: user, error: userError } = await supabase
        .from('users')
        .select('user_id, username, password_hash, wallet_balance, is_admin, is_active')
        .eq('username', username)
        .single()

      if (userError || !user) {
        setError('Invalid username or password')
        setLoading(false)
        return
      }

      if (!user.is_active) {
        setError('Account is inactive')
        setLoading(false)
        return
      }

      // Set auth context for RLS policies
      await setAuthContext(user.user_id, user.is_admin)

      // For MVP demo: Store in localStorage (NOT secure for production!)
      localStorage.setItem('user', JSON.stringify({
        id: user.user_id,
        username: user.username,
        wallet_balance: user.wallet_balance,
        balance: user.wallet_balance,
        is_admin: user.is_admin
      }))

      // Redirect to dashboard
      router.push('/dashboard')
      
    } catch (err) {
      console.error('Login error:', err)
      setError('Login failed. Please try again.')
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center" style={{backgroundColor: 'transparent'}}>
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle className="text-2xl">8Ball Markets</CardTitle>
          <CardDescription>
            {isSignUp ? 'Create a new account' : 'Login to your account'}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={isSignUp ? handleSignUp : handleLogin} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="username">Username</Label>
              <Input
                id="username"
                type="text"
                placeholder="Username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                required
                minLength={3}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                placeholder="Password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={3}
              />
            </div>
            {error && (
              <div className="text-sm text-red-600 bg-red-50 p-3 rounded">
                {error}
              </div>
            )}
            {success && (
              <div className="text-sm text-green-600 bg-green-50 p-3 rounded">
                {success}
              </div>
            )}
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? (isSignUp ? 'Creating account...' : 'Logging in...') : (isSignUp ? 'Sign Up' : 'Login')}
            </Button>
          </form>
          
          <div className="mt-4 text-center">
            <button
              onClick={() => {
                setIsSignUp(!isSignUp)
                setError('')
                setSuccess('')
              }}
              className="text-sm text-blue-600 hover:underline"
            >
              {isSignUp ? 'Already have an account? Login' : "Don't have an account? Sign Up"}
            </button>
          </div>

          {isSignUp && (
            <p className="mt-4 text-sm text-gray-500 text-center">
              New accounts start with $1000
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

