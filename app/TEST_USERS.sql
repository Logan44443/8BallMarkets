-- Test users for 8Ball Markets demo
-- Run this in Supabase Studio SQL Editor after migrations

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Temporarily disable the trigger that tries to insert into User_Statistics (table was dropped in MVP)
ALTER TABLE users DISABLE TRIGGER trg_create_user_statistics;

-- User 1: alainfornes (password: Password)
INSERT INTO users (
  username,
  email, 
  password_hash,
  display_name,
  wallet_balance,
  is_active
) VALUES (
  'alainfornes',
  'alainfornes@example.com',
  crypt('Password', gen_salt('bf')),
  'Alain Fornes',
  10000.00,
  true
);

-- User 2: carlospenzini (password: Password)
INSERT INTO users (
  username,
  email,
  password_hash,
  display_name,
  wallet_balance,
  is_active
) VALUES (
  'carlospenzini',
  'carlospenzini@example.com',
  crypt('Password', gen_salt('bf')),
  'Carlos Penzini',
  10000.00,
  true
);

-- User 3: lukashorvat (password: Password)
INSERT INTO users (
  username,
  email,
  password_hash,
  display_name,
  wallet_balance,
  is_active
) VALUES (
  'lukashorvat',
  'lukashorvat@example.com',
  crypt('Password', gen_salt('bf')),
  'Lukas Horvat',
  10000.00,
  true
);

-- Re-enable the trigger
ALTER TABLE users ENABLE TRIGGER trg_create_user_statistics;

-- Show created users
SELECT user_id, username, email, wallet_balance FROM users;
