'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'

interface User {
  user_id: number
  username: string
}

export default function CreateBetPage() {
  const [betType, setBetType] = useState<'marketplace' | 'direct'>('marketplace')
  const [description, setDescription] = useState('')
  const [amount, setAmount] = useState('')
  const [searchQuery, setSearchQuery] = useState('')
  const [users, setUsers] = useState<User[]>([])
  const [selectedUser, setSelectedUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const router = useRouter()

  // Search users when query changes (for Direct Bet)
  useEffect(() => {
    if (betType === 'direct' && searchQuery.length > 0) {
      searchUsers()
    } else {
      setUsers([])
    }
  }, [searchQuery, betType])

  const searchUsers = async () => {
    try {
      const currentUser = JSON.parse(localStorage.getItem('user') || '{}')
      
      const { data, error } = await supabase
        .from('users')
        .select('user_id, username')
        .ilike('username', `%${searchQuery}%`)
        .neq('user_id', currentUser.id)
        .limit(5)

      if (error) throw error
      setUsers(data || [])
    } catch (err) {
      console.error('Error searching users:', err)
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      const userData = localStorage.getItem('user')
      if (!userData) {
        router.push('/login')
        return
      }

      // Validate Direct Bet has a selected user
      if (betType === 'direct' && !selectedUser) {
        setError('Please select a user for the direct bet')
        setLoading(false)
        return
      }
      
      const user = JSON.parse(userData)
      const amountCents = Math.round(parseFloat(amount) * 100)
      const amountDollars = amountCents / 100

      // Check if user has enough balance
      if (user.wallet_balance < amountDollars) {
        setError(`Insufficient funds! You need $${amountDollars.toFixed(2)} but only have $${user.wallet_balance.toFixed(2)}`)
        setLoading(false)
        return
      }

      // Call the bet_propose function
      const { data, error: betError } = await supabase.rpc('bet_propose', {
        p_proposer_id: user.id,
        p_event_description: description,
        p_odds_format: 'DECIMAL',
        p_odds_proposer: 2.0,
        p_stake_proposer_cents: amountCents,
        p_currency: 'USD',
        p_arbiter_id: null,
        p_payout_model: 'EVENS',
        p_fee_bps: 0
      })

      if (betError) {
        setError(betError.message)
        setLoading(false)
        return
      }

      // If Direct Bet, update with target_user_id
      if (betType === 'direct' && selectedUser && data) {
        const { error: updateError } = await supabase
          .from('direct_bets')
          .update({ target_user_id: selectedUser.user_id })
          .eq('bet_id', data)

        if (updateError) {
          setError(updateError.message)
          setLoading(false)
          return
        }
      }

      // Deduct money from wallet in database (goes into escrow)
      const { error: updateError } = await supabase
        .from('users')
        .update({ wallet_balance: user.wallet_balance - amountDollars })
        .eq('user_id', user.id)

      if (updateError) {
        setError('Failed to update balance')
        setLoading(false)
        return
      }

      // Update localStorage
      user.wallet_balance -= amountDollars
      localStorage.setItem('user', JSON.stringify(user))

      // Success - redirect to dashboard
      alert('Bet created successfully! Funds moved to escrow.')
      router.push('/dashboard')
      
    } catch (err) {
      setError('Failed to create bet. Please try again.')
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-2xl mx-auto">
        <Button 
          variant="outline" 
          onClick={() => router.push('/dashboard')}
          className="mb-4"
        >
          ← Back to Dashboard
        </Button>

        <Card>
          <CardHeader>
            <CardTitle>Create Bet</CardTitle>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="space-y-6">
              {/* Bet Type Toggle */}
              <div className="space-y-2">
                <Label>Bet Type</Label>
                <div className="flex items-center justify-center gap-4 p-4 bg-gray-100 rounded-lg">
                  <span className={`text-sm font-semibold transition-colors ${betType === 'marketplace' ? 'text-blue-600' : 'text-gray-400'}`}>
                    Marketplace
                  </span>
                  <Switch
                    checked={betType === 'direct'}
                    onCheckedChange={(checked) => {
                      setBetType(checked ? 'direct' : 'marketplace')
                      if (!checked) {
                        setSelectedUser(null)
                        setSearchQuery('')
                      }
                    }}
                  />
                  <span className={`text-sm font-semibold transition-colors ${betType === 'direct' ? 'text-blue-600' : 'text-gray-400'}`}>
                    Direct
                  </span>
                </div>
                <p className="text-sm text-gray-500">
                  {betType === 'marketplace' 
                    ? '🌐 Anyone can accept this bet' 
                    : '👤 Send this bet to a specific user'}
                </p>
              </div>

              {/* Direct Bet User Selection */}
              {betType === 'direct' && (
                <div className="space-y-2">
                  <Label htmlFor="userSearch">Send to User</Label>
                  <Input
                    id="userSearch"
                    type="text"
                    placeholder="Search username..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                  />
                  
                  {/* User Results */}
                  {users.length > 0 && (
                    <div className="border rounded-md max-h-40 overflow-y-auto">
                      {users.map((user) => (
                        <button
                          key={user.user_id}
                          type="button"
                          onClick={() => {
                            setSelectedUser(user)
                            setSearchQuery(user.username)
                            setUsers([])
                          }}
                          className="w-full text-left px-3 py-2 hover:bg-gray-100"
                        >
                          {user.username}
                        </button>
                      ))}
                    </div>
                  )}

                  {/* Selected User */}
                  {selectedUser && (
                    <div className="bg-blue-50 p-2 rounded text-sm">
                      Sending to: <strong>{selectedUser.username}</strong>
                    </div>
                  )}
                </div>
              )}

              {/* Bet Description */}
              <div className="space-y-2">
                <Label htmlFor="description">What's the bet?</Label>
                <Input
                  id="description"
                  type="text"
                  placeholder="e.g., Duke will beat UNC in basketball"
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  required
                />
              </div>

              {/* Stake Amount */}
              <div className="space-y-2">
                <Label htmlFor="amount">Stake Amount ($)</Label>
                <Input
                  id="amount"
                  type="number"
                  step="0.01"
                  min="0.01"
                  placeholder="10.00"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  required
                />
              </div>

              {/* Bet Summary */}
              <div className="bg-gray-50 p-3 rounded text-sm space-y-1">
                <p><strong>Bet Type:</strong> {betType === 'marketplace' ? 'Marketplace (Public)' : 'Direct (Private)'}</p>
                <p><strong>You stake:</strong> ${amount || '0.00'}</p>
                <p><strong>Opponent stakes:</strong> ${amount || '0.00'}</p>
                <p><strong>Winner gets:</strong> ${amount ? (parseFloat(amount) * 2).toFixed(2) : '0.00'}</p>
              </div>

              {/* Error Message */}
              {error && (
                <div className="text-sm text-red-600 bg-red-50 p-3 rounded">
                  {error}
                </div>
              )}

              {/* Submit Button */}
              <Button 
                type="submit" 
                className="w-full bg-green-600 hover:bg-green-700" 
                disabled={loading}
              >
                {loading ? 'Creating...' : 'Create Bet'}
              </Button>
            </form>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

