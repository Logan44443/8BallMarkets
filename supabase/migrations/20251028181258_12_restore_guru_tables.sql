-- Restore minimal tables for each guru's milestone demo

-- For Lukas (Comments Guru): Restore basic comments
-- Just Bet_Threads and Comments (no reactions, mentions, reports)
CREATE TABLE Bet_Threads (
  thread_id BIGSERIAL PRIMARY KEY,
  bet_id BIGINT NOT NULL UNIQUE,
  visibility TEXT NOT NULL DEFAULT 'PRIVATE' CHECK (visibility IN ('PRIVATE','PUBLIC')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (bet_id) REFERENCES direct_bets(bet_id) ON DELETE CASCADE
);

CREATE TABLE Comments (
  comment_id BIGSERIAL PRIMARY KEY,
  thread_id BIGINT NOT NULL REFERENCES Bet_Threads(thread_id) ON DELETE CASCADE,
  author_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  edited_at TIMESTAMPTZ,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_comments_thread_time ON Comments(thread_id, created_at DESC);
CREATE INDEX idx_comments_author_time ON Comments(author_id, created_at DESC);

-- For Leonardo (Social/Friends Guru): Restore basic friends
CREATE TABLE friend_requests (
    request_id BIGSERIAL PRIMARY KEY,
    sender_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    receiver_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('PENDING', 'ACCEPTED', 'REJECTED', 'CANCELED')),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    CHECK (sender_id <> receiver_id),
    UNIQUE (sender_id, receiver_id)
);

CREATE TABLE friends (
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    friend_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    friended_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, friend_id),
    CHECK (user_id <> friend_id)
);

-- For Alain (Order Book) and team in general: 
-- They can work with direct_bets which already exists

