'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase'
import { setAuthContext } from '@/lib/auth'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface Bet {
  bet_id: number
  event_description: string
  stake_proposer_cents: number
  created_at: string
  proposer_id: number
  users: {
    username: string
  }
}

export default function MarketplacePage() {
  const [bets, setBets] = useState<Bet[]>([])
  const [loading, setLoading] = useState(true)
  const [accepting, setAccepting] = useState<number | null>(null)
  const router = useRouter()

  useEffect(() => {
    loadBets()
  }, [])

  const loadBets = async () => {
    try {
      const userData = localStorage.getItem('user')
      if (!userData) {
        router.push('/login')
        return
      }
      const user = JSON.parse(userData)

      // Get all PENDING bets where target_user_id IS NULL (public marketplace bets)
      // AND proposer is NOT the current user
      const { data, error } = await supabase
        .from('direct_bets')
        .select(`
          bet_id,
          event_description,
          stake_proposer_cents,
          created_at,
          proposer_id,
          users!direct_bets_proposer_id_fkey(username)
        `)
        .eq('status', 'PENDING')
        .is('target_user_id', null)
        .neq('proposer_id', user.id)
        .order('created_at', { ascending: false })

      if (error) throw error
      setBets(data || [])
    } catch (err) {
      console.error('Error loading bets:', err)
    } finally {
      setLoading(false)
    }
  }

  const handleAccept = async (betId: number, stakeAmount: number) => {
    setAccepting(betId)
    
    try {
      const userData = localStorage.getItem('user')
      if (!userData) {
        router.push('/login')
        return
      }
      
      const user = JSON.parse(userData)

      // Check if user has enough balance
      const stakeInDollars = stakeAmount / 100
      if (user.wallet_balance < stakeInDollars) {
        alert(`Insufficient funds! You need $${stakeInDollars.toFixed(2)} but only have $${user.wallet_balance.toFixed(2)}`)
        setAccepting(null)
        return
      }

      // Re-establish auth context before RPC call
      await setAuthContext(user.id, user.is_admin || false)

      // Call bet_accept function (this will move funds to HELD via the trigger)
      const { error } = await supabase.rpc('bet_accept', {
        p_bet_id: betId,
        p_acceptor_id: user.id,
        p_stake_acceptor_cents: stakeAmount,
        p_odds_acceptor: null
      })

      if (error) {
        alert(`Error: ${error.message}`)
        setAccepting(null)
        return
      }

      // Wait a moment for sync trigger to update balance
      await new Promise(resolve => setTimeout(resolve, 300))

      // Refresh balance from database (sync trigger should have updated it)
      const { data: updatedBalance, error: balanceError } = await supabase
        .from('users')
        .select('wallet_balance')
        .eq('user_id', user.id)
        .single()

      if (balanceError) {
        console.error('Error fetching updated balance:', balanceError)
      }

      // Update user's balance in localStorage with fresh value
      if (updatedBalance) {
        user.wallet_balance = updatedBalance.wallet_balance
        user.balance = updatedBalance.wallet_balance
        localStorage.setItem('user', JSON.stringify(user))
      }

      alert('Bet accepted successfully! Funds moved to escrow.')
      
      // Reload bets to remove the accepted one
      loadBets()
      
    } catch (err) {
      alert('Failed to accept bet')
      console.error(err)
    } finally {
      setAccepting(null)
    }
  }

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center">Loading...</div>
  }

  return (
    <div className="min-h-screen p-8" style={{backgroundColor: 'transparent'}}>
      <div className="max-w-6xl mx-auto">
        <div className="mb-6 flex justify-between items-center">
          <h1 className="text-3xl font-bold text-white">Bet Marketplace</h1>
          <Button variant="outline" onClick={() => router.push('/dashboard')}>
            ← Dashboard
          </Button>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Available Bets</CardTitle>
          </CardHeader>
          <CardContent>
            {bets.length === 0 ? (
              <p className="text-center text-gray-500 py-8">
                No open bets available. Create one to get started!
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b">
                      <th className="text-left p-3 font-semibold">Creator</th>
                      <th className="text-left p-3 font-semibold">Bet Description</th>
                      <th className="text-right p-3 font-semibold">Stake</th>
                      <th className="text-center p-3 font-semibold">Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {bets.map((bet) => (
                      <tr key={bet.bet_id} className="border-b hover:bg-gray-50">
                        <td className="p-3">
                          <span className="font-medium">{bet.users?.username || 'Unknown'}</span>
                        </td>
                        <td className="p-3">
                          <span>{bet.event_description}</span>
                          <br />
                          <span className="text-xs text-gray-500">
                            {new Date(bet.created_at).toLocaleDateString()}
                          </span>
                        </td>
                        <td className="p-3 text-right">
                          <span className="font-bold text-lg">
                            ${(bet.stake_proposer_cents / 100).toFixed(2)}
                          </span>
                          <br />
                          <span className="text-xs text-gray-500">
                            Winner: ${(bet.stake_proposer_cents / 50).toFixed(2)}
                          </span>
                        </td>
                        <td className="p-3 text-center">
                          <Button
                            onClick={() => handleAccept(bet.bet_id, bet.stake_proposer_cents)}
                            disabled={accepting === bet.bet_id}
                            className="bg-green-600 hover:bg-green-700"
                          >
                            {accepting === bet.bet_id ? 'Accepting...' : 'Accept'}
                          </Button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

