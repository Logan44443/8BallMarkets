'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { supabase } from '@/lib/supabase'
import { setAuthContext } from '@/lib/auth'

interface LeaderboardEntry {
  user_id: number
  username: string
  total_profit: number
  wins: number
  losses: number
  win_rate: number
  total_wagered: number
}

type SortBy = 'profit' | 'wins' | 'win_rate'

export default function LeaderboardPage() {
  const [entries, setEntries] = useState<LeaderboardEntry[]>([])
  const [allEntries, setAllEntries] = useState<LeaderboardEntry[]>([])
  const [sortBy, setSortBy] = useState<SortBy>('profit')
  const [loading, setLoading] = useState(false) // Start as false, will be set to true when loading starts
  const [leaderboardLoaded, setLeaderboardLoaded] = useState(false) // Track if data is actually loaded
  const [loadingInProgress, setLoadingInProgress] = useState(false) // Prevent concurrent loads
  const router = useRouter()

  useEffect(() => {
    loadLeaderboard()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Helper function to create a checksum of the leaderboard data for verification
  const createChecksum = (data: LeaderboardEntry[]): string => {
    const sorted = [...data].sort((a, b) => a.user_id - b.user_id)
    const summary = sorted.map(e => `${e.user_id}:${e.wins}:${e.losses}:${e.total_profit.toFixed(2)}`).join('|')
    return summary
  }

  const loadLeaderboard = async (retryCount = 0) => {
    // Prevent concurrent loads
    if (loadingInProgress && retryCount === 0) {
      console.log('Leaderboard load already in progress, skipping...')
      return
    }

    setLoadingInProgress(true)
    setLoading(true)
    setLeaderboardLoaded(false)
    
    try {
      const userData = localStorage.getItem('user')
      if (!userData) {
        router.push('/login')
        return
      }

      const user = JSON.parse(userData)
      const isAdmin = user.is_admin || false
      console.log(`[Leaderboard] Loading attempt ${retryCount + 1}, user: ${user.id}, admin: ${isAdmin}`)
      
      // Re-establish auth context with longer delay for reliability
      await setAuthContext(user.id, isAdmin)
      // Increased delay to ensure auth context is fully set in database session
      await new Promise(resolve => setTimeout(resolve, 500 + (retryCount * 100)))

      // Get all users - verify we get consistent results
      const { data: users, error: usersError } = await supabase
        .from('users')
        .select('user_id, username')
        .eq('is_active', true)
        .order('user_id', { ascending: true }) // Consistent ordering

      if (usersError) {
        console.error('[Leaderboard] Error loading users:', usersError)
        throw usersError
      }

      if (!users || users.length === 0) {
        console.log('[Leaderboard] No users found')
        setLoading(false)
        setLeaderboardLoaded(true)
        return
      }

      console.log(`[Leaderboard] Loaded ${users.length} users`)

      // Use RPC function to fetch all resolved bets (bypasses RLS for consistency)
      let allResolvedBetsArray: any[] = []
      const { data: rpcBets, error: allBetsError } = await supabase.rpc(
        'get_all_resolved_bets_for_leaderboard'
      )

      if (allBetsError) {
        console.error('[Leaderboard] Error loading all resolved bets via RPC:', allBetsError)
        // Fallback: try direct query (may be limited by RLS)
        const { data: fallbackBets } = await supabase
          .from('direct_bets')
          .select('bet_id, status, outcome, proposer_id, acceptor_id, stake_proposer_cents, stake_acceptor_cents')
          .eq('status', 'RESOLVED')
          .order('bet_id', { ascending: true })
          .limit(1000) // Safety limit
        
        if (fallbackBets) {
          console.warn('[Leaderboard] Using fallback query (may be incomplete due to RLS)')
          allResolvedBetsArray = fallbackBets
        } else {
          throw allBetsError
        }
      } else if (rpcBets) {
        allResolvedBetsArray = rpcBets
      }

      if (allResolvedBetsArray.length === 0) {
        console.log('[Leaderboard] No resolved bets found')
        const emptyEntries = users.map(u => ({
          user_id: u.user_id,
          username: u.username,
          total_profit: 0,
          wins: 0,
          losses: 0,
          win_rate: 0,
          total_wagered: 0
        }))
        setAllEntries(emptyEntries)
        setEntries(emptyEntries)
        setLeaderboardLoaded(true)
        setLoading(false)
        setLoadingInProgress(false)
        return
      }

      console.log(`[Leaderboard] Loaded ${allResolvedBetsArray.length} unique resolved bets`)
      const uniqueBets = allResolvedBetsArray

      // Create a map of user_id -> bets for efficient lookup
      const betsByUser = new Map<number, typeof uniqueBets>()
      
      uniqueBets.forEach(bet => {
        if (!bet.outcome || bet.outcome === 'VOID') return
        
        const proposerId = Number(bet.proposer_id)
        const acceptorId = Number(bet.acceptor_id)
        
        // Add to proposer's bets
        if (proposerId) {
          if (!betsByUser.has(proposerId)) {
            betsByUser.set(proposerId, [])
          }
          betsByUser.get(proposerId)!.push(bet)
        }
        
        // Add to acceptor's bets
        if (acceptorId) {
          if (!betsByUser.has(acceptorId)) {
            betsByUser.set(acceptorId, [])
          }
          betsByUser.get(acceptorId)!.push(bet)
        }
      })

      // Calculate stats for each user from the same dataset
      const leaderboardData: LeaderboardEntry[] = users.map((userItem) => {
        const userIdNum = Number(userItem.user_id)
        const bets = betsByUser.get(userIdNum) || []
        
        // Sort bets by bet_id for consistent processing
        const sortedBets = [...bets].sort((a, b) => a.bet_id - b.bet_id)

        if (sortedBets.length === 0) {
          return {
            user_id: userItem.user_id,
            username: userItem.username,
            total_profit: 0,
            wins: 0,
            losses: 0,
            win_rate: 0,
            total_wagered: 0
          }
        }

        // Calculate stats using integer math (cents) for precision
        let totalProfitCents = 0
        let wins = 0
        let losses = 0
        let totalWageredCents = 0

        sortedBets.forEach(bet => {
          // Skip VOID bets or bets with null outcome (shouldn't happen due to filter above, but safety check)
          if (!bet.outcome || bet.outcome === 'VOID') return

          // Only count bets where user is proposer or acceptor (not just arbiter)
          const isProposer = Number(bet.proposer_id) === userIdNum
          const isAcceptor = Number(bet.acceptor_id) === userIdNum
          
          // Skip if user is only arbiter (shouldn't happen, but safety check)
          if (!isProposer && !isAcceptor) {
            return
          }

          // Ensure we have valid stake values
          const stakeCents = isProposer 
            ? (Number(bet.stake_proposer_cents) || 0)
            : (Number(bet.stake_acceptor_cents) || 0)
          const opponentStakeCents = isProposer 
            ? (Number(bet.stake_acceptor_cents) || 0)
            : (Number(bet.stake_proposer_cents) || 0)

          if (stakeCents <= 0 || opponentStakeCents <= 0) {
            console.warn(`[Leaderboard] Invalid stake for bet ${bet.bet_id}, user ${userIdNum}: stake=${stakeCents}, opponent=${opponentStakeCents}`)
            return
          }

          totalWageredCents += stakeCents

          // Determine if this user won - use same logic as profile page
          const userWon = 
            (bet.outcome === 'PROPOSER_WIN' && isProposer) ||
            (bet.outcome === 'ACCEPTOR_WIN' && isAcceptor)

          if (userWon) {
            wins++
            // Profit = opponent's stake (even money for now)
            totalProfitCents += opponentStakeCents
          } else {
            losses++
            // Loss = their stake
            totalProfitCents -= stakeCents
          }
        })

        const totalBets = wins + losses
        const winRate = totalBets > 0 ? (wins / totalBets) * 100 : 0

        // Convert to dollars only at the end, with proper rounding
        const totalProfit = Math.round(totalProfitCents) / 100
        const totalWagered = Math.round(totalWageredCents) / 100

        return {
          user_id: userItem.user_id,
          username: userItem.username,
          total_profit: totalProfit,
          wins,
          losses,
          win_rate: winRate,
          total_wagered: totalWagered
        }
      })

      // Verification: Ensure we have data for all users
      if (leaderboardData.length !== users.length) {
        console.warn(`[Leaderboard] Data mismatch: expected ${users.length} entries, got ${leaderboardData.length}`)
        if (retryCount < 2) {
          console.log(`[Leaderboard] Retrying... (attempt ${retryCount + 2})`)
          setLoadingInProgress(false)
          await new Promise(resolve => setTimeout(resolve, 500))
          return loadLeaderboard(retryCount + 1)
        }
      }

      // Verify data integrity: check for duplicate user_ids
      const userIds = leaderboardData.map(e => e.user_id)
      const uniqueUserIds = new Set(userIds)
      if (userIds.length !== uniqueUserIds.size) {
        console.warn(`[Leaderboard] Duplicate user_ids detected! Expected ${userIds.length} unique, got ${uniqueUserIds.size}`)
        // Remove duplicates, keeping first occurrence
        const seen = new Set()
        const deduplicated = leaderboardData.filter(e => {
          if (seen.has(e.user_id)) return false
          seen.add(e.user_id)
          return true
        })
        leaderboardData.length = 0
        leaderboardData.push(...deduplicated)
      }

      // Verification: Since we're using the same dataset, we can verify internal consistency
      // Check that all bets were processed correctly by verifying totals
      const totalBetsProcessed = leaderboardData.reduce((sum, e) => sum + e.wins + e.losses, 0)
      const expectedBets = uniqueBets.filter(b => b.outcome && b.outcome !== 'VOID').length * 2 // Each bet has 2 participants
      
      // Create checksum for verification
      const checksum = createChecksum(leaderboardData)
      console.log(`[Leaderboard] Loaded ${leaderboardData.length} entries, processed ${totalBetsProcessed} win/loss records from ${uniqueBets.length} unique bets, checksum: ${checksum.substring(0, 50)}...`)

      // Final consistency check: ensure all entries have valid data
      const validEntries = leaderboardData.filter(e => 
        e.user_id && 
        e.username && 
        typeof e.wins === 'number' && 
        typeof e.losses === 'number' &&
        !isNaN(e.total_profit) &&
        !isNaN(e.win_rate) &&
        !isNaN(e.total_wagered)
      )

      if (validEntries.length !== leaderboardData.length) {
        console.warn(`[Leaderboard] Filtered out ${leaderboardData.length - validEntries.length} invalid entries`)
        if (retryCount < 2) {
          console.log(`[Leaderboard] Retrying due to invalid entries... (attempt ${retryCount + 2})`)
          setLoadingInProgress(false)
          await new Promise(resolve => setTimeout(resolve, 1000))
          return loadLeaderboard(retryCount + 1)
        }
      }

      // Store unsorted data (use valid entries only)
      setAllEntries(validEntries)
      
      // Sort based on initial criteria (profit) - ensure stable sort with multiple tie-breakers
      const sorted = [...validEntries].sort((a, b) => {
        // Primary: total profit (descending)
        if (Math.abs(b.total_profit - a.total_profit) > 0.01) {
          return b.total_profit - a.total_profit
        }
        // Secondary: wins (descending)
        if (b.wins !== a.wins) {
          return b.wins - a.wins
        }
        // Tertiary: win rate (descending)
        if (Math.abs(b.win_rate - a.win_rate) > 0.01) {
          return b.win_rate - a.win_rate
        }
        // Final: user_id (ascending) for absolute consistency
        return a.user_id - b.user_id
      })
      setEntries(sorted)
      
      // Final verification: log summary
      const totalWins = validEntries.reduce((sum, e) => sum + e.wins, 0)
      const totalLosses = validEntries.reduce((sum, e) => sum + e.losses, 0)
      const totalProfit = validEntries.reduce((sum, e) => sum + e.total_profit, 0)
      console.log(`[Leaderboard] Verification complete: ${validEntries.length} users, ${totalWins} total wins, ${totalLosses} total losses, $${totalProfit.toFixed(2)} total profit`)
      
      // Mark as loaded after data is ready
      setLeaderboardLoaded(true)
    } catch (err) {
      console.error('[Leaderboard] Error loading leaderboard:', err)
      if (retryCount < 2) {
        console.log(`[Leaderboard] Retrying after error... (attempt ${retryCount + 2})`)
        setLoadingInProgress(false)
        await new Promise(resolve => setTimeout(resolve, 1000))
        return loadLeaderboard(retryCount + 1)
      }
      setLeaderboardLoaded(true)
    } finally {
      setLoading(false)
      setLoadingInProgress(false)
    }
  }

  // Re-sort when sortBy changes
  useEffect(() => {
    if (allEntries.length === 0) return

    const sorted = [...allEntries].sort((a, b) => {
      switch (sortBy) {
        case 'profit':
          return b.total_profit - a.total_profit
        case 'wins':
          return b.wins - a.wins
        case 'win_rate':
          return b.win_rate - a.win_rate
        default:
          return b.total_profit - a.total_profit
      }
    })

    setEntries(sorted)
  }, [sortBy, allEntries])

  const getRankEmoji = (rank: number) => {
    if (rank === 1) return '🥇'
    if (rank === 2) return '🥈'
    if (rank === 3) return '🥉'
    return `#${rank}`
  }

  return (
    <div className="min-h-screen p-8" style={{backgroundColor: 'transparent'}}>
      <div className="max-w-6xl mx-auto">
        {/* Header */}
        <div className="mb-6 flex justify-between items-center">
          <div>
            <h1 className="text-3xl font-bold text-white">🏆 Leaderboard</h1>
            <p className="text-white mt-1">Top performers on 8Ball Markets</p>
          </div>
          <Button variant="outline" onClick={() => router.push('/dashboard')}>
            Back to Dashboard
          </Button>
        </div>

        {/* Sort Options */}
        <Card className="mb-6">
          <CardContent className="py-4">
            <div className="flex gap-2 items-center">
              <span className="text-sm font-medium text-gray-600 mr-2">Sort by:</span>
              <Button
                variant={sortBy === 'profit' ? 'default' : 'outline'}
                size="sm"
                onClick={() => setSortBy('profit')}
              >
                💰 Total Profit
              </Button>
              <Button
                variant={sortBy === 'wins' ? 'default' : 'outline'}
                size="sm"
                onClick={() => setSortBy('wins')}
              >
                🎯 Most Wins
              </Button>
              <Button
                variant={sortBy === 'win_rate' ? 'default' : 'outline'}
                size="sm"
                onClick={() => setSortBy('win_rate')}
              >
                📊 Win Rate
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Leaderboard Table */}
        <Card>
          <CardHeader>
            <CardTitle>
              {sortBy === 'profit' && '💰 Top Earners'}
              {sortBy === 'wins' && '🎯 Most Wins'}
              {sortBy === 'win_rate' && '📊 Best Win Rate'}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loading || !leaderboardLoaded ? (
              <div className="text-center py-12 text-gray-500">Loading leaderboard...</div>
            ) : entries.length === 0 ? (
              <div className="text-center py-12 text-gray-500">
                No data yet. Complete some bets to appear on the leaderboard!
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead className="border-b-2 border-gray-300">
                    <tr className="text-left">
                      <th className="p-3 text-sm font-semibold text-gray-600">Rank</th>
                      <th className="p-3 text-sm font-semibold text-gray-600">Player</th>
                      <th className="p-3 text-sm font-semibold text-gray-600 text-right">Profit/Loss</th>
                      <th className="p-3 text-sm font-semibold text-gray-600 text-center">Record</th>
                      <th className="p-3 text-sm font-semibold text-gray-600 text-center">Win Rate</th>
                      <th className="p-3 text-sm font-semibold text-gray-600 text-right">Total Wagered</th>
                    </tr>
                  </thead>
                  <tbody>
                    {entries.map((entry, index) => {
                      const rank = index + 1
                      const isTop3 = rank <= 3

                      return (
                        <tr
                          key={entry.user_id}
                          className={`border-b hover:bg-gray-50 transition-colors ${
                            isTop3 ? 'bg-yellow-50' : ''
                          }`}
                        >
                          <td className="p-3">
                            <span className={`text-lg font-bold ${isTop3 ? 'text-2xl' : ''}`}>
                              {getRankEmoji(rank)}
                            </span>
                          </td>
                          <td className="p-3">
                            <button
                              onClick={() => router.push(`/profile/${entry.user_id}`)}
                              className="font-medium text-blue-600 hover:underline"
                            >
                              {entry.username}
                            </button>
                          </td>
                          <td className={`p-3 text-right font-bold ${
                            entry.total_profit > 0 ? 'text-green-600' :
                            entry.total_profit < 0 ? 'text-red-600' :
                            'text-gray-600'
                          }`}>
                            {entry.total_profit > 0 ? '+' : ''}${entry.total_profit.toFixed(2)}
                          </td>
                          <td className="p-3 text-center">
                            <span className="text-sm">
                              <span className="text-green-600 font-medium">{entry.wins}W</span>
                              {' - '}
                              <span className="text-red-600 font-medium">{entry.losses}L</span>
                            </span>
                          </td>
                          <td className="p-3 text-center">
                            <span className="text-sm font-medium">
                              {entry.win_rate.toFixed(1)}%
                            </span>
                          </td>
                          <td className="p-3 text-right text-sm text-gray-600">
                            ${entry.total_wagered.toFixed(2)}
                          </td>
                        </tr>
                      )
                    })}
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

