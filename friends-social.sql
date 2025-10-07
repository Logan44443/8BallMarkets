-- ====================================================================
-- Friends / Social Schema (PostgreSQL)
-- PROJECT: P2P Betting App - Friends / Social Module
-- AUTHOR: Leonardo Stocco Lanfranchi
-- ====================================================================
-- Assumptions:
--   - There is a users table at public.users(user_id BIGINT PK).
--   - This file creates a minimal core.bets_settlements table so the
--     social analytics (head-to-head, leaderboards) work immediately.
-- ====================================================================

CREATE SCHEMA IF NOT EXISTS social;
CREATE SCHEMA IF NOT EXISTS core;
SET search_path = social, public;


CREATE TABLE IF NOT EXISTS core.bets_settlements (
    bet_id       BIGSERIAL PRIMARY KEY,
    created_by   BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE, 
    accepted_by  BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    amount       NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    winner_id    BIGINT REFERENCES public.users(user_id) ON DELETE SET NULL,
    loser_id     BIGINT REFERENCES public.users(user_id) ON DELETE SET NULL,
    winner_pl    NUMERIC(14,2) DEFAULT 0, 
    loser_pl     NUMERIC(14,2) DEFAULT 0, 
    settled_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT parties_distinct CHECK (created_by <> accepted_by),
    CONSTRAINT consistent_outcome CHECK (
        (winner_id IS NULL AND loser_id IS NULL AND winner_pl = 0 AND loser_pl = 0)
        OR
        (winner_id IS NOT NULL AND loser_id IS NOT NULL AND winner_pl > 0 AND loser_pl < 0)
    ),
    CONSTRAINT winner_is_party CHECK (winner_id IS NULL OR winner_id IN (created_by, accepted_by)),
    CONSTRAINT loser_is_party  CHECK (loser_id  IS NULL OR loser_id  IN (created_by, accepted_by))
);

CREATE INDEX IF NOT EXISTS idx_settlements_parties ON core.bets_settlements(created_by, accepted_by);
CREATE INDEX IF NOT EXISTS idx_settlements_winner  ON core.bets_settlements(winner_id);
CREATE INDEX IF NOT EXISTS idx_settlements_loser   ON core.bets_settlements(loser_id);
CREATE INDEX IF NOT EXISTS idx_settlements_time    ON core.bets_settlements(settled_at);

CREATE TABLE IF NOT EXISTS blocks (
    block_id        BIGSERIAL PRIMARY KEY,
    blocker_id      BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    blocked_id      BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT blocks_no_self CHECK (blocker_id <> blocked_id),
    CONSTRAINT blocks_unique_pair UNIQUE (blocker_id, blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_id);

CREATE TABLE IF NOT EXISTS friend_requests (
    request_id      BIGSERIAL PRIMARY KEY,
    requester_id    BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    recipient_id    BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    status          TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','ACCEPTED','DECLINED','CANCELLED')),
    message         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at    TIMESTAMPTZ,
    CONSTRAINT fr_no_self CHECK (requester_id <> recipient_id)
);

CREATE INDEX IF NOT EXISTS idx_fr_requester ON friend_requests(requester_id);
CREATE INDEX IF NOT EXISTS idx_fr_recipient ON friend_requests(recipient_id);
CREATE INDEX IF NOT EXISTS idx_fr_status    ON friend_requests(status);

CREATE OR REPLACE FUNCTION social.fn_block_prevent_request()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'PENDING' AND EXISTS (
    SELECT 1 FROM social.blocks b
    WHERE (b.blocker_id = NEW.requester_id AND b.blocked_id = NEW.recipient_id)
       OR (b.blocker_id = NEW.recipient_id AND b.blocked_id = NEW.requester_id)
  ) THEN
    RAISE EXCEPTION 'Cannot send friend request: one of the users has blocked the other.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_block_prevent_request ON friend_requests;
CREATE TRIGGER trg_block_prevent_request
BEFORE INSERT ON friend_requests
FOR EACH ROW EXECUTE FUNCTION social.fn_block_prevent_request();

CREATE TABLE IF NOT EXISTS friendships (
    friendship_id   BIGSERIAL PRIMARY KEY,
    user_id_low     BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    user_id_high    BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT friendships_order CHECK (user_id_low < user_id_high),
    CONSTRAINT friendships_unique UNIQUE (user_id_low, user_id_high)
);

CREATE INDEX IF NOT EXISTS idx_friendships_low  ON friendships(user_id_low);
CREATE INDEX IF NOT EXISTS idx_friendships_high ON friendships(user_id_high);


CREATE OR REPLACE FUNCTION social.fn_block_prevent_friendship()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM social.blocks b
    WHERE (b.blocker_id = NEW.user_id_low  AND b.blocked_id = NEW.user_id_high)
       OR (b.blocker_id = NEW.user_id_high AND b.blocked_id = NEW.user_id_low)
  ) THEN
    RAISE EXCEPTION 'Cannot create friendship: one of the users has blocked the other.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_block_prevent_friendship ON friendships;
CREATE TRIGGER trg_block_prevent_friendship
BEFORE INSERT ON friendships
FOR EACH ROW EXECUTE FUNCTION social.fn_block_prevent_friendship();


CREATE OR REPLACE FUNCTION social.fn_accept_request_creates_friendship()
RETURNS TRIGGER AS $$
DECLARE
  u_low  BIGINT := LEAST(NEW.requester_id, NEW.recipient_id);
  u_high BIGINT := GREATEST(NEW.requester_id, NEW.recipient_id);
BEGIN
  IF NEW.status = 'ACCEPTED' THEN
    INSERT INTO friendships(user_id_low, user_id_high)
    VALUES (u_low, u_high)
    ON CONFLICT (user_id_low, user_id_high) DO NOTHING;
    NEW.responded_at := COALESCE(NEW.responded_at, NOW());
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_accept_request_creates_friendship ON friend_requests;
CREATE TRIGGER trg_accept_request_creates_friendship
AFTER UPDATE OF status ON friend_requests
FOR EACH ROW
WHEN (OLD.status <> 'ACCEPTED' AND NEW.status = 'ACCEPTED')
EXECUTE FUNCTION social.fn_accept_request_creates_friendship();


CREATE OR REPLACE FUNCTION social.fn_auto_unfriend_on_block()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM friendships
  WHERE user_id_low  = LEAST(NEW.blocker_id, NEW.blocked_id)
    AND user_id_high = GREATEST(NEW.blocker_id, NEW.blocked_id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_unfriend_on_block ON blocks;
CREATE TRIGGER trg_auto_unfriend_on_block
AFTER INSERT ON blocks
FOR EACH ROW EXECUTE FUNCTION social.fn_auto_unfriend_on_block();

CREATE TABLE IF NOT EXISTS circles (
    circle_id       BIGSERIAL PRIMARY KEY,
    owner_id        BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    description     TEXT,
    is_private      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_circle_owner_name ON circles(owner_id, name);
CREATE INDEX IF NOT EXISTS idx_circles_owner ON circles(owner_id);

CREATE TABLE IF NOT EXISTS circle_memberships (
    circle_id       BIGINT NOT NULL REFERENCES social.circles(circle_id) ON DELETE CASCADE,
    user_id         BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    role            TEXT NOT NULL DEFAULT 'MEMBER' CHECK (role IN ('OWNER','ADMIN','MEMBER')),
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (circle_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_cm_user ON circle_memberships(user_id);

CREATE TABLE IF NOT EXISTS circle_invites (
    invite_id       BIGSERIAL PRIMARY KEY,
    circle_id       BIGINT NOT NULL REFERENCES social.circles(circle_id) ON DELETE CASCADE,
    inviter_id      BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    invitee_id      BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    status          TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','ACCEPTED','DECLINED','CANCELLED','EXPIRED')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at    TIMESTAMPTZ,
    CONSTRAINT ci_no_self CHECK (invitee_id <> inviter_id),
    CONSTRAINT ci_unique_open UNIQUE (circle_id, invitee_id, status)
);

CREATE INDEX IF NOT EXISTS idx_ci_invitee ON circle_invites(invitee_id);
CREATE INDEX IF NOT EXISTS idx_ci_circle  ON circle_invites(circle_id);


CREATE TABLE IF NOT EXISTS team_bets (
    team_bet_id   BIGSERIAL PRIMARY KEY,
    settlement_id BIGINT NOT NULL REFERENCES core.bets_settlements(bet_id) ON DELETE CASCADE,
    side_a_name   TEXT DEFAULT 'Team A',
    side_b_name   TEXT DEFAULT 'Team B',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT tb_unique_settlement UNIQUE (settlement_id)
);

CREATE TABLE IF NOT EXISTS team_bet_members (
    team_bet_id     BIGINT NOT NULL REFERENCES social.team_bets(team_bet_id) ON DELETE CASCADE,
    user_id         BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    side            TEXT NOT NULL CHECK (side IN ('A','B')),
    share_fraction  NUMERIC(8,6) NOT NULL CHECK (share_fraction > 0 AND share_fraction <= 1),
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (team_bet_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_tb_members_user ON team_bet_members(user_id);


CREATE OR REPLACE FUNCTION social.fn_check_team_shares()
RETURNS TRIGGER AS $$
DECLARE
  sum_a NUMERIC(10,6);
  sum_b NUMERIC(10,6);
BEGIN
  SELECT COALESCE(SUM(share_fraction),0) INTO sum_a FROM team_bet_members WHERE team_bet_id = NEW.team_bet_id AND side = 'A';
  SELECT COALESCE(SUM(share_fraction),0) INTO sum_b FROM team_bet_members WHERE team_bet_id = NEW.team_bet_id AND side = 'B';

  IF sum_a > 1.000001 OR sum_b > 1.000001 THEN
    RAISE EXCEPTION 'Team shares exceed 1.0 for team_bet_id=%', NEW.team_bet_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_team_shares_ins ON team_bet_members;
CREATE TRIGGER trg_check_team_shares_ins
AFTER INSERT OR UPDATE ON team_bet_members
FOR EACH ROW EXECUTE FUNCTION social.fn_check_team_shares();


CREATE OR REPLACE VIEW v_mutual_friends AS
WITH f AS (
  SELECT user_id_low AS u1, user_id_high AS u2 FROM friendships
  UNION ALL
  SELECT user_id_high AS u1, user_id_low  AS u2 FROM friendships
),
pairs AS (
  SELECT a.u1 AS user_a, b.u1 AS user_b, a.u2 AS friend
  FROM f a
  JOIN f b ON a.u2 = b.u2 AND a.u1 < b.u1
)
SELECT user_a, user_b, COUNT(*)::INT AS mutual_count
FROM pairs
GROUP BY user_a, user_b;

CREATE OR REPLACE VIEW v_friends_expanded AS
SELECT user_id_low  AS user_id, user_id_high AS friend_id, created_at
FROM friendships
UNION ALL
SELECT user_id_high AS user_id, user_id_low  AS friend_id, created_at
FROM friendships;


CREATE OR REPLACE VIEW v_relationship_status AS
SELECT
  a.user_id AS user_a,
  b.user_id AS user_b,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM friendships f
      WHERE (f.user_id_low  = LEAST(a.user_id, b.user_id)
         AND f.user_id_high = GREATEST(a.user_id, b.user_id))
    ) THEN 'FRIENDS'
    WHEN EXISTS (
      SELECT 1 FROM blocks bl
      WHERE (bl.blocker_id = a.user_id AND bl.blocked_id = b.user_id)
         OR (bl.blocker_id = b.user_id AND bl.blocked_id = a.user_id)
    ) THEN 'BLOCKED'
    WHEN EXISTS (
      SELECT 1 FROM friend_requests r
      WHERE ((r.requester_id = a.user_id AND r.recipient_id = b.user_id)
          OR (r.requester_id = b.user_id AND r.recipient_id = a.user_id))
        AND r.status = 'PENDING'
    ) THEN 'PENDING'
    ELSE 'NONE'
  END AS relation
FROM public.users a
CROSS JOIN public.users b
WHERE a.user_id < b.user_id;

CREATE OR REPLACE VIEW v_head_to_head AS
SELECT
  LEAST(s.created_by, s.accepted_by) AS user_a,
  GREATEST(s.created_by, s.accepted_by) AS user_b,
  COUNT(*) FILTER (WHERE s.winner_id IS NOT NULL)                                         AS total_decisions,
  COUNT(*) FILTER (WHERE s.winner_id = LEAST(s.created_by, s.accepted_by))                AS a_wins,
  COUNT(*) FILTER (WHERE s.winner_id = GREATEST(s.created_by, s.accepted_by))             AS b_wins,
  COALESCE(SUM(CASE
                  WHEN s.winner_id = LEAST(s.created_by, s.accepted_by)   THEN s.winner_pl
                  WHEN s.loser_id  = LEAST(s.created_by, s.accepted_by)   THEN s.loser_pl
               END), 0)                                                                    AS a_pl,
  COALESCE(SUM(CASE
                  WHEN s.winner_id = GREATEST(s.created_by, s.accepted_by) THEN s.winner_pl
                  WHEN s.loser_id  = GREATEST(s.created_by, s.accepted_by) THEN s.loser_pl
               END), 0)                                                                    AS b_pl
FROM core.bets_settlements s
GROUP BY 1,2;

CREATE OR REPLACE VIEW v_head_to_head_friends AS
SELECT h.*
FROM v_head_to_head h
JOIN friendships f
  ON f.user_id_low  = h.user_a
 AND f.user_id_high = h.user_b;


CREATE OR REPLACE VIEW v_friend_leaderboard AS
SELECT
  u.user_id,
  COALESCE(SUM(CASE WHEN s.winner_id = u.user_id THEN s.winner_pl
                    WHEN s.loser_id  = u.user_id THEN s.loser_pl
               END),0)                                            AS total_pl,
  COUNT(s.bet_id)                                                AS total_bets,
  COUNT(*) FILTER (WHERE s.winner_id = u.user_id)                AS wins,
  COUNT(*) FILTER (WHERE s.loser_id  = u.user_id)                AS losses
FROM public.users u
LEFT JOIN core.bets_settlements s
       ON u.user_id IN (s.created_by, s.accepted_by)
GROUP BY u.user_id;

CREATE OR REPLACE VIEW v_friend_leaderboard_among_friends AS
WITH my_friends AS (
  SELECT user_id_low  AS me, user_id_high AS friend_id FROM friendships
  UNION ALL
  SELECT user_id_high AS me, user_id_low  AS friend_id FROM friendships
),
scores AS (
  SELECT * FROM v_friend_leaderboard
)
SELECT mf.me,
       s.user_id AS friend_id,
       s.total_pl, s.total_bets, s.wins, s.losses
FROM my_friends mf
JOIN scores s ON s.user_id = mf.friend_id;

CREATE OR REPLACE VIEW v_friend_requests_pending AS
SELECT
  r.request_id,
  r.requester_id,
  r.recipient_id,
  r.created_at,
  CASE WHEN r.recipient_id = u.user_id THEN 'INCOMING' ELSE 'OUTGOING' END AS direction
FROM friend_requests r
JOIN public.users u ON u.user_id IN (r.requester_id, r.recipient_id)
WHERE r.status = 'PENDING';

CREATE OR REPLACE VIEW v_friends_feed AS
WITH fe AS (
  SELECT user_id, friend_id FROM v_friends_expanded
)
SELECT fe.user_id,
       s.bet_id,
       s.created_by,
       s.accepted_by,
       s.winner_id,
       s.loser_id,
       s.amount,
       s.winner_pl,
       s.loser_pl,
       s.settled_at
FROM fe
JOIN core.bets_settlements s
  ON s.created_by = fe.friend_id OR s.accepted_by = fe.friend_id
ORDER BY settled_at DESC;