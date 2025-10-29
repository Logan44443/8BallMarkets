CREATE TYPE ticket_status AS ENUM ('OPEN','ASSIGNED','WAITING_USER','WAITING_STAFF','RESOLVED','CLOSED');
CREATE TYPE ticket_priority AS ENUM ('LOW','MEDIUM','HIGH','CRITICAL');



CREATE TABLE Support_Tickets (
  ticket_id BIGSERIAL PRIMARY KEY,
  creator_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  subject VARCHAR(200) NOT NULL,
  status ticket_status NOT NULL DEFAULT 'OPEN',
  priority ticket_priority NOT NULL DEFAULT 'MEDIUM',
  related_bet_id BIGINT REFERENCES direct_bets(bet_id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  assignee_id BIGINT REFERENCES users(user_id) ON DELETE SET NULL
);

CREATE TABLE Ticket_Messages (
  message_id BIGSERIAL PRIMARY KEY,
  ticket_id BIGINT NOT NULL REFERENCES Support_Tickets(ticket_id) ON DELETE CASCADE,
  author_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_internal_note BOOLEAN NOT NULL DEFAULT FALSE  
);


CREATE OR REPLACE FUNCTION fn_ticket_touch()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE Support_Tickets SET updated_at = now() WHERE ticket_id = NEW.ticket_id;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ticket_touch
AFTER INSERT ON Ticket_Messages FOR EACH ROW EXECUTE FUNCTION fn_ticket_touch();


CREATE TABLE Ticket_Tags (
  tag TEXT PRIMARY KEY
);
CREATE TABLE Ticket_Tag_Map (
  ticket_id BIGINT REFERENCES Support_Tickets(ticket_id) ON DELETE CASCADE,
  tag TEXT REFERENCES Ticket_Tags(tag) ON DELETE CASCADE,
  PRIMARY KEY (ticket_id, tag)
);


CREATE INDEX idx_tickets_status_updated ON Support_Tickets(status, updated_at DESC);
CREATE INDEX idx_tickets_assignee_updated ON Support_Tickets(assignee_id, updated_at DESC);
CREATE INDEX idx_tickets_creator_updated ON Support_Tickets(creator_id, updated_at DESC);
