'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
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

interface Friend {
  user_id: number
  friend_id: number
  friended_at: string
  friend: { username: string }
}

interface FriendRequest {
  request_id: number
  sender_id: number
  receiver_id: number
  status: string
  requested_at: string
  sender: { username: string }
  receiver: { username: string }
}

interface SearchUser {
  user_id: number
  username: string
}

export default function ProfilePage() {
  const [user, setUser] = useState<User | null>(null)
  const [currentBets, setCurrentBets] = useState<Bet[]>([])
  const [pastBets, setPastBets] = useState<Bet[]>([])
  const [wins, setWins] = useState(0)
  const [losses, setLosses] = useState(0)
  const [loadingBets, setLoadingBets] = useState(false)
  const [betsLoaded, setBetsLoaded] = useState(false) // Track if bets have been successfully loaded at least once
  const [friends, setFriends] = useState<Friend[]>([])
  const [sentRequests, setSentRequests] = useState<FriendRequest[]>([])
  const [incomingRequests, setIncomingRequests] = useState<FriendRequest[]>([])
  const [searchQuery, setSearchQuery] = useState('')
  const [searchUsers, setSearchUsers] = useState<SearchUser[]>([])
  const [selectedUser, setSelectedUser] = useState<SearchUser | null>(null)
  const [sendingRequest, setSendingRequest] = useState(false)
  const [adminPassword, setAdminPassword] = useState('')
  const [isAdmin, setIsAdmin] = useState(false)
  const [unlockingAdmin, setUnlockingAdmin] = useState(false)
  const router = useRouter()

  useEffect(() => {
    loadProfile()
  }, [])

  useEffect(() => {
    if (searchQuery.trim() && user) {
      searchForUsers()
    } else {
      setSearchUsers([])
      setSelectedUser(null)
    }
  }, [searchQuery, user])

  const loadProfile = async () => {
    const userData = localStorage.getItem('user')
    if (!userData) {
      router.push('/login')
      return
    }

    const parsedUser = JSON.parse(userData)
    console.log('loadProfile: Setting auth context for user:', parsedUser.id)
    await setAuthContext(parsedUser.id, parsedUser.is_admin || false)
    // Wait a bit for auth context to be set before loading data
    await new Promise(resolve => setTimeout(resolve, 300))

    // Load user data
    const { data: userProfile } = await supabase
      .from('users')
      .select('user_id, username, created_at')
      .eq('user_id', parsedUser.id)
      .single()

    if (userProfile) {
      setUser(userProfile)
      setIsAdmin(parsedUser.is_admin || false)
      // Load bets after a delay to ensure auth context is fully set
      setTimeout(() => {
        loadBets(userProfile.user_id)
      }, 200)
      loadFriends(userProfile.user_id)
    }
  }

  const handleAdminUnlock = async () => {
    if (adminPassword !== 'ADMIN') {
      alert('Incorrect admin password')
      return
    }

    setUnlockingAdmin(true)
    try {
      if (!user) return

      // Update user to admin in database
      const { error } = await supabase
        .from('users')
        .update({ is_admin: true })
        .eq('user_id', user.user_id)

      if (error) {
        alert('Failed to unlock admin access')
        return
      }

      // Update localStorage
      const userData = localStorage.getItem('user')
      if (userData) {
        const parsedUser = JSON.parse(userData)
        parsedUser.is_admin = true
        localStorage.setItem('user', JSON.stringify(parsedUser))
      }

      // Update auth context
      await setAuthContext(user.user_id, true)

      setIsAdmin(true)
      alert('Admin access unlocked! You now have admin privileges.')
      setAdminPassword('')
    } catch (err) {
      console.error('Error unlocking admin:', err)
      alert('An error occurred')
    } finally {
      setUnlockingAdmin(false)
    }
  }

  const loadBets = async (userId: number, retryCount = 0) => {
    // Prevent concurrent loads
    if (loadingBets && retryCount === 0) {
      console.log('Bets already loading, skipping...')
      return
    }
    
    setLoadingBets(true)
    // Reset betsLoaded on first attempt (not on retry)
    if (retryCount === 0) {
      setBetsLoaded(false)
    }
    try {
      // Re-establish auth context before query - do this first and wait
      const userData = localStorage.getItem('user')
      if (userData) {
        const parsedUser = JSON.parse(userData)
        console.log('Setting auth context for user:', parsedUser.id, 'is_admin:', parsedUser.is_admin, 'retry:', retryCount)
        await setAuthContext(parsedUser.id, parsedUser.is_admin || false)
        // Longer delay to ensure auth context is fully set in the database session
        // Increase delay on retry
        await new Promise(resolve => setTimeout(resolve, 300 + (retryCount * 200)))
      }

      // Load all bets where user is involved
      console.log('=== LOADING BETS DEBUG ===')
      console.log('Querying for user_id:', userId, 'type:', typeof userId, 'retry:', retryCount)
      
      // Ensure userId is a number for the query
      const userIdNum = Number(userId)
      
      // Use combined query - the .or() query works and returns all bets (including acceptor)
      // Separate queries have RLS issues with acceptor_id
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
          arbiter_id,
          outcome,
          created_at,
          proposer:users!direct_bets_proposer_id_fkey(username),
          acceptor:users!direct_bets_acceptor_id_fkey(username),
          arbiter:users!direct_bets_arbiter_id_fkey(username)
        `)
        .or(`proposer_id.eq.${userIdNum},acceptor_id.eq.${userIdNum},arbiter_id.eq.${userIdNum}`)
        .order('created_at', { ascending: false })

      // Transform the data to match Bet interface (handle array vs object for relations)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const bets = (betsData || []).map((bet: any) => ({
        ...bet,
        proposer: Array.isArray(bet.proposer) ? bet.proposer[0] : bet.proposer,
        acceptor: Array.isArray(bet.acceptor) ? bet.acceptor[0] : bet.acceptor,
        arbiter: Array.isArray(bet.arbiter) ? bet.arbiter[0] : bet.arbiter
      }))
      
      console.log('Total bets loaded from combined query:', bets.length)
      
      // If we got 0 bets but this is the first try, retry once after a longer delay
      // This handles race conditions where auth context isn't fully set yet
      if (bets.length === 0 && retryCount === 0 && !error) {
        console.log('Got 0 bets on first try, retrying after longer delay...')
        setLoadingBets(false) // Reset loading state for retry
        setTimeout(() => {
          loadBets(userId, 1) // Retry once
        }, 500)
        return
      }
      
      // Mark bets as loaded only if we got data (even if 0 bets, that's valid data)
      // Or if we're on retry and got data
      if (bets.length > 0 || retryCount > 0 || error) {
        setBetsLoaded(true)
      }

      if (error) {
        console.error('Error loading bets:', error)
        console.log('=== END LOADING BETS DEBUG ===')
        return
      }

      console.log('Raw bets loaded:', bets?.length || 0)
      console.log('Raw bets data:', bets)
      if (bets && bets.length > 0) {
        console.log('First bet details:', {
          bet_id: bets[0].bet_id,
          status: bets[0].status,
          outcome: bets[0].outcome,
          proposer_id: bets[0].proposer_id,
          acceptor_id: bets[0].acceptor_id,
          arbiter_id: bets[0].arbiter_id,
          proposer_id_type: typeof bets[0].proposer_id,
          acceptor_id_type: typeof bets[0].acceptor_id
        })
      }
      console.log('=== END LOADING BETS DEBUG ===')

      if (bets) {
        console.log('=== FILTERING BETS DEBUG ===')
        console.log('All bet statuses:', bets.map(b => ({ bet_id: b.bet_id, status: b.status, outcome: b.outcome })))
        
        const current = bets.filter(b => ['PENDING', 'ACTIVE', 'DISPUTED'].includes(b.status))
        const past = bets.filter(b => ['RESOLVED', 'CANCELED', 'EXPIRED'].includes(b.status))
        
        console.log('Current bets count:', current.length)
        console.log('Past bets count:', past.length)
        console.log('Past bets statuses:', past.map(b => ({ bet_id: b.bet_id, status: b.status, outcome: b.outcome })))
        console.log('Existing pastBets count:', pastBets.length)
        console.log('=== END FILTERING BETS DEBUG ===')
        
        // Only update if we got more bets than we currently have (prevent overwriting with incomplete data)
        if (bets.length >= pastBets.length + currentBets.length || pastBets.length === 0) {
          setCurrentBets(current as Bet[])
          setPastBets(past as Bet[])
        } else {
          console.warn('Skipping state update - got fewer bets than existing state. Existing:', pastBets.length + currentBets.length, 'New:', bets.length)
        }

        // Calculate wins/losses - use EXACT same logic as getBetOutcome function
        // Count all RESOLVED bets in past bets section and use same calculation as display
        const pastResolved = past.filter(b => b.status === 'RESOLVED')
        
        // Helper function that matches getBetOutcome exactly
        const calculateOutcome = (bet: Bet) => {
          if (bet.status !== 'RESOLVED') return bet.status
          if (bet.outcome === 'VOID') return 'VOID'
          
          // Only calculate win/loss if user is proposer or acceptor (not arbiter)
          const isProposer = bet.proposer_id === userId
          const isAcceptor = bet.acceptor_id === userId
          
          // If user is only arbiter, return status (arbiters don't win/lose)
          if (!isProposer && !isAcceptor) {
            return bet.status
          }
          
          const isWinner = (bet.outcome === 'PROPOSER_WIN' && isProposer) ||
                          (bet.outcome === 'ACCEPTOR_WIN' && isAcceptor)
          return isWinner ? 'WON' : 'LOST'
        }
        
        // Count wins/losses - only count bets where user is proposer or acceptor
        const participantBets = pastResolved.filter(b => 
          b.proposer_id === userId || b.acceptor_id === userId
        )
        const winCount = participantBets.filter(b => calculateOutcome(b) === 'WON').length
        const lossCount = participantBets.filter(b => calculateOutcome(b) === 'LOST').length

        // DEBUG: Log win/loss calculation details
        console.log('=== WIN/LOSS CALCULATION DEBUG ===')
        console.log('User ID:', userId, '(type:', typeof userId, ')')
        console.log('Total bets loaded:', bets.length)
        console.log('Resolved bets (for win/loss):', pastResolved.length)
        console.log('Past bets (all):', past.length)
        console.log('Past bets (RESOLVED only):', pastResolved.length)
        console.log('Past bets details (EXPANDED):', JSON.stringify(pastResolved.map(b => {
          const outcome = calculateOutcome(b)
          const isProposer = b.proposer_id === userId
          const isAcceptor = b.acceptor_id === userId
          const winCheck = (b.outcome === 'PROPOSER_WIN' && isProposer) || 
                          (b.outcome === 'ACCEPTOR_WIN' && isAcceptor)
          const lossCheck = (b.outcome === 'PROPOSER_WIN' && isAcceptor) ||
                           (b.outcome === 'ACCEPTOR_WIN' && isProposer)
          return {
            bet_id: b.bet_id,
            status: b.status,
            outcome: b.outcome,
            proposer_id: b.proposer_id,
            acceptor_id: b.acceptor_id,
            arbiter_id: b.arbiter_id,
            display_outcome: outcome,
            is_proposer: isProposer,
            is_acceptor: isAcceptor,
            proposer_id_type: typeof b.proposer_id,
            acceptor_id_type: typeof b.acceptor_id,
            userId: userId,
            userId_type: typeof userId,
            win_check: winCheck,
            loss_check: lossCheck,
            should_be_win: winCheck,
            should_be_loss: lossCheck
          }
        }), null, 2))
        console.log('Calculated wins:', winCount)
        console.log('Calculated losses:', lossCount)
        console.log('=== END DEBUG ===')

        setWins(winCount)
        setLosses(lossCount)
        
        // Mark as loaded after calculating wins/losses
        setBetsLoaded(true)
      }
    } catch (err) {
      console.error('Error in loadBets:', err)
      // Even on error, mark as loaded so we don't show loading forever
      setBetsLoaded(true)
    } finally {
      setLoadingBets(false)
    }
  }

  const loadFriends = async (userId: number) => {
    const { data: friendsData } = await supabase
      .from('friends')
      .select(`friend_id, friended_at, friend:users!friends_friend_id_fkey(username)`)
      .eq('user_id', userId)

    const { data: sentData } = await supabase
      .from('friend_requests')
      .select(`request_id, sender_id, receiver_id, status, requested_at, receiver:users!friend_requests_receiver_id_fkey(username)`)
      .eq('sender_id', userId)
      .eq('status', 'PENDING')

    const { data: incomingData } = await supabase
      .from('friend_requests')
      .select(`request_id, sender_id, receiver_id, status, requested_at, sender:users!friend_requests_sender_id_fkey(username)`)
      .eq('receiver_id', userId)
      .eq('status', 'PENDING')

    setFriends((friendsData || []) as unknown as Friend[])
    setSentRequests((sentData || []) as unknown as FriendRequest[])
    setIncomingRequests((incomingData || []) as unknown as FriendRequest[])
  }

  const searchForUsers = async () => {
    if (!searchQuery.trim() || !user) return

    const friendIds = friends.map(f => f.friend_id)
    const sentIds = sentRequests.map(r => r.receiver_id)
    const incomingIds = incomingRequests.map(r => r.sender_id)
    const excludeIds = [...friendIds, ...sentIds, ...incomingIds, user.user_id]

    const { data } = await supabase
      .from('users')
      .select('user_id, username')
      .ilike('username', `%${searchQuery}%`)
      .not('user_id', 'in', `(${excludeIds.join(',')})`)
      .limit(10)

    setSearchUsers(data || [])
  }

  const sendFriendRequest = async () => {
    if (!selectedUser || !user) return

    setSendingRequest(true)
    const { error } = await supabase
      .from('friend_requests')
      .insert({ sender_id: user.user_id, receiver_id: selectedUser.user_id, status: 'PENDING' })

    if (!error) {
      setSearchQuery('')
      setSelectedUser(null)
      setSearchUsers([])
      loadFriends(user.user_id)
    }
    setSendingRequest(false)
  }

  const acceptFriendRequest = async (requestId: number, senderId: number) => {
    if (!user) return

    await supabase
      .from('friend_requests')
      .update({ status: 'ACCEPTED', responded_at: new Date().toISOString() })
      .eq('request_id', requestId)

    await supabase
      .from('friends')
      .insert([
        { user_id: user.user_id, friend_id: senderId },
        { user_id: senderId, friend_id: user.user_id }
      ])

    loadFriends(user.user_id)
  }

  const rejectFriendRequest = async (requestId: number) => {
    if (!user) return

    await supabase
      .from('friend_requests')
      .update({ status: 'REJECTED', responded_at: new Date().toISOString() })
      .eq('request_id', requestId)

    loadFriends(user.user_id)
  }

  const getUserRole = (bet: Bet) => {
    if (!user) return ''
    if (bet.proposer_id === user.user_id) return 'Proposer'
    if (bet.acceptor_id === user.user_id) return 'Acceptor'
    if (bet.arbiter_id === user.user_id) return 'Arbiter'
    return ''
  }

  const getOpponentName = (bet: Bet) => {
    if (!user) return ''
    if (bet.proposer_id === user.user_id && bet.acceptor) return bet.acceptor.username
    if (bet.acceptor_id === user.user_id) return bet.proposer.username
    return 'N/A'
  }

  const getOpponentId = (bet: Bet) => {
    if (!user) return null
    if (bet.proposer_id === user.user_id) return bet.acceptor_id
    if (bet.acceptor_id === user.user_id) return bet.proposer_id
    return null
  }

  const getBetOutcome = (bet: Bet) => {
    if (!user || bet.status !== 'RESOLVED') return bet.status
    if (bet.outcome === 'VOID') return 'VOID'
    
    // Only calculate win/loss if user is proposer or acceptor (not arbiter)
    const isProposer = bet.proposer_id === user.user_id
    const isAcceptor = bet.acceptor_id === user.user_id
    
    // If user is only arbiter, return status (arbiters don't win/lose)
    if (!isProposer && !isAcceptor) {
      return bet.status
    }
    
    const isWinner = (bet.outcome === 'PROPOSER_WIN' && isProposer) ||
                     (bet.outcome === 'ACCEPTOR_WIN' && isAcceptor)
    
    return isWinner ? 'WON' : 'LOST'
  }

  if (!user) {
    return <div className="min-h-screen flex items-center justify-center">Loading...</div>
  }

  return (
    <div className="min-h-screen p-8" style={{backgroundColor: 'transparent'}}>
      <div className="max-w-6xl mx-auto">
        {/* Header */}
        <div className="mb-6 flex justify-between items-center">
          <div>
            <h1 className="text-3xl font-bold text-white">{user.username}</h1>
            <p className="text-lg text-white mt-1">
              {loadingBets || !betsLoaded ? (
                <span className="text-gray-300">Loading...</span>
              ) : (
                `${wins} Wins - ${losses} Losses`
              )}
            </p>
          </div>
          <Button variant="outline" onClick={() => router.push('/dashboard')}>
            Back to Dashboard
          </Button>
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
                          <p>Role: <span className="font-medium">{getUserRole(bet)}</span></p>
                          <p>
                            vs{' '}
                            {getOpponentId(bet) ? (
                              <button
                                onClick={() => router.push(`/profile/${getOpponentId(bet)}`)}
                                className="text-blue-600 hover:underline font-medium"
                              >
                                @{getOpponentName(bet)}
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
                          <p>Role: <span className="font-medium">{getUserRole(bet)}</span></p>
                          <p>
                            vs{' '}
                            {getOpponentId(bet) ? (
                              <button
                                onClick={() => router.push(`/profile/${getOpponentId(bet)}`)}
                                className="text-blue-600 hover:underline font-medium"
                              >
                                @{getOpponentName(bet)}
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
                        getBetOutcome(bet) === 'WON' ? 'bg-green-100 text-green-800' :
                        getBetOutcome(bet) === 'LOST' ? 'bg-red-100 text-red-800' :
                        'bg-gray-100 text-gray-800'
                      }`}>
                        {getBetOutcome(bet)}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Friends Section */}
        <Card>
          <CardHeader>
            <CardTitle>Friends</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 gap-6">
              {/* Left: Search Users */}
              <div className="space-y-4">
                <Input
                  type="text"
                  placeholder="Search users..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                />
                
                {searchUsers.length > 0 && (
                  <div className="border rounded-md max-h-40 overflow-y-auto">
                    {searchUsers.map((searchUser) => (
                      <div
                        key={searchUser.user_id}
                        onClick={() => setSelectedUser(searchUser)}
                        className={`p-2 cursor-pointer hover:bg-gray-50 ${
                          selectedUser?.user_id === searchUser.user_id ? 'bg-blue-50' : ''
                        }`}
                      >
                        {searchUser.username}
                      </div>
                    ))}
                  </div>
                )}

                {selectedUser && (
                  <div className="p-3 bg-blue-50 rounded-md space-y-2">
                    <p className="text-sm">Selected: <strong>{selectedUser.username}</strong></p>
                    <Button
                      onClick={sendFriendRequest}
                      disabled={sendingRequest}
                      className="w-full"
                      size="sm"
                    >
                      {sendingRequest ? 'Sending...' : 'Send Friend Request'}
                    </Button>
                  </div>
                )}
              </div>

              {/* Right: Friends List */}
              <div className="space-y-2">
                <div className="max-h-64 overflow-y-auto space-y-2">
                  {/* Incoming Requests */}
                  {incomingRequests.map((request) => (
                    <div key={request.request_id} className="p-2 bg-orange-50 rounded-md flex items-center justify-between">
                      <span className="text-sm font-medium">{request.sender.username}</span>
                      <div className="flex gap-1">
                        <Button
                          size="sm"
                          className="bg-green-600 hover:bg-green-700 h-7 text-xs"
                          onClick={() => acceptFriendRequest(request.request_id, request.sender_id)}
                        >
                          Accept
                        </Button>
                        <Button
                          size="sm"
                          className="bg-red-600 hover:bg-red-700 text-white h-7 text-xs"
                          onClick={() => rejectFriendRequest(request.request_id)}
                        >
                          Reject
                        </Button>
                      </div>
                    </div>
                  ))}

                  {/* Sent Requests */}
                  {sentRequests.map((request) => (
                    <div key={request.request_id} className="p-2 bg-yellow-50 rounded-md flex items-center justify-between">
                      <span className="text-sm font-medium">{request.receiver.username}</span>
                      <span className="text-xs bg-yellow-200 text-yellow-800 px-2 py-1 rounded">Pending</span>
                    </div>
                  ))}

                  {/* Current Friends */}
                  {friends.map((friend) => (
                    <div key={friend.friend_id} className="p-2 bg-white rounded-md border">
                      <button
                        onClick={() => router.push(`/profile/${friend.friend_id}`)}
                        className="text-sm font-medium text-blue-600 hover:underline"
                      >
                        {friend.friend.username}
                      </button>
                    </div>
                  ))}

                  {friends.length === 0 && sentRequests.length === 0 && incomingRequests.length === 0 && (
                    <p className="text-center text-gray-500 text-sm py-4">No friends yet</p>
                  )}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Admin Unlock Section */}
        {!isAdmin && (
          <Card className="mt-6">
            <CardHeader>
              <CardTitle>🔐 Admin Access</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                <p className="text-sm text-gray-600">
                  Enter the admin password to unlock administrative privileges
                </p>
                <div className="flex gap-2">
                  <Input
                    type="password"
                    placeholder="Enter Admin Password"
                    value={adminPassword}
                    onChange={(e) => setAdminPassword(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        handleAdminUnlock()
                      }
                    }}
                  />
                  <Button
                    onClick={handleAdminUnlock}
                    disabled={unlockingAdmin || !adminPassword}
                  >
                    {unlockingAdmin ? 'Unlocking...' : 'Unlock'}
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Admin Badge */}
        {isAdmin && (
          <Card className="mt-6 bg-gradient-to-r from-purple-50 to-pink-50 border-purple-200">
            <CardContent className="py-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <span className="text-3xl">👑</span>
                  <div>
                    <p className="font-bold text-purple-900">Admin Access Enabled</p>
                    <p className="text-sm text-purple-700">You have administrative privileges</p>
                  </div>
                </div>
                <Button
                  variant="outline"
                  onClick={() => router.push('/admin')}
                  className="bg-purple-100 hover:bg-purple-200 border-purple-300"
                >
                  Admin Dashboard →
                </Button>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  )
}

