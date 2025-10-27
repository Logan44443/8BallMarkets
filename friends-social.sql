
-- FRIENDS / SOCIAL GURU
-- PROJECT: P2P Betting Platform
-- AUTHOR: Leonardo Stocco Lanfranchi

-- What this module depends on:
-- 1. public.users(user_id)  -> used by all social tables (friends, circles, etc.)
-- 2. core.bets_settlements  -> used (read-only) for head-to-head stats & leaderboards

-- What other modules depend on this one:
-- 1. Direct Bets / Order Book -> reference social.circles(circle_id) for private bets
-- 2. Comments / Discussions   -> check social.friends & social.circle_members for visibility
-- 3. Reputation / Profiles    -> read social.head_to_head_stats & leaderboards for stats


CREATE SCHEMA IF NOT EXISTS social;
SET search_path = social, public;


-- FRIEND REQUESTS

CREATE TABLE IF NOT EXISTS social.friend_requests (
    request_id      BIGSERIAL PRIMARY KEY,
    sender_id       BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    receiver_id     BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    status          TEXT NOT NULL CHECK (status IN ('PENDING', 'ACCEPTED', 'REJECTED', 'CANCELED')),
    requested_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at    TIMESTAMPTZ,
    CHECK (sender_id <> receiver_id),
    UNIQUE (sender_id, receiver_id, status)
);


-- FRIENDSHIPS

CREATE TABLE IF NOT EXISTS social.friends (
    user_id         BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    friend_id       BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    friended_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_blocked      BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (user_id, friend_id),
    CHECK (user_id <> friend_id)
);


-- CIRCLES (PRIVATE GROUPS)

CREATE TABLE IF NOT EXISTS social.circles (
    circle_id       BIGSERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    created_by      BIGINT REFERENCES public.users(user_id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    visibility      TEXT NOT NULL CHECK (visibility IN ('PRIVATE', 'INVITE_ONLY'))
);


-- CIRCLE MEMBERSHIP

CREATE TABLE IF NOT EXISTS social.circle_members (
    circle_id       BIGINT NOT NULL REFERENCES social.circles(circle_id) ON DELETE CASCADE,
    user_id         BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    role            TEXT NOT NULL CHECK (role IN ('OWNER', 'ADMIN', 'MEMBER')),
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (circle_id, user_id)
);


-- HEAD-TO-HEAD STATS (VIEW)

CREATE OR REPLACE VIEW social.head_to_head_stats AS
SELECT
    LEAST(b.proposer_id, b.acceptor_id)           AS user_a,
    GREATEST(b.proposer_id, b.acceptor_id)        AS user_b,
    COUNT(*)                                      AS total_bets,
    SUM(CASE WHEN b.winner_id = b.proposer_id THEN 1
             WHEN b.winner_id = b.acceptor_id THEN 1
             ELSE 0 END)                          AS bets_with_decision,
    SUM(CASE WHEN b.winner_id = b.proposer_id THEN 1 ELSE 0 END) AS wins_user_a,
    SUM(CASE WHEN b.winner_id = b.acceptor_id THEN 1 ELSE 0 END) AS wins_user_b,
    SUM(CASE 
            WHEN b.winner_id = b.proposer_id THEN b.amount
            WHEN b.winner_id = b.acceptor_id THEN -b.amount
            ELSE 0 END)                           AS pnl_user_a
FROM core.bets_settlements b
GROUP BY
    LEAST(b.proposer_id, b.acceptor_id),
    GREATEST(b.proposer_id, b.acceptor_id);


-- LEADERBOARD SNAPSHOTS

CREATE TABLE IF NOT EXISTS social.leaderboards_user_daily (
    leaderboard_date DATE NOT NULL,
    user_id          BIGINT NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    total_winnings   NUMERIC(12,2) NOT NULL DEFAULT 0,
    bets_placed      INTEGER NOT NULL DEFAULT 0,
    win_streak       INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (leaderboard_date, user_id)
);
