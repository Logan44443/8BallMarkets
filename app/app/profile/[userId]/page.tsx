'use client'

import { useEffect, useState } from 'react'
import { useRouter, useParams } from 'next/navigation'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { supabase } from '@/lib/supabase'
import { setAuthContext } from '@/lib/auth'

interface User {
  user_id: number
  username: string
  created_at: string
}

interface Bet {
  bet_id: number
  event_description: string
  status: string
  stake_proposer_cents: number
  stake_acceptor_cents: number
  proposer_id: number
  acceptor_id: number
  arbiter_id: number | null
  outcome: string | null
  created_at: string
  proposer: { username: string }
  acceptor: { username: string } | null
  arbiter: { username: string } | null
}

export default function UserProfilePage() {
  const params = useParams()
  const userId = params?.userId as string
  const [profileUser, setProfileUser] = useState<User | null>(null)
  const [currentBets, setCurrentBets] = useState<Bet[]>([])
  const [pastBets, setPastBets] = useState<Bet[]>([])
  const [wins, setWins] = useState(0)
  const [losses, setLosses] = useState(0)
  const [currentUserId, setCurrentUserId] = useState<number | null>(null)
  const router = useRouter()

  useEffect(() => {
    loadProfile()
  }, [userId])

  const loadProfile = async () => {
    // Get current logged-in user
    const userData = localStorage.getItem('user')
    if (!userData) {
      router.push('/login')
      return
    }

    const parsedUser = JSON.parse(userData)
    setCurrentUserId(parsedUser.id)
    await setAuthContext(parsedUser.id, parsedUser.is_admin || false)

    // Load profile user data
    const { data: userProfile } = await supabase
      .from('users')
      .select('user_id, username, created_at')
      .eq('user_id', userId)
      .single()

    if (userProfile) {
      setProfileUser(userProfile)
      loadBets(parseInt(userId))
    }
  }

  const loadBets = async (targetUserId: number) => {
    try {
      // Re-establish auth context before query
      const userData = localStorage.getItem('user')
      if (userData) {
        const parsedUser = JSON.parse(userData)
        await setAuthContext(parsedUser.id, parsedUser.is_admin || false)
      }

      // Ensure targetUserId is a number
      const userIdNum = typeof targetUserId === 'string' ? parseInt(targetUserId, 10) : targetUserId

      // Load all bets where this user is involved
      const { data: bets, error } = await supabase
        .from('direct_bets')
        .select(`
          bet_id,
          event_description,
          status,
          stake_proposer_cents,
          stake_acceptor_cents,
          proposer_id,
          acceptor_id,
          arbiter_id,
          outcome,
          created_at,
          proposer:users!direct_bets_proposer_id_fkey(username),
          acceptor:users!direct_bets_acceptor_id_fkey(username),
          arbiter:users!direct_bets_arbiter_id_fkey(username)
        `)
        .or(`proposer_id.eq.${userIdNum},acceptor_id.eq.${userIdNum},arbiter_id.eq.${userIdNum}`)
        .order('created_at', { ascending: false })

      if (error) {
        console.error('Error loading bets:', error)
        return
      }

      if (bets) {
        console.log(`Loaded ${bets.length} bets for user ${userIdNum}`, bets)
        
        const current = bets.filter(b => ['PENDING', 'ACTIVE', 'DISPUTED'].includes(b.status))
        const past = bets.filter(b => ['RESOLVED', 'CANCELED', 'EXPIRED'].includes(b.status))
        
        setCurrentBets(current as Bet[])
        setPastBets(past as Bet[])

        // Calculate wins/losses - ensure numeric comparison
        const resolvedBets = bets.filter(b => 
          b.status === 'RESOLVED' && 
          b.outcome !== 'VOID' &&
          b.outcome !== null &&
          (Number(b.proposer_id) === userIdNum || Number(b.acceptor_id) === userIdNum)
        )

        console.log(`Resolved bets for user ${userIdNum}:`, resolvedBets)

        const winCount = resolvedBets.filter(b => 
          (b.outcome === 'PROPOSER_WIN' && Number(b.proposer_id) === userIdNum) ||
          (b.outcome === 'ACCEPTOR_WIN' && Number(b.acceptor_id) === userIdNum)
        ).length

        const lossCount = resolvedBets.filter(b =>
          (b.outcome === 'PROPOSER_WIN' && Number(b.acceptor_id) === userIdNum) ||
          (b.outcome === 'ACCEPTOR_WIN' && Number(b.proposer_id) === userIdNum)
        ).length

        console.log(`Wins: ${winCount}, Losses: ${lossCount}`)
        setWins(winCount)
        setLosses(lossCount)
      }
    } catch (err) {
      console.error('Error in loadBets:', err)
    }
  }

  const getUserRole = (bet: Bet, targetUserId: number) => {
    if (bet.proposer_id === targetUserId) return 'Proposer'
    if (bet.acceptor_id === targetUserId) return 'Acceptor'
    if (bet.arbiter_id === targetUserId) return 'Arbiter'
    return ''
  }

  const getOpponentName = (bet: Bet, targetUserId: number) => {
    if (bet.proposer_id === targetUserId && bet.acceptor) return bet.acceptor.username
    if (bet.acceptor_id === targetUserId) return bet.proposer.username
    return 'N/A'
  }

  const getOpponentId = (bet: Bet, targetUserId: number) => {
    if (bet.proposer_id === targetUserId) return bet.acceptor_id
    if (bet.acceptor_id === targetUserId) return bet.proposer_id
    return null
  }

  const getBetOutcome = (bet: Bet, targetUserId: number) => {
    if (bet.status !== 'RESOLVED') return bet.status
    if (bet.outcome === 'VOID') return 'VOID'
    
    const isWinner = (bet.outcome === 'PROPOSER_WIN' && bet.proposer_id === targetUserId) ||
                     (bet.outcome === 'ACCEPTOR_WIN' && bet.acceptor_id === targetUserId)
    
    return isWinner ? 'WON' : 'LOST'
  }

  if (!profileUser) {
    return <div className="min-h-screen flex items-center justify-center">Loading...</div>
  }

  const targetUserId = parseInt(userId)

  return (
    <div className="min-h-screen p-8" style={{backgroundColor: 'transparent'}}>
      <div className="max-w-6xl mx-auto">
        {/* Header */}
        <div className="mb-6 flex justify-between items-center">
          <div>
            <h1 className="text-3xl font-bold text-white">{profileUser.username}</h1>
            <p className="text-lg text-white mt-1">{wins} Wins - {losses} Losses</p>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => router.back()}>
              Back
            </Button>
            <Button variant="outline" onClick={() => router.push('/dashboard')}>
              Dashboard
            </Button>
          </div>
        </div>

        {/* Current Bets */}
        <Card className="mb-6">
          <CardHeader>
            <CardTitle>Current Bets</CardTitle>
          </CardHeader>
          <CardContent>
            {currentBets.length === 0 ? (
              <p className="text-gray-500">No current bets</p>
            ) : (
              <div className="space-y-3">
                {currentBets.map(bet => (
                  <div key={bet.bet_id} className="border rounded-lg p-4 hover:bg-gray-50">
                    <div className="flex justify-between items-start">
                      <div className="flex-1">
                        <p className="font-semibold">{bet.event_description}</p>
                        <div className="mt-2 text-sm text-gray-600 space-y-1">
                          <p>Role: <span className="font-medium">{getUserRole(bet, targetUserId)}</span></p>
                          <p>
                            vs{' '}
                            {getOpponentId(bet, targetUserId) ? (
                              <button
                                onClick={() => router.push(`/profile/${getOpponentId(bet, targetUserId)}`)}
                                className="text-blue-600 hover:underline font-medium"
                              >
                                @{getOpponentName(bet, targetUserId)}
                              </button>
                            ) : (
                              <span className="text-gray-500">Waiting for opponent</span>
                            )}
                          </p>
                          <p>Amount: ${(bet.stake_proposer_cents / 100).toFixed(2)}</p>
                          <p>Date: {new Date(bet.created_at).toLocaleDateString()}</p>
                        </div>
                      </div>
                      <span className={`px-3 py-1 rounded-full text-sm font-medium ${
                        bet.status === 'ACTIVE' ? 'bg-green-100 text-green-800' :
                        bet.status === 'DISPUTED' ? 'bg-red-100 text-red-800' :
                        'bg-yellow-100 text-yellow-800'
                      }`}>
                        {bet.status}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Past Bets */}
        <Card className="mb-6">
          <CardHeader>
            <CardTitle>Past Bets</CardTitle>
          </CardHeader>
          <CardContent>
            {pastBets.length === 0 ? (
              <p className="text-gray-500">No past bets</p>
            ) : (
              <div className="space-y-3">
                {pastBets.map(bet => (
                  <div key={bet.bet_id} className="border rounded-lg p-4 hover:bg-gray-50">
                    <div className="flex justify-between items-start">
                      <div className="flex-1">
                        <p className="font-semibold">{bet.event_description}</p>
                        <div className="mt-2 text-sm text-gray-600 space-y-1">
                          <p>Role: <span className="font-medium">{getUserRole(bet, targetUserId)}</span></p>
                          <p>
                            vs{' '}
                            {getOpponentId(bet, targetUserId) ? (
                              <button
                                onClick={() => router.push(`/profile/${getOpponentId(bet, targetUserId)}`)}
                                className="text-blue-600 hover:underline font-medium"
                              >
                                @{getOpponentName(bet, targetUserId)}
                              </button>
                            ) : (
                              <span className="text-gray-500">No opponent</span>
                            )}
                          </p>
                          <p>Amount: ${(bet.stake_proposer_cents / 100).toFixed(2)}</p>
                          <p>Date: {new Date(bet.created_at).toLocaleDateString()}</p>
                        </div>
                      </div>
                      <span className={`px-3 py-1 rounded-full text-sm font-medium ${
                        getBetOutcome(bet, targetUserId) === 'WON' ? 'bg-green-100 text-green-800' :
                        getBetOutcome(bet, targetUserId) === 'LOST' ? 'bg-red-100 text-red-800' :
                        'bg-gray-100 text-gray-800'
                      }`}>
                        {getBetOutcome(bet, targetUserId)}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

