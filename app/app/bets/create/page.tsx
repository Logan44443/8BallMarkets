'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase'
import { setAuthContext } from '@/lib/auth'
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
  const [arbiterSearchQuery, setArbiterSearchQuery] = useState('')
  const [arbiterUsers, setArbiterUsers] = useState<User[]>([])
  const [selectedArbiter, setSelectedArbiter] = useState<User | null>(null)
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

  // Search for arbiter when query changes
  useEffect(() => {
    if (arbiterSearchQuery.length > 0) {
      searchArbiters()
    } else {
      setArbiterUsers([])
    }
  }, [arbiterSearchQuery])

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

  const searchArbiters = async () => {
    try {
      const currentUser = JSON.parse(localStorage.getItem('user') || '{}')
      
      // Exclude self and opponent
      const excludeIds = [currentUser.id]
      if (selectedUser) excludeIds.push(selectedUser.user_id)

      const { data, error } = await supabase
        .from('users')
        .select('user_id, username')
        .ilike('username', `%${arbiterSearchQuery}%`)
        .not('user_id', 'in', `(${excludeIds.join(',')})`)
        .limit(5)

      if (error) throw error
      setArbiterUsers(data || [])
    } catch (err) {
      console.error('Error searching arbiters:', err)
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

      await setAuthContext(user.id, user.is_admin || false)

      const { data: userBalance, error: balanceError } = await supabase
        .from('users')
        .select('wallet_balance')
        .eq('user_id', user.id)
        .single()

      if (balanceError || !userBalance) {
        setError('Failed to check balance. Please try again.')
        setLoading(false)
        return
      }

      if (userBalance.wallet_balance < amountDollars) {
        setError(`Insufficient funds! You need $${amountDollars.toFixed(2)} but only have $${userBalance.wallet_balance.toFixed(2)}`)
        setLoading(false)
        return
      }

      // Call the bet_propose function
      console.log('Creating bet with:', {
        proposer_id: user.id,
        stake_cents: amountCents,
        current_balance: userBalance.wallet_balance
      })
      
      const { data, error: betError } = await supabase.rpc('bet_propose', {
        p_proposer_id: user.id,
        p_event_description: description,
        p_odds_format: 'DECIMAL',
        p_odds_proposer: 2.0,
        p_stake_proposer_cents: amountCents,
        p_currency: 'USD',
        p_arbiter_id: selectedArbiter ? selectedArbiter.user_id : null,
        p_payout_model: 'EVENS',
        p_fee_bps: 0
      })

      if (betError) {
        console.error('Bet creation error:', betError)
        console.error('Full error details:', JSON.stringify(betError, null, 2))
        setError(betError.message || 'Failed to create bet. Check console for details.')
        setLoading(false)
        return
      }
      
      console.log('Bet created successfully, bet_id:', data)
      
      if (!data) {
        console.error('bet_propose returned null/undefined bet_id!')
        setError('Bet creation returned no bet ID')
        setLoading(false)
        return
      }
      
      // Check if ledger entries were created (debug)
      // Re-establish auth context before querying ledger
      await setAuthContext(user.id, user.is_admin || false)
      
      if (data) {
        const { data: ledgerData, error: ledgerError } = await supabase
          .from('bet_ledger_links')
          .select('tx_id')
          .eq('bet_id', data)
        
        console.log('Ledger links for this bet:', ledgerData, 'Error:', ledgerError)
        
        if (ledgerData && ledgerData.length > 0) {
          const { data: postingsData, error: postingsError } = await supabase
            .from('ledger_postings')
            .select('*')
            .in('tx_id', ledgerData.map(l => l.tx_id))
          
          console.log('Ledger postings created:', postingsData, 'Error:', postingsError)
        } else {
          console.warn('No ledger links found - this means the function may have failed to create ledger entries')
        }
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

      // Manually trigger balance sync by calling the calculate function
      // This ensures balance is updated even if trigger hasn't fired yet
      const { data: syncResult, error: syncError } = await supabase.rpc('calculate_user_balance', {
        p_user_id: user.id
      })
      
      if (!syncError && syncResult !== null) {
        // Update wallet_balance directly using the calculated value
        const { error: updateError } = await supabase
          .from('users')
          .update({ wallet_balance: syncResult })
          .eq('user_id', user.id)
        
        if (updateError) {
          console.error('Error updating balance:', updateError)
        }
      }
      
      // Refresh balance from database (funds are now HELD via trigger)
      // Wait a moment for trigger to complete
      await new Promise(resolve => setTimeout(resolve, 300))
      
      const { data: updatedBalance, error: balanceCheckError } = await supabase
        .from('users')
        .select('wallet_balance')
        .eq('user_id', user.id)
        .single()

      console.log('Balance after bet creation:', {
        old_balance: userBalance.wallet_balance,
        calculated_balance: syncResult,
        new_balance: updatedBalance?.wallet_balance,
        expected_decrease: amountDollars,
        balance_error: balanceCheckError,
        sync_error: syncError
      })

      if (updatedBalance) {
        // Update localStorage with fresh balance (funds are now held in escrow)
        user.wallet_balance = updatedBalance.wallet_balance
        localStorage.setItem('user', JSON.stringify(user))
        console.log('Updated localStorage balance to:', updatedBalance.wallet_balance)
      }

      // Success - redirect to dashboard
      // Funds are now held in escrow until bet is accepted and resolved
      alert('Bet created successfully! Funds are now held in escrow.')
      router.push('/dashboard')
      
    } catch (err) {
      setError('Failed to create bet. Please try again.')
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen p-8" style={{backgroundColor: 'transparent'}}>
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
                <Label className="text-base font-semibold">Bet Type</Label>
                <div className="flex items-center justify-center gap-6 p-5 bg-white border-2 border-gray-300 rounded-lg shadow-sm">
                  <span className={`text-base font-bold transition-all ${betType === 'marketplace' ? 'text-blue-600 scale-110' : 'text-gray-400'}`}>
                    🌐 Marketplace
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
                    className="data-[state=checked]:bg-blue-200 data-[state=unchecked]:bg-gray-300 border border-gray-400 [&>span]:bg-white [&>span]:border-2 [&>span]:border-gray-800"
                  />
                  <span className={`text-base font-bold transition-all ${betType === 'direct' ? 'text-blue-600 scale-110' : 'text-gray-400'}`}>
                    👤 Direct
                  </span>
                </div>
                <p className="text-sm text-gray-600 font-medium text-center">
                  {betType === 'marketplace' 
                    ? 'Anyone can accept this bet' 
                    : 'Send this bet to a specific user'}
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
                <Label htmlFor="description">What&apos;s the bet?</Label>
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

              {/* Arbiter Selection (Optional) */}
              <div className="space-y-2">
                <Label htmlFor="arbiterSearch">Third-Party Arbiter (Optional)</Label>
                <p className="text-xs text-gray-500 mb-2">
                  Select someone to verify fairness and resolve the outcome
                </p>
                <Input
                  id="arbiterSearch"
                  type="text"
                  placeholder="Search username..."
                  value={arbiterSearchQuery}
                  onChange={(e) => setArbiterSearchQuery(e.target.value)}
                />
                
                {/* Arbiter Results */}
                {arbiterUsers.length > 0 && (
                  <div className="border rounded-md max-h-40 overflow-y-auto">
                    {arbiterUsers.map((user) => (
                      <button
                        key={user.user_id}
                        type="button"
                        onClick={() => {
                          setSelectedArbiter(user)
                          setArbiterSearchQuery(user.username)
                          setArbiterUsers([])
                        }}
                        className="w-full text-left px-3 py-2 hover:bg-gray-100"
                      >
                        {user.username}
                      </button>
                    ))}
                  </div>
                )}

                {/* Selected Arbiter */}
                {selectedArbiter && (
                  <div className="bg-purple-50 p-2 rounded text-sm flex justify-between items-center">
                    <span>Arbiter: <strong>{selectedArbiter.username}</strong></span>
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedArbiter(null)
                        setArbiterSearchQuery('')
                      }}
                      className="text-red-600 hover:underline text-xs"
                    >
                      Remove
                    </button>
                  </div>
                )}
              </div>

              {/* Bet Summary */}
              <div className="bg-gray-50 p-3 rounded text-sm space-y-1">
                <p><strong>Bet Type:</strong> {betType === 'marketplace' ? 'Marketplace (Public)' : 'Direct (Private)'}</p>
                <p><strong>You stake:</strong> ${amount || '0.00'}</p>
                <p><strong>Opponent stakes:</strong> ${amount || '0.00'}</p>
                <p><strong>Winner gets:</strong> ${amount ? (parseFloat(amount) * 2).toFixed(2) : '0.00'}</p>
                {selectedArbiter && (
                  <p className="text-purple-700"><strong>⚖️ Arbiter:</strong> {selectedArbiter.username}</p>
                )}
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

