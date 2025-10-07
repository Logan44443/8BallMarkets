
CREATE TYPE comment_visibility AS ENUM ('PRIVATE_BET_THREAD','PUBLIC');

CREATE TABLE Bet_Threads (
  thread_id BIGSERIAL PRIMARY KEY,
  bet_id BIGINT NOT NULL UNIQUE,
  visibility comment_visibility NOT NULL DEFAULT 'PRIVATE_BET_THREAD',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (bet_id) REFERENCES Bets(bet_id) ON DELETE CASCADE
);

CREATE TABLE Comments (
  comment_id BIGSERIAL PRIMARY KEY,
  thread_id BIGINT NOT NULL,
  author_id BIGINT NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  edited_at TIMESTAMPTZ,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  FOREIGN KEY (thread_id) REFERENCES Bet_Threads(thread_id) ON DELETE CASCADE,
  FOREIGN KEY (author_id) REFERENCES Users(user_id) ON DELETE CASCADE
);

CREATE OR REPLACE FUNCTION fn_enforce_private_post()
RETURNS TRIGGER AS $$
BEGIN
  IF (SELECT visibility FROM Bet_Threads WHERE thread_id = NEW.thread_id) = 'PRIVATE_BET_THREAD' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM Bets b JOIN Bet_Threads t ON t.bet_id = b.bet_id
      WHERE t.thread_id = NEW.thread_id
        AND NEW.author_id IN (b.proposer_id, b.acceptor_id, b.arbiter_id)
    ) THEN
      RAISE EXCEPTION 'Only participants of the bet can post in this thread';
    END IF;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_private_post
BEFORE INSERT ON Comments FOR EACH ROW EXECUTE FUNCTION fn_enforce_private_post();


CREATE TABLE Comment_Reactions (
  comment_id BIGINT NOT NULL REFERENCES Comments(comment_id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
  reaction TEXT NOT NULL CHECK (reaction IN ('like','helpful','funny')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (comment_id, user_id, reaction)
);

CREATE TABLE Comment_Mentions (
  comment_id BIGINT NOT NULL REFERENCES Comments(comment_id) ON DELETE CASCADE,
  mentioned_user_id BIGINT NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
  PRIMARY KEY (comment_id, mentioned_user_id)
);


CREATE TYPE report_reason AS ENUM ('SPAM','ABUSE','OFF_TOPIC','OTHER');
CREATE TABLE Comment_Reports (
  report_id BIGSERIAL PRIMARY KEY,
  comment_id BIGINT NOT NULL REFERENCES Comments(comment_id) ON DELETE CASCADE,
  reporter_id BIGINT NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
  reason report_reason NOT NULL,
  details TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (comment_id, reporter_id)
);


CREATE INDEX idx_comments_thread_time ON Comments(thread_id, created_at DESC);
CREATE INDEX idx_comments_author_time ON Comments(author_id, created_at DESC);
CREATE INDEX idx_reactions_comment ON Comment_Reactions(comment_id);
