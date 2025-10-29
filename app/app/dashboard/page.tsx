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

interface User {
  id: number
  username: string
  balance: number
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
  const [friends, setFriends] = useState<Friend[]>([])
  const [sentRequests, setSentRequests] = useState<FriendRequest[]>([])
  const [incomingRequests, setIncomingRequests] = useState<FriendRequest[]>([])
  
  // Support ticket state
  const [supportOpen, setSupportOpen] = useState(false)
  const [supportMessage, setSupportMessage] = useState('')
  const [sendingSupport, setSendingSupport] = useState(false)

  useEffect(() => {
    loadUser()
  }, [router])
  
  useEffect(() => {
    if (user) {
      loadFriendsData(user.id)
    }
  }, [user])

  useEffect(() => {
    if (searchQuery.trim() && user) {
      searchForUsers()
    } else {
      setSearchUsers([])
      setSelectedUser(null)
    }
  }, [searchQuery, user])

  const loadUser = async () => {
    // Check if user is logged in (for MVP demo)
    const userData = localStorage.getItem('user')
    if (!userData) {
      router.push('/login')
      return
    }
    
    const parsedUser = JSON.parse(userData)
    
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
  }

  const loadFriendsData = async (userId: number) => {
    try {
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
    } catch (err) {
      console.error('Error loading friends:', err)
    }
  }

  const searchForUsers = async () => {
    if (!searchQuery.trim() || !user) return

    try {
      const friendIds = friends.map(f => f.friend_id)
      const sentIds = sentRequests.map(r => r.receiver_id)
      const incomingIds = incomingRequests.map(r => r.sender_id)
      const excludeIds = [...friendIds, ...sentIds, ...incomingIds, user.id]

      const { data } = await supabase
        .from('users')
        .select('user_id, username')
        .ilike('username', `%${searchQuery}%`)
        .not('user_id', 'in', `(${excludeIds.join(',')})`)
        .limit(10)

      setSearchUsers(data || [])
    } catch (err) {
      console.error('Error searching users:', err)
    }
  }

  const sendFriendRequest = async () => {
    if (!selectedUser || !user) return

    setSendingRequest(true)
    try {
      const { error } = await supabase
        .from('friend_requests')
        .insert({ sender_id: user.id, receiver_id: selectedUser.user_id, status: 'PENDING' })

      if (error) {
        alert('Failed to send friend request')
        return
      }

      setSearchQuery('')
      setSelectedUser(null)
      setSearchUsers([])
      loadFriendsData(user.id)
    } catch (err) {
      console.error('Error:', err)
    } finally {
      setSendingRequest(false)
    }
  }

  const acceptFriendRequest = async (requestId: number, senderId: number) => {
    if (!user) return

    try {
      await supabase
        .from('friend_requests')
        .update({ status: 'ACCEPTED', responded_at: new Date().toISOString() })
        .eq('request_id', requestId)

      await supabase
        .from('friends')
        .insert([
          { user_id: user.id, friend_id: senderId },
          { user_id: senderId, friend_id: user.id }
        ])

      loadFriendsData(user.id)
    } catch (err) {
      console.error('Error:', err)
    }
  }

  const rejectFriendRequest = async (requestId: number) => {
    if (!user) return

    try {
      await supabase
        .from('friend_requests')
        .update({ status: 'REJECTED', responded_at: new Date().toISOString() })
        .eq('request_id', requestId)

      loadFriendsData(user.id)
    } catch (err) {
      console.error('Error:', err)
    }
  }

  const sendSupportMessage = async () => {
    if (!supportMessage.trim() || !user) return

    setSendingSupport(true)
    try {
      // For MVP demo, just show success message without actual backend
      // In production, this would create a ticket in the Tickets table
      alert('Support ticket submitted! We will respond as soon as possible.')
      setSupportMessage('')
      setSupportOpen(false)
    } catch (err) {
      console.error('Error:', err)
    } finally {
      setSendingSupport(false)
    }
  }

  if (!user) {
    return <div className="min-h-screen flex items-center justify-center">Loading...</div>
  }

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-6xl mx-auto">
        <div className="mb-8 flex justify-between items-center">
          <h1 className="text-3xl font-bold">8Ball Markets</h1>
          <Button onClick={() => {
            localStorage.removeItem('user')
            router.push('/login')
          }}>
            Logout
          </Button>
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
            <CardContent className="flex gap-4">
              <Button variant="outline" onClick={() => router.push('/bets/create')}>
                Create Bet
              </Button>
              <Button variant="outline" onClick={() => router.push('/bets/marketplace')}>
                Marketplace
              </Button>
              <Button variant="outline" onClick={() => router.push('/bets/my-bets')}>
                My Bets
              </Button>
            </CardContent>
          </Card>

          {/* Friends List */}
          <Card>
            <CardHeader>
              <CardTitle>Friends List</CardTitle>
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
                        <span className="text-sm font-medium">{friend.friend.username}</span>
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

          {/* Customer Support */}
          <Card>
            <CardHeader>
              <CardTitle>Customer Support</CardTitle>
            </CardHeader>
            <CardContent>
              <Button variant="outline" onClick={() => setSupportOpen(true)}>
                Create Ticket
              </Button>
            </CardContent>
          </Card>
        </div>

        {/* Support Ticket Dialog */}
        <Dialog open={supportOpen} onOpenChange={setSupportOpen}>
          <DialogContent className="max-w-2xl w-[90vw] h-[85vh] flex flex-col bg-white rounded-3xl shadow-2xl p-0 gap-0">
            <DialogHeader className="px-6 py-4 border-b bg-linear-to-r from-blue-50 to-purple-50 rounded-t-3xl">
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
      </div>
    </div>
  )
}

