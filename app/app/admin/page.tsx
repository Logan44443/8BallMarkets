'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { supabase } from '@/lib/supabase'
import { setAuthContext } from '@/lib/auth'
import { Label } from '@/components/ui/label'

interface SupportTicket {
  ticket_id: number
  user_id: number
  subject: string
  status: string
  priority: string
  created_at: string
  updated_at: string
  user: { username: string }
}

interface TicketMessage {
  message_id: number
  author_id: number
  message: string
  is_internal: boolean
  created_at: string
  author: { username: string }
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
  created_at: string
  accepted_at: string | null
  dispute_notes: string | null
  outcome_notes: string | null
  proposer: { username: string }
  acceptor: { username: string } | null
  arbiter: { username: string } | null
}

export default function AdminDashboardPage() {
  const [tickets, setTickets] = useState<SupportTicket[]>([])
  const [selectedTicket, setSelectedTicket] = useState<SupportTicket | null>(null)
  const [messages, setMessages] = useState<TicketMessage[]>([])
  const [newMessage, setNewMessage] = useState('')
  const [dialogOpen, setDialogOpen] = useState(false)
  const [sendingMessage, setSendingMessage] = useState(false)
  const [currentUserId, setCurrentUserId] = useState<number | null>(null)
  
  // Bet management states
  const [bets, setBets] = useState<Bet[]>([])
  const [selectedBet, setSelectedBet] = useState<Bet | null>(null)
  const [resolveDialogOpen, setResolveDialogOpen] = useState(false)
  const [outcome, setOutcome] = useState<'PROPOSER_WIN' | 'ACCEPTOR_WIN' | 'VOID'>('PROPOSER_WIN')
  const [notes, setNotes] = useState('')
  const [loading, setLoading] = useState(false)
  
  const router = useRouter()

  useEffect(() => {
    checkAdminAndLoadData()
  }, [])

  const checkAdminAndLoadData = async () => {
    const userData = localStorage.getItem('user')
    if (!userData) {
      router.push('/login')
      return
    }

    const user = JSON.parse(userData)
    setCurrentUserId(user.id)
    
    // Check if user is admin
    if (!user.is_admin) {
      alert('You need admin privileges to access this page')
      router.push('/dashboard')
      return
    }

    await setAuthContext(user.id, true)
    loadTickets()
    loadBets()
  }

  const loadTickets = async () => {
    // Re-establish auth context before query
    if (currentUserId) {
      await setAuthContext(currentUserId, true)
    }

    const { data } = await supabase
      .from('support_tickets')
      .select(`
        ticket_id,
        user_id,
        subject,
        status,
        priority,
        created_at,
        updated_at,
        user:users!support_tickets_user_id_fkey(username)
      `)
      .order('updated_at', { ascending: false })

    if (data) {
      // Transform the data
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const transformedTickets = data.map((ticket: any) => ({
        ...ticket,
        user: Array.isArray(ticket.user) ? ticket.user[0] : ticket.user
      }))
      setTickets(transformedTickets as SupportTicket[])
    }
  }

  const loadMessages = async (ticket: SupportTicket) => {
    // Re-establish auth context before loading messages
    if (currentUserId) {
      await setAuthContext(currentUserId, true)
    }

    // Load messages for this ticket - order by created_at ascending (oldest first)
    const { data } = await supabase
      .from('ticket_messages')
      .select(`
        message_id,
        author_id,
        message,
        is_internal,
        created_at,
        author:users!ticket_messages_author_id_fkey(username)
      `)
      .eq('ticket_id', ticket.ticket_id)
      .order('created_at', { ascending: true })

    if (data) {
      // Transform the data
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const transformedMessages = data.map((msg: any) => ({
        ...msg,
        author: Array.isArray(msg.author) ? msg.author[0] : msg.author
      }))
      
      // Explicitly sort by created_at as a safeguard (oldest first)
      transformedMessages.sort((a, b) => 
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
      )
      
      setMessages(transformedMessages as TicketMessage[])
    }
  }

  const openTicket = async (ticket: SupportTicket) => {
    setSelectedTicket(ticket)
    setDialogOpen(true)
    await loadMessages(ticket)
  }

  const sendMessage = async () => {
    if (!newMessage.trim() || !selectedTicket || !currentUserId) return

    setSendingMessage(true)
    try {
      // Re-establish auth context before insert
      await setAuthContext(currentUserId, true)
      
      const { error } = await supabase
        .from('ticket_messages')
        .insert({
          ticket_id: selectedTicket.ticket_id,
          author_id: currentUserId,
          message: newMessage,
          is_internal: false
        })

      if (error) {
        console.error('Insert error:', error)
        alert('Failed to send message: ' + error.message)
        return
      }

      // Update ticket updated_at
      await supabase
        .from('support_tickets')
        .update({ updated_at: new Date().toISOString() })
        .eq('ticket_id', selectedTicket.ticket_id)

      setNewMessage('')
      
      // Small delay to ensure message is committed to database
      await new Promise(resolve => setTimeout(resolve, 200))
      
      // Reload messages with explicit sorting
      await loadMessages(selectedTicket)
      loadTickets() // Refresh ticket list
    } catch (err) {
      console.error('Error sending message:', err)
    } finally {
      setSendingMessage(false)
    }
  }

  const updateTicketStatus = async (status: string) => {
    if (!selectedTicket || !currentUserId) return

    // Re-establish auth context before update
    await setAuthContext(currentUserId, true)

    const { error } = await supabase
      .from('support_tickets')
      .update({ status, updated_at: new Date().toISOString() })
      .eq('ticket_id', selectedTicket.ticket_id)

    if (!error) {
      setSelectedTicket({ ...selectedTicket, status })
      loadTickets()
    }
  }

  // Bet management functions
  const loadBets = async () => {
    // Re-establish auth context before query
    if (currentUserId) {
      await setAuthContext(currentUserId, true)
    }

    const { data: betsData } = await supabase
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
        created_at,
        accepted_at,
        dispute_notes,
        outcome_notes,
        proposer:users!direct_bets_proposer_id_fkey(username),
        acceptor:users!direct_bets_acceptor_id_fkey(username),
        arbiter:users!direct_bets_arbiter_id_fkey(username)
      `)
      .in('status', ['ACTIVE', 'DISPUTED'])
      .order('created_at', { ascending: false })

    if (betsData) {
      // Transform the data to match our Bet type
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const transformedBets = betsData.map((bet: any) => ({
        ...bet,
        proposer: Array.isArray(bet.proposer) ? bet.proposer[0] : bet.proposer,
        acceptor: Array.isArray(bet.acceptor) ? bet.acceptor[0] : bet.acceptor,
        arbiter: Array.isArray(bet.arbiter) ? bet.arbiter[0] : bet.arbiter
      }))
      setBets(transformedBets as Bet[])
    }
  }

  const handleResolveBet = async () => {
    if (!selectedBet || !currentUserId) return

    setLoading(true)
    try {
      // Re-establish auth context before RPC call
      await setAuthContext(currentUserId, true)
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
      if (selectedBet && currentUserId && (selectedBet.proposer_id === currentUserId || selectedBet.acceptor_id === currentUserId)) {
        const { data: updatedBalance } = await supabase
          .from('users')
          .select('wallet_balance')
          .eq('user_id', currentUserId)
          .single()
        
        if (updatedBalance) {
          const userData = localStorage.getItem('user')
          if (userData) {
            const user = JSON.parse(userData)
            user.wallet_balance = updatedBalance.wallet_balance
            user.balance = updatedBalance.wallet_balance
            localStorage.setItem('user', JSON.stringify(user))
          }
        }
      }

      alert('Bet resolved successfully! Balances have been updated.')
      setResolveDialogOpen(false)
      setSelectedBet(null)
      setNotes('')
      loadBets()
    } catch (err) {
      console.error('Error resolving bet:', err)
      alert('Failed to resolve bet')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen p-8" style={{backgroundColor: 'transparent'}}>
      <div className="max-w-7xl mx-auto">
        {/* Header */}
        <div className="mb-6 flex justify-between items-center">
          <div>
            <h1 className="text-3xl font-bold text-white">👑 Admin Dashboard</h1>
            <p className="text-white mt-1">Manage support tickets and bets</p>
          </div>
          <Button variant="outline" onClick={() => router.push('/dashboard')}>
            Back to Dashboard
          </Button>
        </div>

        {/* Support Tickets */}
        <Card>
          <CardHeader>
            <CardTitle>All Support Tickets ({tickets.length})</CardTitle>
          </CardHeader>
          <CardContent>
            {tickets.length === 0 ? (
              <p className="text-gray-500 text-center py-8">No support tickets yet</p>
            ) : (
              <div className="space-y-3">
                {tickets.map(ticket => (
                  <div
                    key={ticket.ticket_id}
                    onClick={() => openTicket(ticket)}
                    className="border rounded-lg p-4 hover:bg-gray-50 cursor-pointer transition"
                  >
                    <div className="flex justify-between items-start">
                      <div className="flex-1">
                        <div className="flex items-center gap-3 mb-2">
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
                          <span className="text-sm font-medium text-blue-600">
                            @{ticket.user.username}
                          </span>
                        </div>
                        <p className="font-semibold text-lg">{ticket.subject}</p>
                        <p className="text-xs text-gray-500 mt-2">
                          Created: {new Date(ticket.created_at).toLocaleString()} • 
                          Updated: {new Date(ticket.updated_at).toLocaleString()}
                        </p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Bet Management */}
        <Card className="mt-6">
          <CardHeader>
            <CardTitle>All Active & Disputed Bets ({bets.length})</CardTitle>
          </CardHeader>
          <CardContent>
            {bets.length === 0 ? (
              <p className="text-gray-500 text-center py-8">No active or disputed bets</p>
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
                          {bet.arbiter && (
                            <span className="text-xs text-gray-600">
                              Arbiter: @{bet.arbiter.username}
                            </span>
                          )}
                        </div>
                        <p className="font-semibold text-lg mb-2">{bet.event_description}</p>
                        <div className="grid grid-cols-2 gap-4 text-sm text-gray-600">
                          <div>
                            <p className="font-medium text-gray-900">Proposer:</p>
                            <p>@{bet.proposer.username}</p>
                            <p className="text-green-600 font-medium">
                              ${(bet.stake_proposer_cents / 100).toFixed(2)} staked
                            </p>
                          </div>
                          <div>
                            <p className="font-medium text-gray-900">Acceptor:</p>
                            <p>@{bet.acceptor?.username || 'N/A'}</p>
                            {bet.stake_acceptor_cents && (
                              <p className="text-green-600 font-medium">
                                ${(bet.stake_acceptor_cents / 100).toFixed(2)} staked
                              </p>
                            )}
                          </div>
                        </div>
                        {bet.status === 'DISPUTED' && (bet.dispute_notes || bet.outcome_notes) && (
                          <div className="mt-3 p-2 bg-red-50 border border-red-200 rounded text-sm">
                            <p className="font-medium text-red-800">⚠️ Dispute Notes:</p>
                            <p className="text-gray-700">{bet.dispute_notes || bet.outcome_notes}</p>
                          </div>
                        )}
                        <p className="text-xs text-gray-500 mt-2">
                          Created: {new Date(bet.created_at).toLocaleDateString()}
                          {bet.accepted_at && ` • Accepted: ${new Date(bet.accepted_at).toLocaleDateString()}`}
                        </p>
                      </div>
                      <Button 
                        onClick={() => {
                          setSelectedBet(bet)
                          setResolveDialogOpen(true)
                        }}
                        className="ml-4 bg-purple-600 hover:bg-purple-700"
                      >
                        Resolve as Admin
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Ticket Chat Dialog */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-3xl w-[90vw] h-[85vh] flex flex-col bg-white rounded-3xl shadow-2xl p-0 gap-0">
          <DialogHeader className="px-6 py-4 border-b bg-gradient-to-r from-purple-50 to-pink-50 rounded-t-3xl">
            <DialogTitle className="flex items-center justify-between">
              <div>
                <div className="font-bold text-lg text-gray-800">
                  {selectedTicket?.subject}
                </div>
                <DialogDescription className="text-sm text-gray-500 font-normal mt-1">
                  💬 Chat with @{selectedTicket?.user.username}
                </DialogDescription>
              </div>
              {selectedTicket && (
                <div className="flex gap-2">
                  <select
                    value={selectedTicket.status}
                    onChange={(e) => updateTicketStatus(e.target.value)}
                    className="px-3 py-1 border rounded text-sm"
                  >
                    <option value="OPEN">OPEN</option>
                    <option value="IN_PROGRESS">IN PROGRESS</option>
                    <option value="RESOLVED">RESOLVED</option>
                    <option value="CLOSED">CLOSED</option>
                  </select>
                </div>
              )}
            </DialogTitle>
          </DialogHeader>

          {/* Messages */}
          <div className="flex-1 overflow-y-auto space-y-3 py-6 px-6 bg-white">
            {messages.length === 0 ? (
              <div className="text-center text-gray-400 py-12">
                💬 No messages yet. Start the conversation!
              </div>
            ) : (
              messages.map((message) => {
                const isAdminMessage = message.author_id === currentUserId
                return (
                  <div
                    key={message.message_id}
                    className={`flex ${isAdminMessage ? 'justify-end' : 'justify-start'}`}
                  >
                    <div
                      className={`max-w-[70%] rounded-2xl px-4 py-3 shadow-sm ${
                        isAdminMessage
                          ? 'bg-purple-500 text-white rounded-br-sm'
                          : 'bg-gray-100 text-gray-900 rounded-bl-sm'
                      }`}
                    >
                      <div className="text-xs font-semibold mb-1 opacity-80">
                        {message.author.username}
                        {isAdminMessage && ' 👑'}
                      </div>
                      <div className="whitespace-pre-wrap text-sm">
                        {message.message}
                      </div>
                      <div
                        className={`text-xs mt-1 opacity-70 ${
                          isAdminMessage ? 'text-purple-50' : 'text-gray-500'
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
              placeholder="Type your response..."
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
              className="self-end px-6 rounded-xl bg-purple-600 hover:bg-purple-700"
            >
              Send
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Bet Resolve Dialog */}
      <Dialog open={resolveDialogOpen} onOpenChange={setResolveDialogOpen}>
        <DialogContent className="max-w-2xl [&>button]:bg-gray-800 [&>button]:text-white [&>button]:hover:bg-gray-900">
          <DialogHeader>
            <DialogTitle>Resolve Bet (Admin Override)</DialogTitle>
            <DialogDescription>
              Resolve a bet as an admin, overriding the assigned arbiter.
            </DialogDescription>
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
                {selectedBet.arbiter && (
                  <p className="text-sm text-gray-600 mt-2">
                    Assigned Arbiter: @{selectedBet.arbiter.username}
                  </p>
                )}
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
                <Label htmlFor="admin-notes">Resolution Notes (Optional)</Label>
                <Textarea
                  id="admin-notes"
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

              <div className="bg-purple-50 border border-purple-200 p-3 rounded text-sm">
                <p className="font-medium text-purple-800">👑 Admin Override</p>
                <p className="text-gray-700">As an admin, you can resolve any bet regardless of assigned arbiter.</p>
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
                  onClick={handleResolveBet}
                  disabled={loading}
                  className="bg-purple-600 hover:bg-purple-700"
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

