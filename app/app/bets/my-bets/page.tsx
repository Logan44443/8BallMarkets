'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Textarea } from '@/components/ui/textarea'

interface Bet {
  bet_id: number
  event_description: string
  stake_proposer_cents: number
  stake_acceptor_cents: number | null
  status: string
  outcome: string | null
  created_at: string
  accepted_at: string | null
  resolved_at: string | null
  proposer_id: number
  acceptor_id: number | null
  target_user_id: number | null
  proposer: { username: string }
  acceptor: { username: string } | null
}

interface Message {
  comment_id: number
  author_id: number
  body: string
  created_at: string
  author: { username: string }
}

export default function MyBetsPage() {
  const [myBets, setMyBets] = useState<Bet[]>([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState<'all' | 'pending' | 'active' | 'resolved'>('all')
  const router = useRouter()
  const [currentUserId, setCurrentUserId] = useState<number | null>(null)
  
  // Chat dialog state
  const [selectedBet, setSelectedBet] = useState<Bet | null>(null)
  const [chatOpen, setChatOpen] = useState(false)
  const [messages, setMessages] = useState<Message[]>([])
  const [newMessage, setNewMessage] = useState('')
  const [sendingMessage, setSendingMessage] = useState(false)
  const [acceptingBet, setAcceptingBet] = useState<number | null>(null)
  const [rejectingBet, setRejectingBet] = useState<number | null>(null)

  useEffect(() => {
    loadMyBets()
  }, [filter])

  const loadMyBets = async () => {
    try {
      const userData = localStorage.getItem('user')
      if (!userData) {
        router.push('/login')
        return
      }
      
      const user = JSON.parse(userData)
      setCurrentUserId(user.id)

      // Get bets where user is proposer OR acceptor OR target (incoming direct bets)
      let query = supabase
        .from('direct_bets')
        .select(`
          bet_id,
          event_description,
          stake_proposer_cents,
          stake_acceptor_cents,
          status,
          outcome,
          created_at,
          accepted_at,
          resolved_at,
          proposer_id,
          acceptor_id,
          target_user_id,
          proposer:users!direct_bets_proposer_id_fkey(username),
          acceptor:users!direct_bets_acceptor_id_fkey(username)
        `)
        .or(`proposer_id.eq.${user.id},acceptor_id.eq.${user.id},target_user_id.eq.${user.id}`)

      // Apply status filter
      if (filter !== 'all') {
        query = query.eq('status', filter.toUpperCase())
      }

      const { data, error } = await query.order('created_at', { ascending: false })

      if (error) throw error
      setMyBets(data as any || [])
    } catch (err) {
      console.error('Error loading bets:', err)
    } finally {
      setLoading(false)
    }
  }

  const getStatusBadge = (status: string) => {
    const styles: Record<string, string> = {
      PENDING: 'bg-yellow-100 text-yellow-800',
      ACTIVE: 'bg-blue-100 text-blue-800',
      RESOLVED: 'bg-green-100 text-green-800',
      DISPUTED: 'bg-red-100 text-red-800',
      CANCELED: 'bg-gray-100 text-gray-800',
      EXPIRED: 'bg-gray-100 text-gray-800',
    }
    return (
      <span className={`px-2 py-1 rounded-full text-xs font-semibold ${styles[status] || 'bg-gray-100'}`}>
        {status}
      </span>
    )
  }

  const getBetType = (targetUserId: number | null) => {
    if (targetUserId) {
      return <span className="text-xs text-purple-600 font-medium">👤 Direct</span>
    }
    return <span className="text-xs text-blue-600 font-medium">🌐 Marketplace</span>
  }

  const getRole = (bet: Bet, userId: number) => {
    if (bet.proposer_id === userId) {
      return <span className="text-xs bg-purple-100 text-purple-700 px-2 py-0.5 rounded">Proposer</span>
    }
    return <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded">Acceptor</span>
  }

  const getOutcome = (bet: Bet, userId: number) => {
    if (bet.status !== 'RESOLVED' || !bet.outcome) return null
    
    const isProposer = bet.proposer_id === userId
    let won = false

    if (bet.outcome === 'PROPOSER_WIN' && isProposer) won = true
    if (bet.outcome === 'ACCEPTOR_WIN' && !isProposer) won = true
    if (bet.outcome === 'VOID') return <span className="text-gray-600 font-semibold">⊘ VOID</span>
    
    return won ? (
      <span className="text-green-600 font-semibold">✓ WON</span>
    ) : (
      <span className="text-red-600 font-semibold">✗ LOST</span>
    )
  }

  const getOpponent = (bet: Bet, userId: number) => {
    const isProposer = bet.proposer_id === userId
    const isTarget = bet.target_user_id === userId
    
    // If user is the target of a pending direct bet (incoming bet)
    if (bet.status === 'PENDING' && isTarget && !bet.acceptor_id) {
      return bet.proposer.username
    }
    
    // If user is the proposer of a pending bet (sent bet)
    if (bet.status === 'PENDING' && isProposer) {
      return bet.target_user_id ? (
        <span className="text-gray-500 italic">Awaiting {bet.acceptor?.username || 'target user'}</span>
      ) : (
        <span className="text-gray-500 italic">Awaiting anyone</span>
      )
    }

    return isProposer ? bet.acceptor?.username : bet.proposer.username
  }

  const handleAcceptDirectBet = async (bet: Bet, e: React.MouseEvent) => {
    e.stopPropagation() // Prevent opening chat dialog
    
    const userData = localStorage.getItem('user')
    if (!userData) return
    
    const user = JSON.parse(userData)
    const stakeAmount = bet.stake_proposer_cents

    // Check if user has enough balance
    if (user.wallet_balance * 100 < stakeAmount) {
      alert(`Insufficient funds. You need $${stakeAmount / 100} but only have $${user.wallet_balance}`)
      return
    }

    setAcceptingBet(bet.bet_id)
    try {
      const { error } = await supabase.rpc('bet_accept', {
        p_bet_id: bet.bet_id,
        p_acceptor_id: user.id,
        p_stake_acceptor_cents: stakeAmount,
      })

      if (error) {
        console.error('Error accepting bet:', error)
        alert('Failed to accept bet. Please try again.')
        return
      }

      // Update balance in database
      const newBalance = user.wallet_balance - (stakeAmount / 100)
      const { error: updateError } = await supabase
        .from('users')
        .update({ wallet_balance: newBalance })
        .eq('user_id', user.id)

      if (updateError) {
        console.error('Error updating balance:', updateError)
        alert('Failed to update balance. Please try again.')
        return
      }

      // Update local storage balance
      user.wallet_balance = newBalance
      localStorage.setItem('user', JSON.stringify(user))

      alert('Bet accepted successfully!')
      
      // Reload bets
      await loadMyBets()
    } catch (err) {
      console.error('Error accepting bet:', err)
      alert('An error occurred. Please try again.')
    } finally {
      setAcceptingBet(null)
    }
  }

  const handleRejectDirectBet = async (bet: Bet, e: React.MouseEvent) => {
    e.stopPropagation() // Prevent opening chat dialog
    
    if (!confirm('Are you sure you want to reject this bet?')) return

    setRejectingBet(bet.bet_id)
    try {
      // Delete the bet
      const { error } = await supabase
        .from('direct_bets')
        .delete()
        .eq('bet_id', bet.bet_id)

      if (error) {
        console.error('Error rejecting bet:', error)
        alert('Failed to reject bet. Please try again.')
        return
      }

      alert('Bet rejected successfully!')
      
      // Reload bets
      await loadMyBets()
    } catch (err) {
      console.error('Error rejecting bet:', err)
      alert('An error occurred. Please try again.')
    } finally {
      setRejectingBet(null)
    }
  }

  const openBetChat = async (bet: Bet) => {
    setSelectedBet(bet)
    setChatOpen(true)
    await loadMessages(bet.bet_id)
  }

  const loadMessages = async (betId: number) => {
    try {
      // First, ensure a thread exists for this bet
      const { data: threadData, error: threadError } = await supabase
        .from('bet_threads')
        .select('thread_id')
        .eq('bet_id', betId)
        .single()

      let threadId: number

      if (threadError || !threadData) {
        // Create thread if it doesn't exist
        console.log('Creating thread for bet_id:', betId)
        const { data: newThread, error: createError } = await supabase
          .from('bet_threads')
          .insert({ bet_id: betId, visibility: 'PRIVATE' })
          .select('thread_id')
          .single()

        if (createError) {
          console.error('Error creating thread:', createError)
          console.error('Error details:', JSON.stringify(createError, null, 2))
          return
        }
        
        if (!newThread) {
          console.error('No thread returned after insert')
          return
        }
        
        threadId = newThread.thread_id
        console.log('Thread created with ID:', threadId)
      } else {
        threadId = threadData.thread_id
        console.log('Found existing thread ID:', threadId)
      }

      // Load messages for this thread
      const { data: messagesData, error: messagesError } = await supabase
        .from('comments')
        .select(`
          comment_id,
          author_id,
          body,
          created_at,
          author:users!comments_author_id_fkey(username)
        `)
        .eq('thread_id', threadId)
        .eq('is_deleted', false)
        .order('created_at', { ascending: true })

      if (messagesError) {
        console.error('Error loading messages:', messagesError)
        return
      }

      setMessages(messagesData as any || [])
    } catch (err) {
      console.error('Error in loadMessages:', err)
    }
  }

  const sendMessage = async () => {
    if (!newMessage.trim() || !selectedBet || !currentUserId) return

    setSendingMessage(true)
    try {
      // Get or create thread_id for this bet
      const { data: threadData, error: threadError } = await supabase
        .from('bet_threads')
        .select('thread_id')
        .eq('bet_id', selectedBet.bet_id)
        .single()

      let threadId: number

      if (threadError || !threadData) {
        // Create thread if it doesn't exist
        console.log('Creating thread for bet_id:', selectedBet.bet_id)
        const { data: newThread, error: createError } = await supabase
          .from('bet_threads')
          .insert({ bet_id: selectedBet.bet_id, visibility: 'PRIVATE' })
          .select('thread_id')
          .single()

        if (createError) {
          console.error('Error creating thread:', createError)
          console.error('Error details:', JSON.stringify(createError, null, 2))
          alert('Failed to create chat thread. Please try again.')
          return
        }
        
        if (!newThread) {
          console.error('No thread returned after insert')
          alert('Failed to create chat thread. Please try again.')
          return
        }
        
        threadId = newThread.thread_id
        console.log('Thread created with ID:', threadId)
      } else {
        threadId = threadData.thread_id
        console.log('Using existing thread ID:', threadId)
      }

      // Insert new comment
      const { error } = await supabase
        .from('comments')
        .insert({
          thread_id: threadId,
          author_id: currentUserId,
          body: newMessage.trim(),
        })

      if (error) {
        console.error('Error sending message:', error)
        alert('Failed to send message. Please try again.')
        return
      }

      // Reload messages
      await loadMessages(selectedBet.bet_id)
      setNewMessage('')
    } catch (err) {
      console.error('Error in sendMessage:', err)
      alert('An error occurred. Please try again.')
    } finally {
      setSendingMessage(false)
    }
  }

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center">Loading...</div>
  }

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-7xl mx-auto">
        <div className="mb-6 flex justify-between items-center">
          <h1 className="text-3xl font-bold">My Bets</h1>
          <Button variant="outline" onClick={() => router.push('/dashboard')}>
            ← Dashboard
          </Button>
        </div>

        {/* Filter Buttons */}
        <div className="mb-6 flex gap-2">
          <Button
            variant={filter === 'all' ? 'default' : 'outline'}
            onClick={() => setFilter('all')}
          >
            All Bets
          </Button>
          <Button
            variant={filter === 'pending' ? 'default' : 'outline'}
            onClick={() => setFilter('pending')}
          >
            Pending
          </Button>
          <Button
            variant={filter === 'active' ? 'default' : 'outline'}
            onClick={() => setFilter('active')}
          >
            Active
          </Button>
          <Button
            variant={filter === 'resolved' ? 'default' : 'outline'}
            onClick={() => setFilter('resolved')}
          >
            Resolved
          </Button>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Your Betting History</CardTitle>
          </CardHeader>
          <CardContent>
            {myBets.length === 0 ? (
              <p className="text-center text-gray-500 py-8">
                No bets found. Create or accept one to get started!
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b">
                      <th className="text-left p-3 font-semibold">Date</th>
                      <th className="text-left p-3 font-semibold">Bet Description</th>
                      <th className="text-left p-3 font-semibold">Type</th>
                      <th className="text-left p-3 font-semibold">Role</th>
                      <th className="text-left p-3 font-semibold">Opponent</th>
                      <th className="text-right p-3 font-semibold">Your Stake</th>
                      <th className="text-center p-3 font-semibold">Status</th>
                      <th className="text-center p-3 font-semibold">Result</th>
                      <th className="text-center p-3 font-semibold">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {myBets.map((bet) => {
                      const isProposer = bet.proposer_id === currentUserId
                      const isTarget = bet.target_user_id === currentUserId
                      const isPendingIncoming = bet.status === 'PENDING' && isTarget && !bet.acceptor_id
                      const myStake = isProposer ? bet.stake_proposer_cents : (bet.stake_acceptor_cents || bet.stake_proposer_cents)
                      
                      return (
                        <tr 
                          key={bet.bet_id} 
                          className="border-b hover:bg-gray-200 cursor-pointer transition-colors"
                          onClick={() => openBetChat(bet)}
                        >
                          <td className="p-3 text-sm text-gray-600">
                            {new Date(bet.created_at).toLocaleDateString()}
                          </td>
                          <td className="p-3">
                            <div className="max-w-xs">
                              <p className="font-medium">{bet.event_description}</p>
                            </div>
                          </td>
                          <td className="p-3">
                            {getBetType(bet.target_user_id)}
                          </td>
                          <td className="p-3">
                            {isPendingIncoming ? (
                              <span className="text-xs bg-orange-100 text-orange-700 px-2 py-0.5 rounded">Incoming</span>
                            ) : (
                              getRole(bet, currentUserId!)
                            )}
                          </td>
                          <td className="p-3">
                            {getOpponent(bet, currentUserId!)}
                          </td>
                          <td className="p-3 text-right font-semibold">
                            ${(myStake / 100).toFixed(2)}
                          </td>
                          <td className="p-3 text-center">
                            {getStatusBadge(bet.status)}
                          </td>
                          <td className="p-3 text-center">
                            {getOutcome(bet, currentUserId!)}
                          </td>
                          <td className="p-3 text-center">
                            {isPendingIncoming && (
                              <div className="flex gap-2 justify-center">
                                <Button
                                  size="sm"
                                  className="bg-green-600 hover:bg-green-700"
                                  onClick={(e) => handleAcceptDirectBet(bet, e)}
                                  disabled={acceptingBet === bet.bet_id || rejectingBet === bet.bet_id}
                                >
                                  {acceptingBet === bet.bet_id ? 'Accepting...' : 'Accept'}
                                </Button>
                                <Button
                                  size="sm"
                                  className="bg-red-600 hover:bg-red-700 text-white"
                                  onClick={(e) => handleRejectDirectBet(bet, e)}
                                  disabled={acceptingBet === bet.bet_id || rejectingBet === bet.bet_id}
                                >
                                  {rejectingBet === bet.bet_id ? 'Rejecting...' : 'Reject'}
                                </Button>
                              </div>
                            )}
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

        {/* Chat Dialog */}
        <Dialog open={chatOpen} onOpenChange={setChatOpen}>
          <DialogContent className="max-w-2xl w-[90vw] h-[85vh] flex flex-col bg-white rounded-3xl shadow-2xl p-0 gap-0">
            <DialogHeader className="px-6 py-4 border-b bg-linear-to-r from-blue-50 to-purple-50 rounded-t-3xl">
              <DialogTitle className="flex items-center justify-between">
                <div>
                  <div className="font-bold text-lg text-gray-800">
                    {selectedBet?.event_description}
                  </div>
                  <div className="text-sm text-gray-500 font-normal mt-1">
                    {selectedBet && currentUserId && (
                      <>
                        💬 Chatting with {getOpponent(selectedBet, currentUserId)}
                      </>
                    )}
                  </div>
                </div>
              </DialogTitle>
            </DialogHeader>

            {/* Messages Container - White background */}
            <div className="flex-1 overflow-y-auto space-y-3 py-6 px-6 bg-white">
              {messages.length === 0 ? (
                <div className="text-center text-gray-400 py-12">
                  💬 No messages yet. Start the conversation!
                </div>
              ) : (
                messages.map((message) => {
                  const isOwnMessage = message.author_id === currentUserId
                  return (
                    <div
                      key={message.comment_id}
                      className={`flex ${isOwnMessage ? 'justify-end' : 'justify-start'}`}
                    >
                      <div
                        className={`max-w-[70%] rounded-2xl px-4 py-3 shadow-sm ${
                          isOwnMessage
                            ? 'bg-blue-500 text-white rounded-br-sm'
                            : 'bg-gray-100 text-gray-900 rounded-bl-sm'
                        }`}
                      >
                        <div className="text-xs font-semibold mb-1 opacity-80">
                          {message.author.username}
                        </div>
                        <div className="whitespace-pre-wrap wrap-break-word text-sm">
                          {message.body}
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

            {/* Message Input - White background */}
            <div className="border-t bg-white px-6 py-4 rounded-b-3xl flex gap-3">
              <Textarea
                placeholder="Type your message..."
                value={newMessage}
                onChange={(e) => setNewMessage(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault()
                    sendMessage()
                  }
                }}
                className="flex-1 resize-none bg-gray-50 border-gray-200 rounded-xl"
                rows={2}
              />
              <Button
                onClick={sendMessage}
                disabled={sendingMessage || !newMessage.trim()}
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

