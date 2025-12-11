'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { supabase } from '@/lib/supabase'
import { setAuthContext } from '@/lib/auth'

interface Bet {
  bet_id: number
  event_description: string
  status: string
  stake_proposer_cents: number
  stake_acceptor_cents: number
  proposer_id: number
  acceptor_id: number
  created_at: string
  accepted_at: string | null
  dispute_notes: string | null
  outcome_notes: string | null
  proposer: { username: string }
  acceptor: { username: string } | null
}

export default function ArbiterDashboardPage() {
  const [bets, setBets] = useState<Bet[]>([])
  const [selectedBet, setSelectedBet] = useState<Bet | null>(null)
  const [resolveDialogOpen, setResolveDialogOpen] = useState(false)
  const [outcome, setOutcome] = useState<'PROPOSER_WIN' | 'ACCEPTOR_WIN' | 'VOID'>('PROPOSER_WIN')
  const [notes, setNotes] = useState('')
  const [loading, setLoading] = useState(false)
  const [loadingBets, setLoadingBets] = useState(false)
  const router = useRouter()

  useEffect(() => {
    loadArbiterBets()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const loadArbiterBets = async () => {
    setLoadingBets(true)
    try {
      const userData = localStorage.getItem('user')
      if (!userData) {
        router.push('/login')
        return
      }

      const user = JSON.parse(userData)
      await setAuthContext(user.id, user.is_admin || false)
      // Wait for auth context to be set
      await new Promise(resolve => setTimeout(resolve, 200))

      // Load bets where current user is the arbiter
      const { data: betsData, error } = await supabase
        .from('direct_bets')
        .select(`
          bet_id,
          event_description,
          status,
          stake_proposer_cents,
          stake_acceptor_cents,
          proposer_id,
          acceptor_id,
          created_at,
          accepted_at,
          dispute_notes,
          outcome_notes,
          proposer:users!direct_bets_proposer_id_fkey(username),
          acceptor:users!direct_bets_acceptor_id_fkey(username)
        `)
        .eq('arbiter_id', user.id)
        .in('status', ['ACTIVE', 'DISPUTED', 'RESOLVED'])
        .order('created_at', { ascending: false })

      if (error) {
        console.error('Error loading arbiter bets:', error)
        return
      }

      if (betsData) {
        // Transform the data to match our Bet type
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const transformedBets = betsData.map((bet: any) => ({
          ...bet,
          proposer: Array.isArray(bet.proposer) ? bet.proposer[0] : bet.proposer,
          acceptor: Array.isArray(bet.acceptor) ? bet.acceptor[0] : bet.acceptor
        }))
        setBets(transformedBets as Bet[])
      }
    } catch (err) {
      console.error('Error in loadArbiterBets:', err)
    } finally {
      setLoadingBets(false)
    }
  }

  const handleResolve = async () => {
    if (!selectedBet) return

    setLoading(true)
    try {
      // Re-establish auth context before RPC call
      const userData = localStorage.getItem('user')
      if (!userData) {
        alert('User session not found')
        setLoading(false)
        return
      }

      const user = JSON.parse(userData)
      await setAuthContext(user.id, user.is_admin || false)
      // Small delay to ensure auth context is set
      await new Promise(resolve => setTimeout(resolve, 200))

      const { error } = await supabase.rpc('bet_resolve', {
        p_bet_id: selectedBet.bet_id,
        p_outcome: outcome,
        p_notes: notes || null
      })

      if (error) {
        alert('Failed to resolve bet: ' + error.message)
        setLoading(false)
        return
      }

      // Wait for sync trigger to update balances
      await new Promise(resolve => setTimeout(resolve, 500))

      // If current user is proposer or acceptor, refresh their balance
      if (selectedBet && (selectedBet.proposer_id === user.id || selectedBet.acceptor_id === user.id)) {
        const { data: updatedBalance } = await supabase
          .from('users')
          .select('wallet_balance')
          .eq('user_id', user.id)
          .single()
        
        if (updatedBalance) {
          user.wallet_balance = updatedBalance.wallet_balance
          user.balance = updatedBalance.wallet_balance
          localStorage.setItem('user', JSON.stringify(user))
        }
      }

      alert('Bet resolved successfully! Balances have been updated.')
      setResolveDialogOpen(false)
      setSelectedBet(null)
      setNotes('')
      loadArbiterBets()
    } catch (err) {
      console.error('Error resolving bet:', err)
      alert('Failed to resolve bet')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen p-8" style={{backgroundColor: 'transparent'}}>
      <div className="max-w-6xl mx-auto">
        {/* Header */}
        <div className="mb-6 flex justify-between items-center">
          <div>
            <h1 className="text-3xl font-bold text-white">⚖️ Arbiter Dashboard</h1>
            <p className="text-white mt-1">Resolve bets you&apos;re assigned to arbitrate</p>
          </div>
          <Button variant="outline" onClick={() => router.push('/dashboard')}>
            Back to Dashboard
          </Button>
        </div>

        {/* Bets Awaiting Resolution */}
        <Card>
          <CardHeader>
            <CardTitle>Bets Awaiting Your Decision ({bets.length})</CardTitle>
          </CardHeader>
          <CardContent>
            {loadingBets ? (
              <p className="text-gray-500 text-center py-8">Loading bets...</p>
            ) : bets.length === 0 ? (
              <p className="text-gray-500 text-center py-8">No bets to resolve at the moment</p>
            ) : (
              <div className="space-y-4">
                {bets.map(bet => (
                  <div key={bet.bet_id} className="border rounded-lg p-4 hover:bg-gray-50">
                    <div className="flex justify-between items-start">
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-2">
                          <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                            bet.status === 'DISPUTED' ? 'bg-red-100 text-red-800' : 'bg-green-100 text-green-800'
                          }`}>
                            {bet.status}
                          </span>
                          {bet.status === 'DISPUTED' && (
                            <span className="text-xs text-red-600">⚠️ Disputed</span>
                          )}
                        </div>
                        <p className="font-semibold text-lg mb-2">{bet.event_description}</p>
                        <div className="grid grid-cols-2 gap-4 text-sm text-gray-600">
                          <div>
                            <p className="font-medium text-gray-900">Proposer:</p>
                            <p>{bet.proposer.username}</p>
                            <p className="text-green-600 font-medium">
                              ${(bet.stake_proposer_cents / 100).toFixed(2)} staked
                            </p>
                          </div>
                          <div>
                    <p className="font-medium text-gray-900">Acceptor:</p>
                    <p>{bet.acceptor?.username || 'N/A'}</p>
                            {bet.stake_acceptor_cents && (
                              <p className="text-green-600 font-medium">
                                ${(bet.stake_acceptor_cents / 100).toFixed(2)} staked
                              </p>
                            )}
                          </div>
                        </div>
                        {bet.status === 'DISPUTED' && bet.dispute_notes && (
                          <div className="mt-3 p-2 bg-red-50 border border-red-200 rounded text-sm">
                            <p className="font-medium text-red-800">⚠️ Dispute Notes:</p>
                            <p className="text-gray-700">{bet.dispute_notes}</p>
                          </div>
                        )}
                        {bet.status === 'RESOLVED' && bet.outcome_notes && (
                          <div className="mt-3 p-2 bg-blue-50 border border-blue-200 rounded text-sm">
                            <p className="font-medium text-blue-800">📝 Resolution Notes:</p>
                            <p className="text-gray-700">{bet.outcome_notes}</p>
                          </div>
                        )}
                        <p className="text-xs text-gray-500 mt-2">
                          Created: {new Date(bet.created_at).toLocaleDateString()}
                          {bet.accepted_at && ` • Accepted: ${new Date(bet.accepted_at).toLocaleDateString()}`}
                        </p>
                      </div>
                      {bet.status !== 'RESOLVED' && (
                        <Button 
                          onClick={() => {
                            setSelectedBet(bet)
                            setResolveDialogOpen(true)
                          }}
                          className="ml-4"
                        >
                          Resolve
                        </Button>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Resolve Dialog */}
      <Dialog open={resolveDialogOpen} onOpenChange={setResolveDialogOpen}>
        <DialogContent className="max-w-2xl [&>button]:bg-gray-800 [&>button]:text-white [&>button]:hover:bg-gray-900">
          <DialogHeader>
            <DialogTitle>Resolve Bet</DialogTitle>
          </DialogHeader>
          
          {selectedBet && (
            <div className="space-y-4">
              <div className="bg-gray-50 p-4 rounded">
                <p className="font-semibold mb-2">{selectedBet.event_description}</p>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <p className="font-medium">Proposer: {selectedBet.proposer.username}</p>
                    <p className="text-green-600">${(selectedBet.stake_proposer_cents / 100).toFixed(2)}</p>
                  </div>
                  <div>
                    <p className="font-medium">Acceptor: {selectedBet.acceptor?.username}</p>
                    <p className="text-green-600">${(selectedBet.stake_acceptor_cents / 100).toFixed(2)}</p>
                  </div>
                </div>
              </div>

              <div className="space-y-2">
                <Label>Outcome</Label>
                <div className="grid grid-cols-3 gap-2">
                  <Button
                    type="button"
                    onClick={() => setOutcome('PROPOSER_WIN')}
                    className={`w-full ${
                      outcome === 'PROPOSER_WIN' 
                        ? 'bg-blue-600 hover:bg-blue-700 text-white' 
                        : 'bg-gray-200 hover:bg-gray-300 text-gray-800 border-2 border-gray-400'
                    }`}
                  >
                    {selectedBet.proposer.username} Wins
                  </Button>
                  <Button
                    type="button"
                    onClick={() => setOutcome('ACCEPTOR_WIN')}
                    className={`w-full ${
                      outcome === 'ACCEPTOR_WIN' 
                        ? 'bg-blue-600 hover:bg-blue-700 text-white' 
                        : 'bg-gray-200 hover:bg-gray-300 text-gray-800 border-2 border-gray-400'
                    }`}
                  >
                    {selectedBet.acceptor?.username} Wins
                  </Button>
                  <Button
                    type="button"
                    onClick={() => setOutcome('VOID')}
                    className={`w-full ${
                      outcome === 'VOID' 
                        ? 'bg-blue-600 hover:bg-blue-700 text-white' 
                        : 'bg-gray-200 hover:bg-gray-300 text-gray-800 border-2 border-gray-400'
                    }`}
                  >
                    Void (Refund)
                  </Button>
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="notes">Resolution Notes (Optional)</Label>
                <Textarea
                  id="notes"
                  placeholder="Explain your decision..."
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  rows={3}
                  className="bg-white border-2 border-gray-300 focus:border-blue-500"
                />
              </div>

              <div className="bg-blue-50 p-3 rounded text-sm">
                <p className="font-medium mb-1">What happens next:</p>
                {outcome === 'VOID' ? (
                  <p>Both parties will get their stakes refunded</p>
                ) : outcome === 'PROPOSER_WIN' ? (
                  <p>{selectedBet.proposer.username} receives ${((selectedBet.stake_proposer_cents + (selectedBet.stake_acceptor_cents || 0)) / 100).toFixed(2)}</p>
                ) : (
                  <p>{selectedBet.acceptor?.username} receives ${((selectedBet.stake_proposer_cents + (selectedBet.stake_acceptor_cents || 0)) / 100).toFixed(2)}</p>
                )}
              </div>

              <div className="flex gap-2 justify-end">
                <Button
                  variant="outline"
                  onClick={() => {
                    setResolveDialogOpen(false)
                    setNotes('')
                  }}
                >
                  Cancel
                </Button>
                <Button
                  onClick={handleResolve}
                  disabled={loading}
                  className="bg-green-600 hover:bg-green-700"
                >
                  {loading ? 'Resolving...' : 'Confirm Resolution'}
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}