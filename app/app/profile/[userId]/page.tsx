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
        // Small delay to ensure auth context is set
        await new Promise(resolve => setTimeout(resolve, 200))
      }

      // Ensure targetUserId is a number
      const userIdNum = typeof targetUserId === 'string' ? parseInt(targetUserId, 10) : targetUserId

      // Use RPC function to bypass RLS and get all bets for this user
      const { data: rpcBets, error: rpcError } = await supabase.rpc(
        'get_user_bets_for_profile',
        { p_user_id: userIdNum }
      )

      if (rpcError) {
        // Only log meaningful errors (not empty objects)
        if (rpcError.message || Object.keys(rpcError).length > 0) {
          console.warn('RPC call failed, using fallback query:', rpcError.message || rpcError)
        }
        // Fallback to direct query (may be limited by RLS)
        const { data: fallbackBets, error: fallbackError } = await supabase
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

        if (fallbackError) {
          console.error('Error loading bets (fallback):', fallbackError)
          return
        }

        // Transform fallback data to match expected format
        const bets = (fallbackBets || []).map((bet: any) => ({
          ...bet,
          proposer: Array.isArray(bet.proposer) ? bet.proposer[0] : bet.proposer,
          acceptor: Array.isArray(bet.acceptor) ? bet.acceptor[0] : bet.acceptor,
          arbiter: Array.isArray(bet.arbiter) ? bet.arbiter[0] : bet.arbiter
        }))

        processBets(bets, userIdNum)
        return
      }

      // Transform RPC data to match Bet interface
      const bets = (rpcBets || []).map((bet: any) => ({
        bet_id: bet.bet_id,
        event_description: bet.event_description,
        status: bet.status,
        stake_proposer_cents: bet.stake_proposer_cents,
        stake_acceptor_cents: bet.stake_acceptor_cents,
        proposer_id: bet.proposer_id,
        acceptor_id: bet.acceptor_id,
        arbiter_id: bet.arbiter_id,
        outcome: bet.outcome,
        created_at: bet.created_at,
        proposer: bet.proposer_username ? { username: bet.proposer_username } : null,
        acceptor: bet.acceptor_username ? { username: bet.acceptor_username } : null,
        arbiter: bet.arbiter_username ? { username: bet.arbiter_username } : null
      }))

      processBets(bets, userIdNum)
    } catch (err) {
      console.error('Error in loadBets:', err)
    }
  }

  const processBets = (bets: Bet[], userIdNum: number) => {
    console.log(`Loaded ${bets.length} bets for user ${userIdNum}`, bets)
    
    const current = bets.filter(b => ['PENDING', 'ACTIVE', 'DISPUTED'].includes(b.status))
    const past = bets.filter(b => ['RESOLVED', 'CANCELED', 'EXPIRED'].includes(b.status))
    
    setCurrentBets(current as Bet[])
    setPastBets(past as Bet[])

    // Calculate wins/losses - only count bets where user is proposer or acceptor (not arbiter)
    // Also ensure bet has an acceptor (RESOLVED bets should always have one)
    const resolvedBets = bets.filter(b => 
      b.status === 'RESOLVED' && 
      b.outcome !== 'VOID' &&
      b.outcome !== null &&
      b.acceptor_id !== null && // Ensure bet has an acceptor
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

  const getUserRole = (bet: Bet, targetUserId: number) => {
    if (bet.proposer_id === targetUserId) return 'Proposer'
    if (bet.acceptor_id === targetUserId) return 'Acceptor'
    if (bet.arbiter_id === targetUserId) return 'Arbiter'
    return ''
  }

  const getOpponentName = (bet: Bet, targetUserId: number) => {
    // Only show opponent if user is proposer or acceptor (not arbiter)
    if (bet.proposer_id === targetUserId && bet.acceptor) return bet.acceptor.username
    if (bet.acceptor_id === targetUserId && bet.proposer) return bet.proposer.username
    // If user is arbiter, they don't have an opponent
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
    
    // RESOLVED bets must have an acceptor - if not, something is wrong
    if (!bet.acceptor_id) {
      console.warn('RESOLVED bet without acceptor_id:', bet.bet_id)
      return bet.status // Return status instead of WON/LOST
    }
    
    // Only calculate win/loss if user is proposer or acceptor (not arbiter)
    const isProposer = bet.proposer_id === targetUserId
    const isAcceptor = bet.acceptor_id === targetUserId
    
    // If user is only arbiter (not proposer or acceptor), return status
    if (!isProposer && !isAcceptor) {
      return bet.status // Arbiters don't win/lose
    }
    
    const isWinner = (bet.outcome === 'PROPOSER_WIN' && isProposer) ||
                     (bet.outcome === 'ACCEPTOR_WIN' && isAcceptor)
    
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

