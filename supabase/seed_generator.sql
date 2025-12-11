-- Comprehensive Seed Data Generator for 8Ball Markets
-- Generates ~100 users, bets, support tickets, friends, etc.
-- All passwords: "Password"
-- 6 specific users get 2500 wallet balance

-- Clear existing data
TRUNCATE TABLE ticket_messages CASCADE;
TRUNCATE TABLE support_tickets CASCADE;
TRUNCATE TABLE Comments CASCADE;
TRUNCATE TABLE Bet_Threads CASCADE;
TRUNCATE TABLE friends CASCADE;
TRUNCATE TABLE friend_requests CASCADE;
TRUNCATE TABLE bet_audit_log CASCADE;
TRUNCATE TABLE bet_ledger_links CASCADE;
TRUNCATE TABLE ledger_postings CASCADE;
TRUNCATE TABLE ledger_transactions CASCADE;
TRUNCATE TABLE direct_bets CASCADE;
TRUNCATE TABLE Transactions CASCADE;
TRUNCATE TABLE users CASCADE;

-- Insert the 6 specific users first
INSERT INTO users (username, email, password_hash, wallet_balance, reputation_score, is_active, is_admin) VALUES
('alainfornes', 'alain@8ball.com', 'Password', 2500.00, 100, true, true),
('carlospenzini', 'carlos@8ball.com', 'Password', 2500.00, 150, true, false),
('lukashorvat', 'lukas@8ball.com', 'Password', 2500.00, 180, true, false),
('leolanfra', 'leo@8ball.com', 'Password', 2500.00, 120, true, false),
('logazizz', 'logan@8ball.com', 'Password', 2500.00, 200, true, false),
('dco', 'dco@8ball.com', 'Password', 2500.00, 90, true, false);

-- Generate ~94 additional users with firstnamelastname format
DO $$
DECLARE
  first_names TEXT[] := ARRAY[
    'james', 'mary', 'john', 'patricia', 'robert', 'jennifer', 'michael', 'linda',
    'william', 'elizabeth', 'david', 'barbara', 'richard', 'susan', 'joseph', 'jessica',
    'thomas', 'sarah', 'charles', 'karen', 'christopher', 'nancy', 'daniel', 'lisa',
    'matthew', 'betty', 'anthony', 'margaret', 'mark', 'sandra', 'donald', 'ashley',
    'steven', 'kimberly', 'paul', 'emily', 'andrew', 'donna', 'joshua', 'michelle',
    'kenneth', 'dorothy', 'kevin', 'carol', 'brian', 'amanda', 'george', 'melissa',
    'timothy', 'deborah', 'ronald', 'stephanie', 'jason', 'rebecca', 'edward', 'sharon',
    'jeffrey', 'laura', 'ryan', 'cynthia', 'jacob', 'kathleen', 'gary', 'amy',
    'nicholas', 'angela', 'eric', 'shirley', 'jonathan', 'anna', 'stephen', 'brenda',
    'larry', 'pamela', 'justin', 'emma', 'scott', 'frances', 'brandon', 'christine',
    'benjamin', 'marie', 'samuel', 'janet', 'frank', 'catherine', 'gregory', 'virginia',
    'raymond', 'maria', 'alexander', 'heather', 'patrick', 'diane', 'jack', 'julie',
    'dennis', 'joyce', 'jerry', 'victoria', 'tyler', 'kelly', 'aaron', 'christina',
    'jose', 'joan', 'henry', 'evelyn', 'adam', 'judith', 'douglas', 'megan'
  ];
  last_names TEXT[] := ARRAY[
    'smith', 'johnson', 'williams', 'brown', 'jones', 'garcia', 'miller', 'davis',
    'rodriguez', 'martinez', 'hernandez', 'lopez', 'wilson', 'anderson', 'thomas', 'taylor',
    'moore', 'jackson', 'martin', 'lee', 'thompson', 'white', 'harris', 'sanchez',
    'clark', 'ramirez', 'lewis', 'robinson', 'walker', 'young', 'allen', 'king',
    'wright', 'scott', 'torres', 'nguyen', 'hill', 'flores', 'green', 'adams',
    'nelson', 'baker', 'hall', 'rivera', 'campbell', 'mitchell', 'carter', 'roberts',
    'gomez', 'phillips', 'evans', 'turner', 'diaz', 'parker', 'cruz', 'edwards',
    'collins', 'reyes', 'stewart', 'morris', 'morales', 'murphy', 'cook', 'rogers',
    'gutierrez', 'ortiz', 'morgan', 'cooper', 'peterson', 'bailey', 'reed', 'kelly',
    'howard', 'ramos', 'kim', 'cox', 'ward', 'richardson', 'watson', 'brooks',
    'chavez', 'wood', 'james', 'bennett', 'gray', 'mendoza', 'ruiz', 'hughes',
    'price', 'alvarez', 'castillo', 'sanders', 'patel', 'myers', 'long', 'ross',
    'foster', 'jimenez', 'powell', 'jenkins', 'perry', 'russell', 'sullivan', 'bell',
    'coleman', 'butler', 'henderson', 'barnes', 'gonzales', 'fisher', 'vasquez', 'simmons'
  ];
  i INT;
  v_username TEXT;
  v_email TEXT;
  v_first_name TEXT;
  v_last_name TEXT;
  user_count INT := 94;
BEGIN
  FOR i IN 1..user_count LOOP
    -- Pick random first and last name
    v_first_name := first_names[1 + floor(random() * array_length(first_names, 1))::int];
    v_last_name := last_names[1 + floor(random() * array_length(last_names, 1))::int];
    v_username := v_first_name || v_last_name || i::TEXT; -- Add suffix to ensure uniqueness
    v_email := v_username || '@8ball.com';
    
    -- Insert user with random wallet balance between 500 and 3000
    INSERT INTO users (username, email, password_hash, wallet_balance, reputation_score, is_active, is_admin)
    VALUES (
      v_username,
      v_email,
      'Password',
      (500 + floor(random() * 2500)::int)::numeric,
      floor(random() * 300)::int,
      true,
      false
    )
    ON CONFLICT (username) DO NOTHING; -- Skip if duplicate
  END LOOP;
END $$;

-- Create initial ledger entries for all users (DEPOSIT type)
DO $$
DECLARE
  user_record RECORD;
  v_tx_id BIGINT;
BEGIN
  FOR user_record IN SELECT user_id, wallet_balance FROM users LOOP
    IF user_record.wallet_balance > 0 THEN
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES ('USD', 'REFUND', NULL, 'Initial wallet funding')
      RETURNING ledger_transactions.tx_id INTO v_tx_id;
      
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES (v_tx_id, user_record.user_id, (user_record.wallet_balance * 100)::bigint, 'AVAILABLE');
    END IF;
  END LOOP;
END $$;

-- Generate friend requests and friendships
DO $$
DECLARE
  user_ids BIGINT[];
  i INT;
  sender_id BIGINT;
  receiver_id BIGINT;
  friend_pairs INT := 200; -- ~200 friend relationships
  request_pairs INT := 50; -- ~50 pending requests
BEGIN
  -- Get array of all user IDs
  SELECT ARRAY_AGG(users.user_id) INTO user_ids FROM users;
  
  IF user_ids IS NULL OR array_length(user_ids, 1) < 2 THEN
    RAISE NOTICE 'Not enough users to create friendships';
    RETURN;
  END IF;
  
  -- Create accepted friend requests and friendships
  FOR i IN 1..friend_pairs LOOP
    sender_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    receiver_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    
    -- Make sure they're different users
    WHILE receiver_id = sender_id LOOP
      receiver_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    END LOOP;
    
    -- Insert friend request (accepted)
    INSERT INTO friend_requests (sender_id, receiver_id, status, requested_at, responded_at)
    VALUES (
      sender_id,
      receiver_id,
      'ACCEPTED',
      NOW() - (random() * INTERVAL '60 days'),
      NOW() - (random() * INTERVAL '59 days')
    )
    ON CONFLICT DO NOTHING;
    
    -- Insert friendship (bidirectional)
    INSERT INTO friends (user_id, friend_id, friended_at)
    VALUES (
      sender_id,
      receiver_id,
      NOW() - (random() * INTERVAL '59 days')
    )
    ON CONFLICT DO NOTHING;
    
    INSERT INTO friends (user_id, friend_id, friended_at)
    VALUES (
      receiver_id,
      sender_id,
      NOW() - (random() * INTERVAL '59 days')
    )
    ON CONFLICT DO NOTHING;
  END LOOP;
  
  -- Create pending friend requests
  FOR i IN 1..request_pairs LOOP
    sender_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    receiver_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    
    WHILE receiver_id = sender_id LOOP
      receiver_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    END LOOP;
    
    INSERT INTO friend_requests (sender_id, receiver_id, status, requested_at)
    VALUES (
      sender_id,
      receiver_id,
      'PENDING',
      NOW() - (random() * INTERVAL '7 days')
    )
    ON CONFLICT DO NOTHING;
  END LOOP;
END $$;

-- Generate bets (resolved, active, pending, disputed)
DO $$
DECLARE
  user_ids BIGINT[];
  bet_templates TEXT[] := ARRAY[
    'Team A will win the championship',
    'Stock price will exceed $100',
    'Movie will gross over $50M',
    'Player will score more than 20 points',
    'Company will release product by end of year',
    'Temperature will reach 90 degrees',
    'Game will have over 100K players',
    'Album will debut at number one',
    'Series will be renewed for another season',
    'Athlete will break the record',
    'Event will sell out within 24 hours',
    'Product will get 5-star rating',
    'Team will make the playoffs',
    'Price will drop below $50',
    'Score will be over 100 points',
    'Release date will be before deadline',
    'Performance will exceed expectations',
    'Metric will reach target number',
    'Outcome will favor the favorite',
    'Result will be decided by margin'
  ];
  i INT;
  proposer_id BIGINT;
  acceptor_id BIGINT;
  arbiter_id BIGINT;
  v_bet_id BIGINT;
  stake_cents INT;
  created_days_ago INT;
  accepted_days_ago INT;
  resolved_days_ago INT;
  outcome TEXT;
  status TEXT;
  total_bets INT := 500; -- Total bets to generate
  resolved_count INT := 0;
  active_count INT := 0;
  pending_count INT := 0;
  disputed_count INT := 0;
  v_tx_id BIGINT; -- For ledger transactions
  user_idx INT;
  num_users INT;
BEGIN
  -- Get array of all user IDs
  SELECT ARRAY_AGG(users.user_id) INTO user_ids FROM users;
  
  IF user_ids IS NULL OR array_length(user_ids, 1) < 3 THEN
    RAISE NOTICE 'Not enough users to create bets (need at least 3)';
    RETURN;
  END IF;
  
  num_users := array_length(user_ids, 1);
  
  -- First, ensure every user has at least 2 resolved bets (as proposer or acceptor)
  -- This guarantees all users appear on leaderboard with history
  FOR user_idx IN 1..num_users LOOP
    proposer_id := user_ids[user_idx];
    -- Pick a different user as acceptor
    acceptor_id := user_ids[1 + ((user_idx) % num_users)::int];
    WHILE acceptor_id = proposer_id LOOP
      acceptor_id := user_ids[1 + floor(random() * num_users)::int];
    END LOOP;
    -- Pick arbiter
    arbiter_id := user_ids[1 + floor(random() * num_users)::int];
    WHILE arbiter_id = proposer_id OR arbiter_id = acceptor_id LOOP
      arbiter_id := user_ids[1 + floor(random() * num_users)::int];
    END LOOP;
    
    stake_cents := (10 + floor(random() * 40)) * 100; -- $10 to $50
    created_days_ago := floor(random() * 90)::int;
    accepted_days_ago := created_days_ago - floor(random() * 5)::int;
    resolved_days_ago := accepted_days_ago - floor(random() * 10)::int;
    outcome := CASE WHEN random() < 0.1 THEN 'VOID' 
                    WHEN random() < 0.55 THEN 'PROPOSER_WIN' 
                    ELSE 'ACCEPTOR_WIN' END;
    
    -- Ensure acceptor_id is set for RESOLVED bet (safety check)
    IF acceptor_id IS NULL THEN
      -- Pick a different user as acceptor if somehow NULL
      acceptor_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
      WHILE acceptor_id = proposer_id LOOP
        acceptor_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
      END LOOP;
    END IF;
    
    -- Create resolved bet for this user - MUST have acceptor_id
    INSERT INTO direct_bets (
      proposer_id, acceptor_id, arbiter_id, event_description, status, outcome,
      stake_proposer_cents, stake_acceptor_cents, currency_code, odds_format, payout_model,
      created_at, accepted_at, resolved_at, resolved_by
    ) VALUES (
      proposer_id, acceptor_id, arbiter_id,
      bet_templates[1 + floor(random() * array_length(bet_templates, 1))::int] || ' #' || user_idx,
      'RESOLVED', outcome, stake_cents, stake_cents, 'USD', 'DECIMAL', 'EVENS',
      NOW() - (created_days_ago || ' days')::INTERVAL,
      NOW() - (accepted_days_ago || ' days')::INTERVAL,
      NOW() - (resolved_days_ago || ' days')::INTERVAL,
      arbiter_id
    ) RETURNING direct_bets.bet_id INTO v_bet_id;
    
    -- Create ledger entries (same as in main loop below)
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES ('USD', 'HOLD', proposer_id, 'Bet creation')
    RETURNING ledger_transactions.tx_id INTO v_tx_id;
    
    INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
    VALUES (v_tx_id, proposer_id, -stake_cents, 'AVAILABLE'),
           (v_tx_id, proposer_id, stake_cents, 'HELD');
    
    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
    
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES ('USD', 'HOLD', acceptor_id, 'Bet acceptance')
    RETURNING ledger_transactions.tx_id INTO v_tx_id;
    
    INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
    VALUES (v_tx_id, acceptor_id, -stake_cents, 'AVAILABLE'),
           (v_tx_id, acceptor_id, stake_cents, 'HELD');
    
    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
    
    -- Payout
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES ('USD', 'PAYOUT', arbiter_id, 'Bet resolution')
    RETURNING ledger_transactions.tx_id INTO v_tx_id;
    
    IF outcome = 'PROPOSER_WIN' THEN
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES 
        (v_tx_id, proposer_id, -stake_cents, 'HELD'),
        (v_tx_id, proposer_id, stake_cents * 2, 'AVAILABLE'),
        (v_tx_id, acceptor_id, -stake_cents, 'HELD');
    ELSIF outcome = 'ACCEPTOR_WIN' THEN
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES 
        (v_tx_id, acceptor_id, -stake_cents, 'HELD'),
        (v_tx_id, acceptor_id, stake_cents * 2, 'AVAILABLE'),
        (v_tx_id, proposer_id, -stake_cents, 'HELD');
    ELSE -- VOID
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES 
        (v_tx_id, proposer_id, -stake_cents, 'HELD'),
        (v_tx_id, proposer_id, stake_cents, 'AVAILABLE'),
        (v_tx_id, acceptor_id, -stake_cents, 'HELD'),
        (v_tx_id, acceptor_id, stake_cents, 'AVAILABLE');
    END IF;
    
    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
  END LOOP;
  
  -- Now generate the rest of the bets randomly
  FOR i IN 1..total_bets LOOP
    proposer_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    acceptor_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    arbiter_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    
    -- Ensure all IDs are different
    WHILE acceptor_id = proposer_id LOOP
      acceptor_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    END LOOP;
    
    WHILE arbiter_id = proposer_id OR arbiter_id = acceptor_id LOOP
      arbiter_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    END LOOP;
    
    -- Use smaller stakes to avoid insufficient funds errors
    -- Use smaller stakes to avoid insufficient funds (max $50, most users have at least $500)
    stake_cents := (10 + floor(random() * 40)) * 100; -- $10 to $50
    created_days_ago := floor(random() * 90)::int; -- Within last 90 days
    
    -- Distribute bets: 60% resolved, 20% active, 15% pending, 5% disputed
    IF i <= total_bets * 0.6 THEN
      -- RESOLVED bets - MUST have an acceptor
      -- Ensure acceptor_id is set (should already be, but double-check)
      IF acceptor_id IS NULL THEN
        -- Pick a different user as acceptor if somehow NULL
        acceptor_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
        WHILE acceptor_id = proposer_id LOOP
          acceptor_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
        END LOOP;
      END IF;
      
      status := 'RESOLVED';
      accepted_days_ago := created_days_ago - floor(random() * 5)::int;
      resolved_days_ago := accepted_days_ago - floor(random() * 10)::int;
      outcome := CASE WHEN random() < 0.1 THEN 'VOID' 
                      WHEN random() < 0.55 THEN 'PROPOSER_WIN' 
                      ELSE 'ACCEPTOR_WIN' END;
      
      -- Ensure RESOLVED bets always have acceptor_id (safety check)
      INSERT INTO direct_bets (
        proposer_id, acceptor_id, arbiter_id, event_description, status, outcome,
        stake_proposer_cents, stake_acceptor_cents, currency_code, odds_format, payout_model,
        created_at, accepted_at, resolved_at, resolved_by
      ) VALUES (
        proposer_id, acceptor_id, arbiter_id,
        bet_templates[1 + floor(random() * array_length(bet_templates, 1))::int] || ' #' || i,
        status, outcome, stake_cents, stake_cents, 'USD', 'DECIMAL', 'EVENS',
        NOW() - (created_days_ago || ' days')::INTERVAL,
        NOW() - (accepted_days_ago || ' days')::INTERVAL,
        NOW() - (resolved_days_ago || ' days')::INTERVAL,
        arbiter_id
      ) RETURNING direct_bets.bet_id INTO v_bet_id;
      
      -- Create ledger entries for resolved bet
      -- This simulates the bet lifecycle: HOLD on creation, PAYOUT on resolution
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES ('USD', 'HOLD', proposer_id, 'Bet creation')
      RETURNING ledger_transactions.tx_id INTO v_tx_id;
      
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES (v_tx_id, proposer_id, -stake_cents, 'AVAILABLE'),
             (v_tx_id, proposer_id, stake_cents, 'HELD');
      
      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
      
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES ('USD', 'HOLD', acceptor_id, 'Bet acceptance')
      RETURNING ledger_transactions.tx_id INTO v_tx_id;
      
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES (v_tx_id, acceptor_id, -stake_cents, 'AVAILABLE'),
             (v_tx_id, acceptor_id, stake_cents, 'HELD');
      
      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
      
      -- Payout based on outcome
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES ('USD', 'PAYOUT', arbiter_id, 'Bet resolution')
      RETURNING ledger_transactions.tx_id INTO v_tx_id;
      
      IF outcome = 'PROPOSER_WIN' THEN
        INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
        VALUES 
          (v_tx_id, proposer_id, -stake_cents, 'HELD'),
          (v_tx_id, proposer_id, stake_cents * 2, 'AVAILABLE'),
          (v_tx_id, acceptor_id, -stake_cents, 'HELD');
      ELSIF outcome = 'ACCEPTOR_WIN' THEN
        INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
        VALUES 
          (v_tx_id, acceptor_id, -stake_cents, 'HELD'),
          (v_tx_id, acceptor_id, stake_cents * 2, 'AVAILABLE'),
          (v_tx_id, proposer_id, -stake_cents, 'HELD');
      ELSE -- VOID
        INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
        VALUES 
          (v_tx_id, proposer_id, -stake_cents, 'HELD'),
          (v_tx_id, proposer_id, stake_cents, 'AVAILABLE'),
          (v_tx_id, acceptor_id, -stake_cents, 'HELD'),
          (v_tx_id, acceptor_id, stake_cents, 'AVAILABLE');
      END IF;
      
      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
      
    ELSIF i <= total_bets * 0.8 THEN
      -- ACTIVE bets
      status := 'ACTIVE';
      accepted_days_ago := created_days_ago - floor(random() * 5)::int;
      
      INSERT INTO direct_bets (
        proposer_id, acceptor_id, arbiter_id, event_description, status,
        stake_proposer_cents, stake_acceptor_cents, currency_code, odds_format, payout_model,
        created_at, accepted_at
      ) VALUES (
        proposer_id, acceptor_id, arbiter_id,
        bet_templates[1 + floor(random() * array_length(bet_templates, 1))::int] || ' #' || i,
        status, stake_cents, stake_cents, 'USD', 'DECIMAL', 'EVENS',
        NOW() - (created_days_ago || ' days')::INTERVAL,
        NOW() - (accepted_days_ago || ' days')::INTERVAL
      ) RETURNING direct_bets.bet_id INTO v_bet_id;
      
      -- Create ledger entries for active bet (funds held)
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES ('USD', 'HOLD', proposer_id, 'Bet creation')
      RETURNING ledger_transactions.tx_id INTO v_tx_id;
      
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES (v_tx_id, proposer_id, -stake_cents, 'AVAILABLE'),
             (v_tx_id, proposer_id, stake_cents, 'HELD');
      
      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
      
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES ('USD', 'HOLD', acceptor_id, 'Bet acceptance')
      RETURNING ledger_transactions.tx_id INTO v_tx_id;
      
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES (v_tx_id, acceptor_id, -stake_cents, 'AVAILABLE'),
             (v_tx_id, acceptor_id, stake_cents, 'HELD');
      
      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
      
    ELSIF i <= total_bets * 0.95 THEN
      -- PENDING bets
      status := 'PENDING';
      
      INSERT INTO direct_bets (
        proposer_id, arbiter_id, event_description, status,
        stake_proposer_cents, currency_code, odds_format, payout_model,
        created_at
      ) VALUES (
        proposer_id, arbiter_id,
        bet_templates[1 + floor(random() * array_length(bet_templates, 1))::int] || ' #' || i,
        status, stake_cents, 'USD', 'DECIMAL', 'EVENS',
        NOW() - (created_days_ago || ' days')::INTERVAL
      ) RETURNING direct_bets.bet_id INTO v_bet_id;
      
      -- Create ledger entry for pending bet (proposer's funds held)
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES ('USD', 'HOLD', proposer_id, 'Bet creation')
      RETURNING ledger_transactions.tx_id INTO v_tx_id;
      
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES (v_tx_id, proposer_id, -stake_cents, 'AVAILABLE'),
             (v_tx_id, proposer_id, stake_cents, 'HELD');
      
      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
      
    ELSE
      -- DISPUTED bets
      status := 'DISPUTED';
      accepted_days_ago := created_days_ago - floor(random() * 5)::int;
      
      INSERT INTO direct_bets (
        proposer_id, acceptor_id, arbiter_id, event_description, status, outcome_notes,
        stake_proposer_cents, stake_acceptor_cents, currency_code, odds_format, payout_model,
        created_at, accepted_at
      ) VALUES (
        proposer_id, acceptor_id, arbiter_id,
        bet_templates[1 + floor(random() * array_length(bet_templates, 1))::int] || ' #' || i,
        status, 'Disputed outcome - requires arbiter review',
        stake_cents, stake_cents, 'USD', 'DECIMAL', 'EVENS',
        NOW() - (created_days_ago || ' days')::INTERVAL,
        NOW() - (accepted_days_ago || ' days')::INTERVAL
      ) RETURNING direct_bets.bet_id INTO v_bet_id;
      
      -- Create ledger entries for disputed bet (funds held)
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES ('USD', 'HOLD', proposer_id, 'Bet creation')
      RETURNING ledger_transactions.tx_id INTO v_tx_id;
      
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES (v_tx_id, proposer_id, -stake_cents, 'AVAILABLE'),
             (v_tx_id, proposer_id, stake_cents, 'HELD');
      
      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
      
      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES ('USD', 'HOLD', acceptor_id, 'Bet acceptance')
      RETURNING ledger_transactions.tx_id INTO v_tx_id;
      
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES (v_tx_id, acceptor_id, -stake_cents, 'AVAILABLE'),
             (v_tx_id, acceptor_id, stake_cents, 'HELD');
      
      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (v_bet_id, v_tx_id);
    END IF;
  END LOOP;
END $$;

-- Generate support tickets with messages
DO $$
DECLARE
  user_ids BIGINT[];
  v_admin_id BIGINT;
  v_user_id BIGINT;
  v_ticket_id BIGINT;
  ticket_subjects TEXT[] := ARRAY[
    'How do I deposit funds?',
    'My bet has been pending too long',
    'Can I cancel a pending bet?',
    'How does arbitration work?',
    'I want to dispute a resolved bet',
    'Account balance seems incorrect',
    'How do I add friends?',
    'Feature request: bet history',
    'Question about bet outcomes',
    'Need help with wallet',
    'Bet resolution issue',
    'Arbiter not responding',
    'Payment question',
    'Account settings help',
    'Report a problem'
  ];
  ticket_messages TEXT[] := ARRAY[
    'I need help with this issue',
    'Can someone look into this?',
    'This has been going on for a while',
    'Thanks for your help',
    'I think there might be a bug',
    'Is this normal behavior?',
    'Can you explain how this works?',
    'I would like to request a feature',
    'This is urgent please help',
    'Just wanted to follow up'
  ];
  admin_messages TEXT[] := ARRAY[
    'Thanks for reaching out! Let me look into this for you.',
    'I can help with that. Here is what you need to do...',
    'I have resolved this issue for you.',
    'This is expected behavior. Here is why...',
    'I have forwarded this to the team for review.',
    'Can you provide more details about this?',
    'I will investigate and get back to you soon.',
    'This feature is on our roadmap!',
    'I have updated your account accordingly.',
    'Thanks for the feedback!'
  ];
  i INT;
  user_id INT;
  ticket_id BIGINT;
  message_id BIGINT;
  status TEXT;
  priority TEXT;
  total_tickets INT := 80;
  days_ago INT;
BEGIN
  -- Get array of all user IDs
  SELECT ARRAY_AGG(users.user_id) INTO user_ids FROM users;
  SELECT users.user_id INTO v_admin_id FROM users WHERE username = 'alainfornes' LIMIT 1;
  
  IF user_ids IS NULL OR array_length(user_ids, 1) = 0 THEN
    RAISE NOTICE 'No users found';
    RETURN;
  END IF;
  
  FOR i IN 1..total_tickets LOOP
    v_user_id := user_ids[1 + floor(random() * array_length(user_ids, 1))::int];
    days_ago := floor(random() * 30)::int;
    
    -- Distribute status: 40% resolved, 30% open, 20% in_progress, 10% closed
    IF i <= total_tickets * 0.4 THEN
      status := 'RESOLVED';
      priority := CASE WHEN random() < 0.2 THEN 'URGENT' 
                       WHEN random() < 0.5 THEN 'HIGH' 
                       ELSE 'NORMAL' END;
    ELSIF i <= total_tickets * 0.7 THEN
      status := 'OPEN';
      priority := CASE WHEN random() < 0.15 THEN 'URGENT' 
                       WHEN random() < 0.4 THEN 'HIGH' 
                       ELSE 'NORMAL' END;
    ELSIF i <= total_tickets * 0.9 THEN
      status := 'IN_PROGRESS';
      priority := CASE WHEN random() < 0.25 THEN 'URGENT' 
                       WHEN random() < 0.5 THEN 'HIGH' 
                       ELSE 'NORMAL' END;
    ELSE
      status := 'CLOSED';
      priority := 'NORMAL';
    END IF;
    
    -- Insert ticket
    INSERT INTO support_tickets (
      user_id, subject, status, priority, created_at, updated_at, assigned_to, resolved_at
    ) VALUES (
      v_user_id,
      ticket_subjects[1 + floor(random() * array_length(ticket_subjects, 1))::int],
      status,
      priority,
      NOW() - (days_ago || ' days')::INTERVAL,
      NOW() - (days_ago || ' days')::INTERVAL + (random() * INTERVAL '2 days'),
      CASE WHEN status IN ('IN_PROGRESS', 'RESOLVED') THEN v_admin_id ELSE NULL END,
      CASE WHEN status = 'RESOLVED' THEN NOW() - (days_ago || ' days')::INTERVAL + (random() * INTERVAL '1 day') ELSE NULL END
    ) RETURNING support_tickets.ticket_id INTO v_ticket_id;
    
    -- Insert user's initial message
    INSERT INTO ticket_messages (ticket_id, author_id, message, is_internal, created_at)
    VALUES (
      v_ticket_id,
      v_user_id,
      ticket_messages[1 + floor(random() * array_length(ticket_messages, 1))::int],
      false,
      NOW() - (days_ago || ' days')::INTERVAL
    );
    
    -- If resolved or in_progress, add admin reply
    IF status IN ('RESOLVED', 'IN_PROGRESS') THEN
      INSERT INTO ticket_messages (ticket_id, author_id, message, is_internal, created_at)
      VALUES (
        v_ticket_id,
        v_admin_id,
        admin_messages[1 + floor(random() * array_length(admin_messages, 1))::int],
        false,
        NOW() - (days_ago || ' days')::INTERVAL + (random() * INTERVAL '1 day')
      );
      
      -- If resolved, maybe add user's thank you message
      IF status = 'RESOLVED' AND random() < 0.5 THEN
        INSERT INTO ticket_messages (ticket_id, author_id, message, is_internal, created_at)
        VALUES (
          v_ticket_id,
          v_user_id,
          'Thanks for your help!',
          false,
          NOW() - (days_ago || ' days')::INTERVAL + (random() * INTERVAL '12 hours')
        );
      END IF;
    END IF;
  END LOOP;
END $$;

-- Update wallet balances to match ledger (sync)
DO $$
DECLARE
  user_record RECORD;
  calculated_balance NUMERIC;
BEGIN
  FOR user_record IN SELECT users.user_id FROM users LOOP
    SELECT COALESCE(SUM(amount_cents), 0) / 100.0 INTO calculated_balance
    FROM ledger_postings
    WHERE ledger_postings.user_id = user_record.user_id AND balance_kind = 'AVAILABLE';
    
    UPDATE users SET wallet_balance = calculated_balance WHERE users.user_id = user_record.user_id;
  END LOOP;
END $$;

-- Set house user ID
INSERT INTO app_settings (key, value) VALUES ('house_user_id', '1')
ON CONFLICT (key) DO UPDATE SET value = '1';

