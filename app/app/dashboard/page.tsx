'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { supabase } from '@/lib/supabase'
import { setAuthContext } from '@/lib/auth'

interface User {
  id: number
  username: string
  balance: number
  is_admin?: boolean
}

interface SearchUser {
  user_id: number
  username: string
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

interface Friend {
  user_id: number
  friend_id: number
  friended_at: string
  friend: { username: string }
}

export default function DashboardPage() {
  const [user, setUser] = useState<User | null>(null)
  const router = useRouter()
  
  // Friends state
  const [searchQuery, setSearchQuery] = useState('')
  const [searchUsers, setSearchUsers] = useState<SearchUser[]>([])
  const [selectedUser, setSelectedUser] = useState<SearchUser | null>(null)
  const [sendingRequest, setSendingRequest] = useState(false)
  const [loadingFriends, setLoadingFriends] = useState(false)
  const [friends, setFriends] = useState<Friend[]>([])
  const [sentRequests, setSentRequests] = useState<FriendRequest[]>([])
  const [incomingRequests, setIncomingRequests] = useState<FriendRequest[]>([])
  
  // Support ticket state
  const [supportOpen, setSupportOpen] = useState(false)
  const [supportMessage, setSupportMessage] = useState('')
  const [sendingSupport, setSendingSupport] = useState(false)
  const [myTickets, setMyTickets] = useState<any[]>([])
  const [selectedTicket, setSelectedTicket] = useState<any | null>(null)
  const [ticketMessages, setTicketMessages] = useState<any[]>([])
  const [newTicketMessage, setNewTicketMessage] = useState('')
  const [ticketDialogOpen, setTicketDialogOpen] = useState(false)
  const [sendingTicketMessage, setSendingTicketMessage] = useState(false)
  const [loadingTickets, setLoadingTickets] = useState(false)

  useEffect(() => {
    loadUser()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (searchQuery.trim() && user) {
      searchForUsers()
    } else {
      setSearchUsers([])
      setSelectedUser(null)
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchQuery])

  const loadUser = async () => {
    // Check if user is logged in (for MVP demo)
    const userData = localStorage.getItem('user')
    if (!userData) {
      router.push('/login')
      return
    }
    
    const parsedUser = JSON.parse(userData)
    
    // Set auth context for RLS
    await setAuthContext(parsedUser.id, parsedUser.is_admin || false)
    
    // Fetch fresh balance from users table
    const { data: userBalance } = await supabase
      .from('users')
      .select('wallet_balance')
      .eq('user_id', parsedUser.id)
      .single()

    const balance = userBalance ? userBalance.wallet_balance : 0

    // Update localStorage with fresh balance
    const updatedUser = {
      ...parsedUser,
      balance: balance,
      wallet_balance: balance
    }
    localStorage.setItem('user', JSON.stringify(updatedUser))
    
    setUser(updatedUser)
    
    // Load friends data immediately after setting user and auth context
    await loadFriendsData(parsedUser.id)
    
    // Load user's support tickets
    await loadMyTickets(parsedUser.id)
  }
  
  const loadMyTickets = async (userId: number) => {
    setLoadingTickets(true)
    try {
      await setAuthContext(userId, false)
      
      const { data, error } = await supabase
        .from('support_tickets')
        .select('ticket_id, subject, status, priority, created_at, updated_at')
        .eq('user_id', userId)
        .order('updated_at', { ascending: false })
      
      if (error) {
        console.error('Error loading tickets:', error)
      } else {
        setMyTickets(data || [])
      }
    } catch (err) {
      console.error('Error loading tickets:', err)
    } finally {
      setLoadingTickets(false)
    }
  }
  
  const openTicket = async (ticket: any) => {
    setSelectedTicket(ticket)
    setTicketDialogOpen(true)
    
    if (!user) return
    
    await setAuthContext(user.id, user.is_admin || false)
    
    // Load messages for this ticket
    const { data, error } = await supabase
      .from('ticket_messages')
      .select(`
        message_id,
        author_id,
        message,
        is_internal,
        created_at,
        author:users!ticket_messages_author_id_fkey(username, is_admin)
      `)
      .eq('ticket_id', ticket.ticket_id)
      .order('created_at', { ascending: true })
    
    if (error) {
      console.error('Error loading messages:', error)
    } else {
      // Transform the data
      const transformedMessages = (data || []).map((msg: any) => ({
        ...msg,
        author: Array.isArray(msg.author) ? msg.author[0] : msg.author
      }))
      setTicketMessages(transformedMessages)
    }
  }
  
  const sendTicketMessage = async () => {
    if (!newTicketMessage.trim() || !selectedTicket || !user) return
    
    setSendingTicketMessage(true)
    try {
      await setAuthContext(user.id, user.is_admin || false)
      
      const { error } = await supabase
        .from('ticket_messages')
        .insert({
          ticket_id: selectedTicket.ticket_id,
          author_id: user.id,
          message: newTicketMessage.trim(),
          is_internal: false
        })
      
      if (error) {
        console.error('Error sending message:', error)
        alert('Failed to send message: ' + error.message)
        return
      }
      
      // Update ticket updated_at
      await supabase
        .from('support_tickets')
        .update({ updated_at: new Date().toISOString() })
        .eq('ticket_id', selectedTicket.ticket_id)
      
      setNewTicketMessage('')
      // Reload messages
      await openTicket(selectedTicket)
      // Reload ticket list
      await loadMyTickets(user.id)
    } catch (err) {
      console.error('Error sending message:', err)
      alert('An error occurred')
    } finally {
      setSendingTicketMessage(false)
    }
  }

  const loadFriendsData = async (userId: number) => {
    setLoadingFriends(true)
    try {
      // Re-establish auth context
      await setAuthContext(userId, false)

      // Load friends - query both directions since friendship is bidirectional
      const { data: friendsData1, error: friendsError1 } = await supabase
        .from('friends')
        .select(`friend_id, friended_at`)
        .eq('user_id', userId)

      const { data: friendsData2, error: friendsError2 } = await supabase
        .from('friends')
        .select(`user_id, friended_at`)
        .eq('friend_id', userId)

      // Get all friend IDs
      const friendIds = new Set<number>()
      if (friendsData1) {
        friendsData1.forEach((f: any) => friendIds.add(f.friend_id))
      }
      if (friendsData2) {
        friendsData2.forEach((f: any) => friendIds.add(f.user_id))
      }

      // Fetch friend usernames
      const allFriendsMap = new Map<number, Friend>() // Use Map to deduplicate by friend_id
      if (friendIds.size > 0) {
        const { data: friendUsers, error: friendUsersError } = await supabase
          .from('users')
          .select('user_id, username')
          .in('user_id', Array.from(friendIds))

        if (friendUsersError) {
          console.error('Error loading friend usernames:', friendUsersError)
        } else if (friendUsers) {
          // Create a map for quick lookup
          const userMap = new Map(friendUsers.map(u => [u.user_id, u.username]))
          
          // Build friends list with usernames, deduplicating by friend_id
          if (friendsData1) {
            friendsData1.forEach((f: any) => {
              const username = userMap.get(f.friend_id)
              if (username && !allFriendsMap.has(f.friend_id)) {
                allFriendsMap.set(f.friend_id, {
                  user_id: userId,
                  friend_id: f.friend_id,
                  friended_at: f.friended_at,
                  friend: { username }
                })
              }
            })
          }
          if (friendsData2) {
            friendsData2.forEach((f: any) => {
              const username = userMap.get(f.user_id)
              if (username && !allFriendsMap.has(f.user_id)) {
                allFriendsMap.set(f.user_id, {
                  user_id: userId,
                  friend_id: f.user_id,
                  friended_at: f.friended_at,
                  friend: { username }
                })
              }
            })
          }
        }
      }
      
      // Convert map to array (already deduplicated)
      const allFriends = Array.from(allFriendsMap.values())

      // Load sent requests
      const { data: sentData, error: sentError } = await supabase
        .from('friend_requests')
        .select(`request_id, sender_id, receiver_id, status, requested_at`)
        .eq('sender_id', userId)
        .eq('status', 'PENDING')

      // Load incoming requests
      const { data: incomingData, error: incomingError } = await supabase
        .from('friend_requests')
        .select(`request_id, sender_id, receiver_id, status, requested_at`)
        .eq('receiver_id', userId)
        .eq('status', 'PENDING')

      if (friendsError1) console.error('Error loading friends (direction 1):', friendsError1)
      if (friendsError2) console.error('Error loading friends (direction 2):', friendsError2)
      if (sentError) console.error('Error loading sent requests:', sentError)
      if (incomingError) console.error('Error loading incoming requests:', incomingError)

      // Get usernames for sent and incoming requests
      const receiverIds = new Set((sentData || []).map((r: any) => r.receiver_id))
      const senderIds = new Set((incomingData || []).map((r: any) => r.sender_id))
      
      const allRequestUserIds = [...receiverIds, ...senderIds]
      const userMap = new Map<string, number>()
      
      if (allRequestUserIds.length > 0) {
        const { data: requestUsers, error: requestUsersError } = await supabase
          .from('users')
          .select('user_id, username')
          .in('user_id', allRequestUserIds)

        if (requestUsersError) {
          console.error('Error loading request usernames:', requestUsersError)
        } else if (requestUsers) {
          requestUsers.forEach(u => userMap.set(u.user_id.toString(), u.username))
        }
      }

      // Transform sent requests
      const transformedSent: FriendRequest[] = (sentData || []).map((r: any) => ({
        request_id: r.request_id,
        sender_id: r.sender_id,
        receiver_id: r.receiver_id,
        status: r.status,
        requested_at: r.requested_at,
        sender: { username: '' },
        receiver: { username: userMap.get(r.receiver_id.toString()) || 'Unknown' }
      }))

      // Transform incoming requests
      const transformedIncoming: FriendRequest[] = (incomingData || []).map((r: any) => ({
        request_id: r.request_id,
        sender_id: r.sender_id,
        receiver_id: r.receiver_id,
        status: r.status,
        requested_at: r.requested_at,
        sender: { username: userMap.get(r.sender_id.toString()) || 'Unknown' },
        receiver: { username: '' }
      }))

      setFriends(allFriends)
      setSentRequests(transformedSent)
      setIncomingRequests(transformedIncoming)
    } catch (err) {
      console.error('Error loading friends:', err)
    } finally {
      setLoadingFriends(false)
    }
  }

  const searchForUsers = async () => {
    if (!searchQuery.trim() || !user) return

    try {
      // Re-establish auth context
      await setAuthContext(user.id, false)

      const friendIds = friends.map(f => f.friend_id)
      const sentIds = sentRequests.map(r => r.receiver_id)
      const incomingIds = incomingRequests.map(r => r.sender_id)
      const excludeIds = [...new Set([...friendIds, ...sentIds, ...incomingIds, user.id])] // Remove duplicates

      let query = supabase
        .from('users')
        .select('user_id, username')
        .ilike('username', `%${searchQuery}%`)
        .limit(10)

      // Exclude users who are already friends or have pending requests
      if (excludeIds.length > 0) {
        query = query.not('user_id', 'in', `(${excludeIds.join(',')})`)
      }

      const { data, error } = await query

      if (error) {
        console.error('Error searching users:', error)
        return
      }

      setSearchUsers(data || [])
    } catch (err) {
      console.error('Error searching users:', err)
    }
  }

  const sendFriendRequest = async () => {
    if (!selectedUser || !user) return

    setSendingRequest(true)
    try {
      // Re-establish auth context
      await setAuthContext(user.id, false)

      // Check if already friends
      const { data: existingFriend } = await supabase
        .from('friends')
        .select('user_id')
        .or(`and(user_id.eq.${user.id},friend_id.eq.${selectedUser.user_id}),and(user_id.eq.${selectedUser.user_id},friend_id.eq.${user.id})`)
        .limit(1)

      if (existingFriend && existingFriend.length > 0) {
        alert('You are already friends with this user!')
        setSendingRequest(false)
        return
      }

      // Check if there's already a pending request
      const { data: existingRequest } = await supabase
        .from('friend_requests')
        .select('request_id, status')
        .or(`and(sender_id.eq.${user.id},receiver_id.eq.${selectedUser.user_id}),and(sender_id.eq.${selectedUser.user_id},receiver_id.eq.${user.id})`)
        .eq('status', 'PENDING')
        .limit(1)

      if (existingRequest && existingRequest.length > 0) {
        alert('A friend request already exists between you and this user!')
        setSendingRequest(false)
        return
      }

      const { error } = await supabase
        .from('friend_requests')
        .insert({ sender_id: user.id, receiver_id: selectedUser.user_id, status: 'PENDING' })

      if (error) {
        console.error('Error sending friend request:', error)
        if (error.code === '23505') { // Unique constraint violation
          alert('A friend request already exists between you and this user!')
        } else {
          alert('Failed to send friend request: ' + error.message)
        }
        return
      }

      alert('Friend request sent!')
      setSearchQuery('')
      setSelectedUser(null)
      setSearchUsers([])
      await loadFriendsData(user.id)
    } catch (err) {
      console.error('Error:', err)
      alert('An error occurred while sending the friend request')
    } finally {
      setSendingRequest(false)
    }
  }

  const acceptFriendRequest = async (requestId: number, senderId: number) => {
    if (!user) return

    try {
      // Re-establish auth context
      await setAuthContext(user.id, false)

      // Check if already friends (prevent duplicate)
      const { data: existingFriend } = await supabase
        .from('friends')
        .select('user_id')
        .or(`and(user_id.eq.${user.id},friend_id.eq.${senderId}),and(user_id.eq.${senderId},friend_id.eq.${user.id})`)
        .limit(1)

      if (existingFriend && existingFriend.length > 0) {
        // Already friends, just update the request status
        await supabase
          .from('friend_requests')
          .update({ status: 'ACCEPTED', responded_at: new Date().toISOString() })
          .eq('request_id', requestId)
        
        alert('You are already friends with this user!')
        await loadFriendsData(user.id)
        return
      }

      // Update request status
      const { error: updateError } = await supabase
        .from('friend_requests')
        .update({ status: 'ACCEPTED', responded_at: new Date().toISOString() })
        .eq('request_id', requestId)

      if (updateError) {
        console.error('Error updating request:', updateError)
        alert('Failed to accept friend request: ' + updateError.message)
        return
      }

      // Create bidirectional friendship
      const { error: insertError } = await supabase
        .from('friends')
        .insert([
          { user_id: user.id, friend_id: senderId },
          { user_id: senderId, friend_id: user.id }
        ])

      if (insertError) {
        console.error('Error creating friendship:', insertError)
        if (insertError.code === '23505') { // Unique constraint violation
          alert('Friendship already exists!')
        } else {
          alert('Failed to create friendship: ' + insertError.message)
        }
        return
      }

      alert('Friend request accepted!')
      await loadFriendsData(user.id)
    } catch (err) {
      console.error('Error:', err)
      alert('An error occurred while accepting the friend request')
    }
  }

  const rejectFriendRequest = async (requestId: number) => {
    if (!user) return

    try {
      // Re-establish auth context
      await setAuthContext(user.id, false)

      const { error } = await supabase
        .from('friend_requests')
        .update({ status: 'REJECTED', responded_at: new Date().toISOString() })
        .eq('request_id', requestId)

      if (error) {
        console.error('Error rejecting request:', error)
        alert('Failed to reject friend request: ' + error.message)
        return
      }

      await loadFriendsData(user.id)
    } catch (err) {
      console.error('Error:', err)
      alert('An error occurred while rejecting the friend request')
    }
  }

  const sendSupportMessage = async () => {
    if (!supportMessage.trim() || !user) return

    setSendingSupport(true)
    try {
      // Re-establish auth context before insert operations
      await setAuthContext(user.id, user.is_admin || false)
      
      // Create a support ticket
      const { data: ticket, error: ticketError } = await supabase
        .from('support_tickets')
        .insert({
          user_id: user.id,
          subject: 'Support Request',
          status: 'OPEN',
          priority: 'NORMAL'
        })
        .select()
        .single()

      if (ticketError) {
        console.error('Ticket error:', ticketError)
        alert('Failed to create support ticket: ' + ticketError.message)
        setSendingSupport(false)
        return
      }

      // Add the initial message
      const { error: messageError } = await supabase
        .from('ticket_messages')
        .insert({
          ticket_id: ticket.ticket_id,
          author_id: user.id,
          message: supportMessage,
          is_internal: false
        })

      if (messageError) {
        console.error('Message error:', messageError)
        alert('Failed to send message: ' + messageError.message)
        setSendingSupport(false)
        return
      }

      alert('Support ticket submitted! An admin will respond soon.')
      setSupportMessage('')
      setSupportOpen(false)
      
      // Reload tickets to show the new one
      if (user) {
        await loadMyTickets(user.id)
      }
    } catch (err) {
      console.error('Error:', err)
      alert('An error occurred')
    } finally {
      setSendingSupport(false)
    }
  }

  if (!user) {
    return <div className="min-h-screen flex items-center justify-center text-white">Loading...</div>
  }

  return (
    <div className="min-h-screen p-8" style={{backgroundColor: 'transparent'}}>
      <div className="max-w-6xl mx-auto">
        <div className="mb-8 flex justify-between items-center text-white">
          <h1 className="text-3xl font-bold">8Ball Markets</h1>
          <div className="flex gap-3 items-center">
            <Button 
              variant="outline" 
              size="icon"
              onClick={() => router.push('/profile')}
              className="rounded-full w-10 h-10"
              title="View Profile"
            >
              <span className="text-xl">👤</span>
            </Button>
            <Button onClick={() => {
              localStorage.removeItem('user')
              router.push('/login')
            }}>
              Logout
            </Button>
          </div>
        </div>

        <div className="grid gap-6">
          {/* Welcome Card */}
          <Card>
            <CardHeader>
              <CardTitle>Welcome, {user.username}!</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-2xl font-semibold">Wallet Balance: ${user.balance.toFixed(2)}</p>
            </CardContent>
          </Card>

          {/* Bets */}
          <Card>
            <CardHeader>
              <CardTitle>Bets</CardTitle>
            </CardHeader>
            <CardContent className="flex gap-4 flex-wrap">
              <Button variant="outline" onClick={() => router.push('/bets/create')}>
                Create Bet
              </Button>
              <Button variant="outline" onClick={() => router.push('/bets/marketplace')}>
                Marketplace
              </Button>
              <Button variant="outline" onClick={() => router.push('/bets/my-bets')}>
                My Bets
              </Button>
              <Button variant="outline" onClick={() => router.push('/arbiter')} className="bg-purple-50">
                ⚖️ Arbiter Dashboard
              </Button>
              <Button variant="outline" onClick={() => router.push('/leaderboard')} className="bg-yellow-50">
                🏆 Leaderboard
              </Button>
            </CardContent>
          </Card>

          {/* Friends List */}
          <Card>
            <CardHeader>
              <div className="flex justify-between items-center">
                <CardTitle>Friends List</CardTitle>
                <Button 
                  variant="outline" 
                  size="sm"
                  onClick={() => user && loadFriendsData(user.id)}
                  disabled={loadingFriends}
                >
                  {loadingFriends ? 'Refreshing...' : 'Refresh'}
                </Button>
              </div>
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
                  {loadingFriends ? (
                    <div className="p-4 text-center text-gray-500">
                      <p>Loading friends...</p>
                    </div>
                  ) : (
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
                      <div key={`friend-${friend.friend_id}`} className="p-2 bg-white rounded-md border">
                        <span className="text-sm font-medium">{friend.friend.username}</span>
                      </div>
                    ))}

                      {friends.length === 0 && sentRequests.length === 0 && incomingRequests.length === 0 && (
                        <p className="text-center text-gray-500 text-sm py-4">No friends yet</p>
                      )}
                    </div>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Customer Support */}
          <Card>
            <CardHeader>
              <div className="flex justify-between items-center">
                <CardTitle>Customer Support</CardTitle>
                <Button 
                  variant="outline" 
                  size="sm"
                  onClick={() => user && loadMyTickets(user.id)}
                  disabled={loadingTickets}
                >
                  {loadingTickets ? 'Loading...' : 'Refresh'}
                </Button>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <Button variant="outline" onClick={() => setSupportOpen(true)}>
                Create New Ticket
              </Button>
              
              {/* My Tickets List */}
              <div className="mt-4">
                <h3 className="text-sm font-semibold mb-2">My Tickets ({myTickets.length})</h3>
                {loadingTickets ? (
                  <p className="text-sm text-gray-500">Loading tickets...</p>
                ) : myTickets.length === 0 ? (
                  <p className="text-sm text-gray-500">No support tickets yet</p>
                ) : (
                  <div className="space-y-2 max-h-64 overflow-y-auto">
                    {myTickets.map((ticket) => (
                      <div
                        key={ticket.ticket_id}
                        onClick={() => openTicket(ticket)}
                        className="p-3 border rounded-lg hover:bg-gray-50 cursor-pointer transition"
                      >
                        <div className="flex justify-between items-start">
                          <div className="flex-1">
                            <p className="font-medium text-sm">{ticket.subject}</p>
                            <p className="text-xs text-gray-500 mt-1">
                              {new Date(ticket.updated_at).toLocaleDateString()}
                            </p>
                          </div>
                          <div className="flex gap-2">
                            <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                              ticket.status === 'OPEN' ? 'bg-green-100 text-green-800' :
                              ticket.status === 'IN_PROGRESS' ? 'bg-blue-100 text-blue-800' :
                              ticket.status === 'RESOLVED' ? 'bg-gray-100 text-gray-800' :
                              'bg-red-100 text-red-800'
                            }`}>
                              {ticket.status}
                            </span>
                            <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                              ticket.priority === 'URGENT' ? 'bg-red-100 text-red-800' :
                              ticket.priority === 'HIGH' ? 'bg-orange-100 text-orange-800' :
                              'bg-gray-100 text-gray-600'
                            }`}>
                              {ticket.priority}
                            </span>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Support Ticket Dialog */}
        <Dialog open={supportOpen} onOpenChange={setSupportOpen}>
          <DialogContent className="max-w-2xl w-[90vw] h-[85vh] flex flex-col bg-white rounded-3xl shadow-2xl p-0 gap-0">
            <DialogHeader className="px-6 py-4 border-b bg-gradient-to-r from-blue-50 to-purple-50 rounded-t-3xl">
              <DialogTitle className="flex items-center justify-between">
                <div>
                  <div className="font-bold text-lg text-gray-800">
                    Customer Support
                  </div>
                  <div className="text-sm text-gray-500 font-normal mt-1">
                    💬 Chat with Customer Support Specialist
                  </div>
                </div>
              </DialogTitle>
            </DialogHeader>

            {/* Messages Container - White background */}
            <div className="flex-1 overflow-y-auto space-y-3 py-6 px-6 bg-white">
              <div className="text-center py-8">
                <div className="mb-4">
                  <div className="inline-block p-4 bg-blue-50 rounded-full mb-3">
                    <span className="text-3xl">🎧</span>
                  </div>
                  <h3 className="font-semibold text-lg mb-2">Need Help?</h3>
                  <p className="text-gray-600 text-sm max-w-md mx-auto">
                    Describe your issue below and our Customer Support Specialist will respond as soon as possible.
                  </p>
                </div>
              </div>
            </div>

            {/* Message Input - White background */}
            <div className="border-t bg-white px-6 py-4 rounded-b-3xl flex flex-col gap-3">
              <Textarea
                placeholder="Describe your issue or question..."
                value={supportMessage}
                onChange={(e) => setSupportMessage(e.target.value)}
                className="flex-1 resize-none bg-gray-50 border-gray-200 rounded-xl min-h-[100px]"
                rows={4}
              />
              <Button
                onClick={sendSupportMessage}
                disabled={sendingSupport || !supportMessage.trim()}
                className="w-full rounded-xl"
              >
                {sendingSupport ? 'Submitting...' : 'Submit Ticket'}
              </Button>
            </div>
          </DialogContent>
        </Dialog>

        {/* Ticket View Dialog */}
        <Dialog open={ticketDialogOpen} onOpenChange={setTicketDialogOpen}>
          <DialogContent className="max-w-3xl w-[90vw] h-[85vh] flex flex-col bg-white rounded-3xl shadow-2xl p-0 gap-0">
            <DialogHeader className="px-6 py-4 border-b bg-gradient-to-r from-blue-50 to-purple-50 rounded-t-3xl">
              <DialogTitle className="flex items-center justify-between">
                <div>
                  <div className="font-bold text-lg text-gray-800">
                    {selectedTicket?.subject}
                  </div>
                  <div className="text-sm text-gray-500 font-normal mt-1">
                    Ticket #{selectedTicket?.ticket_id} • {selectedTicket?.status}
                  </div>
                </div>
              </DialogTitle>
            </DialogHeader>

            {/* Messages Container */}
            <div className="flex-1 overflow-y-auto space-y-3 py-6 px-6 bg-white">
              {ticketMessages.length === 0 ? (
                <div className="text-center text-gray-400 py-12">
                  💬 No messages yet. Waiting for admin response...
                </div>
              ) : (
                ticketMessages.map((message) => {
                  const isOwnMessage = message.author_id === user?.id
                  const isAdmin = message.author?.is_admin
                  return (
                    <div
                      key={message.message_id}
                      className={`flex ${isOwnMessage ? 'justify-end' : 'justify-start'}`}
                    >
                      <div
                        className={`max-w-[70%] rounded-2xl px-4 py-3 shadow-sm ${
                          isOwnMessage
                            ? 'bg-blue-500 text-white rounded-br-sm'
                            : isAdmin
                            ? 'bg-purple-100 text-gray-900 rounded-bl-sm border border-purple-200'
                            : 'bg-gray-100 text-gray-900 rounded-bl-sm'
                        }`}
                      >
                        <div className="text-xs font-semibold mb-1 opacity-80">
                          {message.author?.username}
                          {isAdmin && ' 👑 (Admin)'}
                        </div>
                        <div className="whitespace-pre-wrap text-sm">
                          {message.message}
                        </div>
                        <div
                          className={`text-xs mt-1 opacity-70 ${
                            isOwnMessage ? 'text-blue-50' : 'text-gray-500'
                          }`}
                        >
                          {new Date(message.created_at).toLocaleTimeString([], {
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </div>
                      </div>
                    </div>
                  )
                })
              )}
            </div>

            {/* Message Input */}
            <div className="border-t bg-white px-6 py-4 rounded-b-3xl flex gap-3">
              <Textarea
                placeholder="Type your message..."
                value={newTicketMessage}
                onChange={(e) => setNewTicketMessage(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault()
                    sendTicketMessage()
                  }
                }}
                className="flex-1 resize-none bg-gray-50 border-gray-200 rounded-xl"
                rows={2}
              />
              <Button
                onClick={sendTicketMessage}
                disabled={sendingTicketMessage || !newTicketMessage.trim()}
                className="self-end px-6 rounded-xl"
              >
                Send
              </Button>
            </div>
          </DialogContent>
        </Dialog>
      </div>
    </div>
  )
}

