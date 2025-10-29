CREATE TYPE transaction_type AS ENUM (
  'DEPOSIT',
  'WITHDRAWAL', 
  'WAGER_PLACED',
  'WAGER_ACCEPTED',
  'PAYOUT',
  'REFUND'
);

CREATE TYPE reputation_reason AS ENUM (
  'BET_WON',
  'BET_LOST',
  'ARBITER_FULFILLED',
  'ARBITER_ABANDONED',
  'BET_DISPUTED',
  'BET_COMPLETED',
  'RELIABLE_ACTIVITY',
  'NEGATIVE_BEHAVIOR'
);

CREATE TYPE achievement_type AS ENUM (
  'WIN_STREAK_5',
  'WIN_STREAK_10',
  'FIRST_BET',
  'RISK_TAKER',
  'HIGH_ROLLER',
  'PERFECT_ARBITER',
  'SOCIAL_BUTTERFLY',
  'LUCKY_STREAK',
  'CONSISTENT_WINNER'
);


-- Users Table: Core user account information
CREATE TABLE users (
  user_id BIGSERIAL PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  email VARCHAR(100) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  display_name VARCHAR(100),
  profile_picture_url VARCHAR(255),
  bio TEXT,
  wallet_balance NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (wallet_balance >= 0),
  reputation_score INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  is_admin BOOLEAN NOT NULL DEFAULT FALSE,
  two_factor_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  two_factor_secret VARCHAR(32),
  CONSTRAINT username_length CHECK (LENGTH(username) >= 3),
  CONSTRAINT email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Transactions Table: Financial activity log
CREATE TABLE Transactions (
  transaction_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  bet_id BIGINT REFERENCES direct_bets(bet_id) ON DELETE SET NULL,
  transaction_type transaction_type NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  balance_before NUMERIC(12,2) NOT NULL,
  balance_after NUMERIC(12,2) NOT NULL,
  description TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT amount_not_zero CHECK (amount != 0)
);

-- Reputation Logs Table: Track reputation changes
CREATE TABLE Reputation_Logs (
  log_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  bet_id BIGINT REFERENCES direct_bets(bet_id) ON DELETE SET NULL,
  reputation_change INT NOT NULL,
  previous_score INT NOT NULL,
  new_score INT NOT NULL,
  reason reputation_reason NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Achievements Table: User achievements and badges
CREATE TABLE Achievements (
  achievement_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  achievement_type achievement_type NOT NULL,
  achievement_name VARCHAR(100) NOT NULL,
  achievement_description TEXT,
  badge_icon_url VARCHAR(255),
  earned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_displayed BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT unique_user_achievement UNIQUE (user_id, achievement_type)
);

-- User Statistics Table: Aggregate betting statistics
CREATE TABLE User_Statistics (
  stat_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT UNIQUE NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  total_bets_proposed INT NOT NULL DEFAULT 0,
  total_bets_accepted INT NOT NULL DEFAULT 0,
  total_bets_won INT NOT NULL DEFAULT 0,
  total_bets_lost INT NOT NULL DEFAULT 0,
  total_bets_arbitrated INT NOT NULL DEFAULT 0,
  total_profit_loss NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  total_wagered NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  current_win_streak INT NOT NULL DEFAULT 0,
  longest_win_streak INT NOT NULL DEFAULT 0,
  arbiter_accuracy_rate NUMERIC(5,2) NOT NULL DEFAULT 0.00,
  last_bet_date TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT accuracy_range CHECK (arbiter_accuracy_rate >= 0 AND arbiter_accuracy_rate <= 100)
);

-- User Sessions Table: Track active sessions for security
CREATE TABLE User_Sessions (
  session_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  session_token VARCHAR(255) UNIQUE NOT NULL,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Password Reset Tokens Table
CREATE TABLE Password_Reset_Tokens (
  token_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  token VARCHAR(255) UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  CONSTRAINT one_active_token_per_user UNIQUE (user_id, used_at) 
    DEFERRABLE INITIALLY DEFERRED
);

-- Email Verification Tokens Table
CREATE TABLE Email_Verification_Tokens (
  token_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  token VARCHAR(255) UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  verified_at TIMESTAMPTZ
);

-- User Preferences Table: Store user settings
CREATE TABLE User_Preferences (
  preference_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT UNIQUE NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  email_notifications BOOLEAN NOT NULL DEFAULT TRUE,
  push_notifications BOOLEAN NOT NULL DEFAULT TRUE,
  bet_notifications BOOLEAN NOT NULL DEFAULT TRUE,
  friend_notifications BOOLEAN NOT NULL DEFAULT TRUE,
  marketing_emails BOOLEAN NOT NULL DEFAULT FALSE,
  theme VARCHAR(20) NOT NULL DEFAULT 'light' CHECK (theme IN ('light', 'dark', 'auto')),
  language VARCHAR(5) NOT NULL DEFAULT 'en',
  timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
  currency VARCHAR(3) NOT NULL DEFAULT 'USD',
  privacy_profile VARCHAR(20) NOT NULL DEFAULT 'public' CHECK (privacy_profile IN ('public', 'friends', 'private')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- Users indexes
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_created_at ON users(created_at DESC);
CREATE INDEX idx_users_reputation ON users(reputation_score DESC);
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = TRUE;

-- Transactions indexes
CREATE INDEX idx_transactions_user_created ON Transactions(user_id, created_at DESC);
CREATE INDEX idx_transactions_type ON Transactions(transaction_type);
CREATE INDEX idx_transactions_bet ON Transactions(bet_id) WHERE bet_id IS NOT NULL;
CREATE INDEX idx_transactions_created ON Transactions(created_at DESC);

-- Reputation Logs indexes
CREATE INDEX idx_reputation_user_created ON Reputation_Logs(user_id, created_at DESC);
CREATE INDEX idx_reputation_reason ON Reputation_Logs(reason);

-- Achievements indexes
CREATE INDEX idx_achievements_user ON Achievements(user_id);
CREATE INDEX idx_achievements_type ON Achievements(achievement_type);
CREATE INDEX idx_achievements_earned ON Achievements(earned_at DESC);

-- User Statistics indexes
CREATE INDEX idx_stats_wins ON User_Statistics(total_bets_won DESC);
CREATE INDEX idx_stats_profit ON User_Statistics(total_profit_loss DESC);
CREATE INDEX idx_stats_volume ON User_Statistics(total_wagered DESC);
CREATE INDEX idx_stats_arbiter_accuracy ON User_Statistics(arbiter_accuracy_rate DESC);

-- Sessions indexes
CREATE INDEX idx_sessions_user ON User_Sessions(user_id);
CREATE INDEX idx_sessions_token ON User_Sessions(session_token);
CREATE INDEX idx_sessions_expires ON User_Sessions(expires_at);

-- Reset tokens indexes
CREATE INDEX idx_reset_tokens_user ON Password_Reset_Tokens(user_id);
CREATE INDEX idx_reset_tokens_expires ON Password_Reset_Tokens(expires_at);

-- Verification tokens indexes
CREATE INDEX idx_verify_tokens_user ON Email_Verification_Tokens(user_id);




-- Function: Update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION fn_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Update Users.updated_at on modification
CREATE TRIGGER trg_users_update_timestamp
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

-- Trigger: Update User_Statistics.updated_at on modification
CREATE TRIGGER trg_stats_update_timestamp
BEFORE UPDATE ON User_Statistics
FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

-- Trigger: Update User_Preferences.updated_at on modification
CREATE TRIGGER trg_preferences_update_timestamp
BEFORE UPDATE ON User_Preferences
FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

-- Function: Automatically create user statistics entry
CREATE OR REPLACE FUNCTION fn_create_user_statistics()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO User_Statistics (user_id)
  VALUES (NEW.user_id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Create statistics when user is created
CREATE TRIGGER trg_create_user_statistics
AFTER INSERT ON users
FOR EACH ROW EXECUTE FUNCTION fn_create_user_statistics();

-- Function: Automatically create user preferences
CREATE OR REPLACE FUNCTION fn_create_user_preferences()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO User_Preferences (user_id)
  VALUES (NEW.user_id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Create preferences when user is created
CREATE TRIGGER trg_create_user_preferences
AFTER INSERT ON users
FOR EACH ROW EXECUTE FUNCTION fn_create_user_preferences();

-- Function: Validate wallet balance on transaction
CREATE OR REPLACE FUNCTION fn_validate_transaction()
RETURNS TRIGGER AS $$
BEGIN
  -- Ensure balance_after matches calculation
  IF NEW.balance_after != NEW.balance_before + NEW.amount THEN
    RAISE EXCEPTION 'Transaction balance mismatch: before=%, amount=%, after=%', 
      NEW.balance_before, NEW.amount, NEW.balance_after;
  END IF;
  
  -- Ensure balance doesn't go negative
  IF NEW.balance_after < 0 THEN
    RAISE EXCEPTION 'Transaction would result in negative balance: %', NEW.balance_after;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Validate transactions before insert
CREATE TRIGGER trg_validate_transaction
BEFORE INSERT ON Transactions
FOR EACH ROW EXECUTE FUNCTION fn_validate_transaction();

-- Function: Update wallet balance from transaction
CREATE OR REPLACE FUNCTION fn_update_wallet_from_transaction()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE users
  SET wallet_balance = NEW.balance_after,
      updated_at = NOW()
  WHERE user_id = NEW.user_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Sync wallet balance with transactions
CREATE TRIGGER trg_update_wallet_from_transaction
AFTER INSERT ON Transactions
FOR EACH ROW EXECUTE FUNCTION fn_update_wallet_from_transaction();

-- Function: Update reputation score from log
CREATE OR REPLACE FUNCTION fn_update_reputation_from_log()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE users
  SET reputation_score = NEW.new_score,
      updated_at = NOW()
  WHERE user_id = NEW.user_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Sync reputation score with logs
CREATE TRIGGER trg_update_reputation_from_log
AFTER INSERT ON Reputation_Logs
FOR EACH ROW EXECUTE FUNCTION fn_update_reputation_from_log();

-- Function: Clean expired sessions
CREATE OR REPLACE FUNCTION fn_clean_expired_sessions()
RETURNS void AS $$
BEGIN
  DELETE FROM User_Sessions
  WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- Function: Clean expired reset tokens
CREATE OR REPLACE FUNCTION fn_clean_expired_tokens()
RETURNS void AS $$
BEGIN
  DELETE FROM Password_Reset_Tokens
  WHERE expires_at < NOW() AND used_at IS NULL;
  
  DELETE FROM Email_Verification_Tokens
  WHERE expires_at < NOW() AND verified_at IS NULL;
END;
$$ LANGUAGE plpgsql;



-- View: User public profile (safe for public display)
CREATE OR REPLACE VIEW v_user_public_profile AS
SELECT 
  u.user_id,
  u.username,
  u.display_name,
  u.profile_picture_url,
  u.location,
  u.bio,
  u.reputation_score,
  u.created_at,
  s.total_bets_won,
  s.total_bets_lost,
  s.total_profit_loss,
  s.current_win_streak,
  s.longest_win_streak,
  s.arbiter_accuracy_rate
FROM users u
LEFT JOIN User_Statistics s ON s.user_id = u.user_id
WHERE u.is_active = TRUE;

-- View: User transaction history summary
CREATE OR REPLACE VIEW v_user_transaction_summary AS
SELECT
  user_id,
  transaction_type,
  COUNT(*) AS transaction_count,
  SUM(amount) AS total_amount,
  MIN(created_at) AS first_transaction,
  MAX(created_at) AS last_transaction
FROM Transactions
GROUP BY user_id, transaction_type;

-- View: Active sessions per user
CREATE OR REPLACE VIEW v_active_sessions AS
SELECT
  s.user_id,
  u.username,
  u.email,
  COUNT(*) AS active_session_count,
  MAX(s.last_activity_at) AS most_recent_activity
FROM User_Sessions s
JOIN users u ON u.user_id = s.user_id
WHERE s.expires_at > NOW()
GROUP BY s.user_id, u.username, u.email;

-- View: Leaderboard (top users by various metrics)
CREATE OR REPLACE VIEW v_leaderboard AS
SELECT
  u.user_id,
  u.username,
  u.display_name,
  u.profile_picture_url,
  u.reputation_score,
  s.total_bets_won,
  s.total_bets_lost,
  s.total_profit_loss,
  s.total_wagered,
  s.current_win_streak,
  s.longest_win_streak,
  CASE 
    WHEN (s.total_bets_won + s.total_bets_lost) > 0 
    THEN ROUND((s.total_bets_won::NUMERIC / (s.total_bets_won + s.total_bets_lost) * 100), 2)
    ELSE 0 
  END AS win_rate,
  ROW_NUMBER() OVER (ORDER BY s.total_profit_loss DESC) AS rank_by_profit,
  ROW_NUMBER() OVER (ORDER BY s.total_bets_won DESC) AS rank_by_wins,
  ROW_NUMBER() OVER (ORDER BY u.reputation_score DESC) AS rank_by_reputation
FROM users u
JOIN User_Statistics s ON s.user_id = u.user_id
WHERE u.is_active = TRUE
ORDER BY s.total_profit_loss DESC;




-- Function: Get user balance (with row lock for transactions)
CREATE OR REPLACE FUNCTION fn_get_user_balance(p_user_id BIGINT, p_lock BOOLEAN DEFAULT FALSE)
RETURNS NUMERIC AS $$
DECLARE
  v_balance NUMERIC;
BEGIN
  IF p_lock THEN
    SELECT wallet_balance INTO v_balance
    FROM users
    WHERE user_id = p_user_id
    FOR UPDATE;
  ELSE
    SELECT wallet_balance INTO v_balance
    FROM users
    WHERE user_id = p_user_id;
  END IF;
  
  RETURN COALESCE(v_balance, 0);
END;
$$ LANGUAGE plpgsql;

-- Function: Record a transaction (atomic)
CREATE OR REPLACE FUNCTION fn_record_transaction(
  p_user_id BIGINT,
  p_type transaction_type,
  p_amount NUMERIC,
  p_bet_id BIGINT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_balance_before NUMERIC;
  v_balance_after NUMERIC;
  v_transaction_id BIGINT;
BEGIN
  -- Lock the user row and get current balance
  SELECT wallet_balance INTO v_balance_before
  FROM users
  WHERE user_id = p_user_id
  FOR UPDATE;
  
  IF v_balance_before IS NULL THEN
    RAISE EXCEPTION 'User % not found', p_user_id;
  END IF;
  
  -- Calculate new balance
  v_balance_after := v_balance_before + p_amount;
  
  -- Prevent negative balance
  IF v_balance_after < 0 THEN
    RAISE EXCEPTION 'Insufficient funds: current=%, amount=%, result=%', 
      v_balance_before, p_amount, v_balance_after;
  END IF;
  
  -- Insert transaction record
  INSERT INTO Transactions (
    user_id, 
    bet_id, 
    transaction_type, 
    amount, 
    balance_before, 
    balance_after, 
    description,
    metadata
  )
  VALUES (
    p_user_id,
    p_bet_id,
    p_type,
    p_amount,
    v_balance_before,
    v_balance_after,
    p_description,
    p_metadata
  )
  RETURNING transaction_id INTO v_transaction_id;
  
  RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql;

-- Function: Update reputation with log
CREATE OR REPLACE FUNCTION fn_update_reputation(
  p_user_id BIGINT,
  p_change INT,
  p_reason reputation_reason,
  p_bet_id BIGINT DEFAULT NULL,
  p_description TEXT DEFAULT NULL
)
RETURNS void AS $$
DECLARE
  v_previous_score INT;
  v_new_score INT;
BEGIN
  -- Get current reputation
  SELECT reputation_score INTO v_previous_score
  FROM users
  WHERE user_id = p_user_id
  FOR UPDATE;
  
  IF v_previous_score IS NULL THEN
    RAISE EXCEPTION 'User % not found', p_user_id;
  END IF;
  
  -- Calculate new score (don't go below 0)
  v_new_score := GREATEST(0, v_previous_score + p_change);
  
  -- Log the change
  INSERT INTO Reputation_Logs (
    user_id,
    bet_id,
    reputation_change,
    previous_score,
    new_score,
    reason,
    description
  )
  VALUES (
    p_user_id,
    p_bet_id,
    p_change,
    v_previous_score,
    v_new_score,
    p_reason,
    p_description
  );
  
  -- Trigger will update the Users table
END;
$$ LANGUAGE plpgsql;

-- Function: Award achievement
CREATE OR REPLACE FUNCTION fn_award_achievement(
  p_user_id BIGINT,
  p_achievement_type achievement_type,
  p_name VARCHAR(100),
  p_description TEXT DEFAULT NULL,
  p_badge_url VARCHAR(255) DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_achievement_id BIGINT;
BEGIN
  INSERT INTO Achievements (
    user_id,
    achievement_type,
    achievement_name,
    achievement_description,
    badge_icon_url
  )
  VALUES (
    p_user_id,
    p_achievement_type,
    p_name,
    p_description,
    p_badge_url
  )
  ON CONFLICT (user_id, achievement_type) DO NOTHING
  RETURNING achievement_id INTO v_achievement_id;
  
  RETURN v_achievement_id;
END;
$$ LANGUAGE plpgsql;