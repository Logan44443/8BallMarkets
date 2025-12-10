-- Create Support Tickets system for admin access
-- Support tickets are chats between users and admins/support staff

CREATE TABLE IF NOT EXISTS support_tickets (
  ticket_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  subject TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED')),
  priority TEXT NOT NULL DEFAULT 'NORMAL' CHECK (priority IN ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  assigned_to BIGINT REFERENCES users(user_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS ticket_messages (
  message_id BIGSERIAL PRIMARY KEY,
  ticket_id BIGINT NOT NULL REFERENCES support_tickets(ticket_id) ON DELETE CASCADE,
  author_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_internal BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_support_tickets_user ON support_tickets(user_id);
CREATE INDEX idx_support_tickets_status ON support_tickets(status);
CREATE INDEX idx_support_tickets_assigned ON support_tickets(assigned_to);
CREATE INDEX idx_ticket_messages_ticket ON ticket_messages(ticket_id, created_at);

-- Helper functions for RLS
CREATE OR REPLACE FUNCTION current_user_id()
RETURNS BIGINT AS $$
  SELECT NULLIF(current_setting('app.current_user_id', TRUE), '')::BIGINT;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION current_user_is_admin()
RETURNS BOOLEAN AS $$
  SELECT COALESCE(current_setting('app.current_is_admin', TRUE), 'false')::BOOLEAN;
$$ LANGUAGE SQL STABLE;

-- RLS Policies
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_messages ENABLE ROW LEVEL SECURITY;

-- Users can view their own tickets
CREATE POLICY "support_tickets_select_own" ON support_tickets
  FOR SELECT
  USING (user_id = current_user_id());

-- Admins can view all tickets
CREATE POLICY "support_tickets_admin_select" ON support_tickets
  FOR SELECT
  USING (current_user_is_admin());

-- Users can create tickets
CREATE POLICY "support_tickets_insert_own" ON support_tickets
  FOR INSERT
  WITH CHECK (user_id = current_user_id());

-- Admins can update any ticket
CREATE POLICY "support_tickets_admin_update" ON support_tickets
  FOR UPDATE
  USING (current_user_is_admin())
  WITH CHECK (current_user_is_admin());

-- Users can view messages on their own tickets
CREATE POLICY "ticket_messages_select_own" ON ticket_messages
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM support_tickets 
      WHERE support_tickets.ticket_id = ticket_messages.ticket_id 
      AND support_tickets.user_id = current_user_id()
    )
  );

-- Admins can view all messages
CREATE POLICY "ticket_messages_admin_select" ON ticket_messages
  FOR SELECT
  USING (current_user_is_admin());

-- Users can send messages on their own tickets
CREATE POLICY "ticket_messages_insert_own" ON ticket_messages
  FOR INSERT
  WITH CHECK (
    author_id = current_user_id()
    AND EXISTS (
      SELECT 1 FROM support_tickets 
      WHERE support_tickets.ticket_id = ticket_messages.ticket_id 
      AND support_tickets.user_id = current_user_id()
    )
    AND is_internal = FALSE
  );

-- Admins can send messages on any ticket
CREATE POLICY "ticket_messages_admin_insert" ON ticket_messages
  FOR INSERT
  WITH CHECK (current_user_is_admin() AND author_id = current_user_id());

COMMENT ON TABLE support_tickets IS 'Support tickets for user help requests - admins can view and respond to all';
COMMENT ON TABLE ticket_messages IS 'Messages within support tickets - persistent chat history';

