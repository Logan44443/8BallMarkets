/**User Table**/
CREATE TABLE Users (
    user_id INT PRIMARY KEY UNIQUE NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(100),
    profile_picture_url VARCHAR(255),
    location VARCHAR(100),
    wallet_balance DECIMAL(10, 2) DEFAULT 0.00,
    reputation_score INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    INDEX idx_username (username),
    INDEX idx_email (email)
);
/**Transaction Table**/
CREATE TABLE Transactions (
    transaction_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    bet_id INT,
    transaction_type ENUM('DEPOSIT', 'WITHDRAWAL', 'WAGER_PLACED', 'WAGER_ACCEPTED', 'PAYOUT', 'REFUND') NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    balance_before DECIMAL(10, 2) NOT NULL,
    balance_after DECIMAL(10, 2) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (bet_id) REFERENCES Bets(bet_id) ON DELETE SET NULL,
    INDEX idx_user_transactions (user_id, created_at),
    INDEX idx_transaction_type (transaction_type)
);
/**Reputation Table**/
CREATE TABLE Reputation_Logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    bet_id INT,
    reputation_change INT NOT NULL,
    previous_score INT NOT NULL,
    new_score INT NOT NULL,
    reason ENUM('BET_WON', 'BET_LOST', 'ARBITER_FULFILLED', 'ARBITER_ABANDONED', 
                'BET_DISPUTED', 'BET_COMPLETED', 'RELIABLE_ACTIVITY', 'NEGATIVE_BEHAVIOR') NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (bet_id) REFERENCES Bets(bet_id) ON DELETE SET NULL,
    INDEX idx_user_reputation (user_id, created_at)
);
/**Achievements Table**/
CREATE TABLE Achievements (
    achievement_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    achievement_type ENUM('WIN_STREAK_5', 'WIN_STREAK_10', 'FIRST_BET', 'RISK_TAKER', 
                          'HIGH_ROLLER', 'PERFECT_ARBITER', 'SOCIAL_BUTTERFLY', 
                          'LUCKY_STREAK', 'CONSISTENT_WINNER') NOT NULL,
    achievement_name VARCHAR(100) NOT NULL,
    achievement_description TEXT,
    badge_icon_url VARCHAR(255),
    earned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_displayed BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    UNIQUE KEY unique_user_achievement (user_id, achievement_type),
    INDEX idx_user_achievements (user_id)
);
/**Statistics Table**/
CREATE TABLE User_Statistics (
    stat_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT UNIQUE NOT NULL,
    total_bets_proposed INT DEFAULT 0,
    total_bets_accepted INT DEFAULT 0,
    total_bets_won INT DEFAULT 0,
    total_bets_lost INT DEFAULT 0,
    total_bets_arbitrated INT DEFAULT 0,
    total_profit_loss DECIMAL(10, 2) DEFAULT 0.00,
    total_wagered DECIMAL(10, 2) DEFAULT 0.00,
    current_win_streak INT DEFAULT 0,
    longest_win_streak INT DEFAULT 0,
    arbiter_accuracy_rate DECIMAL(5, 2) DEFAULT 0.00,
    last_bet_date TIMESTAMP NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    INDEX idx_leaderboard_wins (total_bets_won DESC),
    INDEX idx_leaderboard_profit (total_profit_loss DESC),
    INDEX idx_leaderboard_volume (total_wagered DESC),
    INDEX idx_arbiter_accuracy (arbiter_accuracy_rate DESC)
);
/**
NEED TO ADD:
BET TABLE THAT REFERENCES BET GURU
