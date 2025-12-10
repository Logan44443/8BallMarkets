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

INSERT INTO users (username, email, password_hash, wallet_balance, reputation_score, is_active, is_admin) VALUES
('alainfornes', 'alain@8ball.com', 'Password', 0, 100, true, true),
('carlospenzini', 'carlos@8ball.com', 'Password', 0, 150, true, false),
('leolanfra', 'leo@8ball.com', 'Password', 0, 120, true, false),
('logazizz', 'logan@8ball.com', 'Password', 0, 200, true, false),
('lukashorvat', 'lukas@8ball.com', 'Password', 0, 180, true, false),
('dco', 'dco@8ball.com', 'Password', 0, 90, true, false),
('theodeguy', 'theo@8ball.com', 'Password', 0, 160, true, false),
('diegorizzi', 'diego@8ball.com', 'Password', 0, 140, true, false);

DO $$
DECLARE
  tx BIGINT;
BEGIN
  INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
  VALUES ('USD', 'REFUND', NULL, 'Initial wallet funding')
  RETURNING tx_id INTO tx;
  
  INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind) VALUES
    (tx, 1, 285000, 'AVAILABLE'),
    (tx, 2, 175000, 'AVAILABLE'),
    (tx, 3, 142000, 'AVAILABLE'),
    (tx, 4, 320000, 'AVAILABLE'),
    (tx, 5, 95000, 'AVAILABLE'),
    (tx, 6, 188000, 'AVAILABLE'),
    (tx, 7, 210000, 'AVAILABLE'),
    (tx, 8, 156000, 'AVAILABLE');
END $$;

INSERT INTO friend_requests (sender_id, receiver_id, status, requested_at, responded_at) VALUES
(1, 2, 'ACCEPTED', NOW() - INTERVAL '10 days', NOW() - INTERVAL '9 days'),
(2, 3, 'ACCEPTED', NOW() - INTERVAL '8 days', NOW() - INTERVAL '7 days'),
(3, 4, 'ACCEPTED', NOW() - INTERVAL '6 days', NOW() - INTERVAL '5 days'),
(4, 5, 'ACCEPTED', NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days'),
(1, 6, 'ACCEPTED', NOW() - INTERVAL '4 days', NOW() - INTERVAL '3 days'),
(5, 7, 'ACCEPTED', NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days'),
(7, 8, 'ACCEPTED', NOW() - INTERVAL '2 days', NOW() - INTERVAL '1 day');

INSERT INTO friend_requests (sender_id, receiver_id, status, requested_at) VALUES
(6, 8, 'PENDING', NOW() - INTERVAL '12 hours'),
(2, 5, 'PENDING', NOW() - INTERVAL '8 hours'),
(8, 1, 'PENDING', NOW() - INTERVAL '4 hours');

INSERT INTO friends (user_id, friend_id, friended_at) VALUES
(1, 2, NOW() - INTERVAL '9 days'),
(2, 1, NOW() - INTERVAL '9 days'),
(2, 3, NOW() - INTERVAL '7 days'),
(3, 2, NOW() - INTERVAL '7 days'),
(3, 4, NOW() - INTERVAL '5 days'),
(4, 3, NOW() - INTERVAL '5 days'),
(4, 5, NOW() - INTERVAL '4 days'),
(5, 4, NOW() - INTERVAL '4 days'),
(1, 6, NOW() - INTERVAL '3 days'),
(6, 1, NOW() - INTERVAL '3 days'),
(5, 7, NOW() - INTERVAL '2 days'),
(7, 5, NOW() - INTERVAL '2 days'),
(7, 8, NOW() - INTERVAL '1 day'),
(8, 7, NOW() - INTERVAL '1 day');

INSERT INTO direct_bets (proposer_id, acceptor_id, arbiter_id, event_description, status, outcome, stake_proposer_cents, stake_acceptor_cents, currency_code, odds_format, payout_model, created_at, accepted_at, resolved_at, resolved_by) VALUES
(4, 2, 1, 'Duke will beat UNC in Cameron Indoor Stadium', 'RESOLVED', 'PROPOSER_WIN', 50000, 50000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '12 days', NOW() - INTERVAL '11 days', NOW() - INTERVAL '7 days', 1),
(2, 3, 4, 'Our CS316 final project will get an A', 'RESOLVED', 'PROPOSER_WIN', 25000, 25000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '10 days', NOW() - INTERVAL '9 days', NOW() - INTERVAL '5 days', 4);

INSERT INTO direct_bets (proposer_id, acceptor_id, arbiter_id, event_description, status, stake_proposer_cents, stake_acceptor_cents, currency_code, odds_format, payout_model, created_at, accepted_at) VALUES
(7, 8, 5, 'ChatGPT o1 will be released before January 2026', 'ACTIVE', 30000, 30000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '4 days', NOW() - INTERVAL '3 days');

INSERT INTO direct_bets (proposer_id, acceptor_id, arbiter_id, event_description, status, outcome_notes, stake_proposer_cents, stake_acceptor_cents, currency_code, odds_format, payout_model, created_at, accepted_at) VALUES
(6, 5, 1, 'Bitcoin will hit $100k before end of November 2025', 'DISPUTED', 'DCO says it hit $100k on Nov 28th at 11:59 PM, but Lukas argues the bet specified "by end of November" meaning market close on the 29th', 40000, 40000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '6 days', NOW() - INTERVAL '5 days');

INSERT INTO direct_bets (proposer_id, event_description, status, stake_proposer_cents, currency_code, odds_format, payout_model, created_at) VALUES
(3, 'Lakers will make playoffs this season', 'PENDING', 15000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '2 days');

INSERT INTO direct_bets (proposer_id, target_user_id, event_description, status, stake_proposer_cents, currency_code, odds_format, payout_model, created_at) VALUES
(2, 1, 'Next US president will be a Democrat', 'PENDING', 20000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '1 day');

INSERT INTO direct_bets (proposer_id, acceptor_id, arbiter_id, event_description, status, stake_proposer_cents, stake_acceptor_cents, currency_code, odds_format, payout_model, created_at, accepted_at) VALUES
(4, 2, 6, 'Golang will beat Rust in 2026 Stack Overflow survey', 'ACTIVE', 12000, 12000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days');

INSERT INTO direct_bets (proposer_id, acceptor_id, arbiter_id, event_description, status, outcome, stake_proposer_cents, stake_acceptor_cents, currency_code, odds_format, payout_model, created_at, accepted_at, resolved_at, resolved_by) VALUES
(8, 7, 3, 'It will snow in Durham before Thanksgiving', 'RESOLVED', 'PROPOSER_WIN', 18000, 18000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '15 days', NOW() - INTERVAL '14 days', NOW() - INTERVAL '8 days', 3),
(6, 3, 2, 'Panthers will win their next home game', 'RESOLVED', 'PROPOSER_WIN', 22000, 22000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '14 days', NOW() - INTERVAL '13 days', NOW() - INTERVAL '9 days', 2);

INSERT INTO direct_bets (proposer_id, event_description, status, stake_proposer_cents, currency_code, odds_format, payout_model, created_at) VALUES
(5, 'Tesla stock price will double by end of 2026', 'PENDING', 10000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '18 hours'),
(1, 'Our 8Ball Markets app will get 1000+ users by Spring 2026', 'PENDING', 50000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '6 hours');

INSERT INTO direct_bets (proposer_id, acceptor_id, arbiter_id, event_description, status, outcome, stake_proposer_cents, stake_acceptor_cents, currency_code, odds_format, payout_model, created_at, accepted_at, resolved_at, resolved_by) VALUES
(1, 6, 4, 'Supabase will add a new major feature before end of year', 'RESOLVED', 'PROPOSER_WIN', 15000, 15000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '11 days', NOW() - INTERVAL '10 days', NOW() - INTERVAL '6 days', 4),
(2, 7, 3, 'Python will remain #1 language in TIOBE Index for November', 'RESOLVED', 'PROPOSER_WIN', 12000, 12000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '20 days', NOW() - INTERVAL '19 days', NOW() - INTERVAL '15 days', 3),
(5, 2, 8, 'AWS will have a major outage before Thanksgiving', 'RESOLVED', 'PROPOSER_WIN', 18000, 18000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '18 days', NOW() - INTERVAL '17 days', NOW() - INTERVAL '13 days', 8),
(7, 3, 1, 'SpaceX will launch Starship successfully in November', 'RESOLVED', 'PROPOSER_WIN', 20000, 20000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '16 days', NOW() - INTERVAL '15 days', NOW() - INTERVAL '12 days', 1),
(8, 5, 2, 'Next iPhone will have USB-C instead of Lightning', 'RESOLVED', 'PROPOSER_WIN', 10000, 10000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '22 days', NOW() - INTERVAL '21 days', NOW() - INTERVAL '18 days', 2),
(4, 8, 6, 'Microsoft will acquire another gaming company in 2025', 'RESOLVED', 'PROPOSER_WIN', 30000, 30000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '25 days', NOW() - INTERVAL '24 days', NOW() - INTERVAL '20 days', 6),
(3, 6, 5, 'Meta will rebrand again before 2026', 'RESOLVED', 'PROPOSER_WIN', 8000, 8000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '28 days', NOW() - INTERVAL '27 days', NOW() - INTERVAL '23 days', 5),
(6, 1, 7, 'GitHub Copilot will support more than 20 languages by end of year', 'RESOLVED', 'PROPOSER_WIN', 25000, 25000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '30 days', NOW() - INTERVAL '29 days', NOW() - INTERVAL '25 days', 7),
(2, 4, 1, 'OpenAI will release GPT-5 before end of 2025', 'RESOLVED', 'PROPOSER_WIN', 35000, 35000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '32 days', NOW() - INTERVAL '31 days', NOW() - INTERVAL '27 days', 1),
(1, 3, 8, 'Next.js 15 will be released before December', 'RESOLVED', 'PROPOSER_WIN', 10000, 10000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '35 days', NOW() - INTERVAL '34 days', NOW() - INTERVAL '30 days', 8),
(5, 7, 4, 'Nvidia stock will reach $500 by end of November', 'RESOLVED', 'PROPOSER_WIN', 15000, 15000, 'USD', 'DECIMAL', 'EVENS', NOW() - INTERVAL '38 days', NOW() - INTERVAL '37 days', NOW() - INTERVAL '33 days', 4);

INSERT INTO Bet_Threads (bet_id, visibility) VALUES (3, 'PRIVATE'), (4, 'PRIVATE'), (7, 'PRIVATE');

INSERT INTO Comments (thread_id, author_id, body, created_at) VALUES
(1, 7, 'I''ve been following OpenAI closely, they''re definitely dropping o1 soon', NOW() - INTERVAL '3 days'),
(1, 8, 'You''re too optimistic. They always delay these releases', NOW() - INTERVAL '3 days' + INTERVAL '1 hour'),
(1, 7, 'Bet accepted! We''ll see who knows AI better 😎', NOW() - INTERVAL '2 days'),
(1, 8, 'May the best predictor win! Lukas will keep us honest', NOW() - INTERVAL '2 days' + INTERVAL '30 minutes'),
(2, 6, 'BTC just hit $100,200 on Nov 28th at 11:59 PM! I win!!! 🚀', NOW() - INTERVAL '2 days'),
(2, 5, 'Hold on... the bet said "by end of November" which means market close on the 29th. That spike doesn''t count.', NOW() - INTERVAL '2 days' + INTERVAL '30 minutes'),
(2, 6, 'Dude, "end of November" means before December 1st. The price hit it.', NOW() - INTERVAL '2 days' + INTERVAL '1 hour'),
(2, 5, 'The bet specified "by end of November" which in trading terms means the final market close. I''m disputing this.', NOW() - INTERVAL '2 days' + INTERVAL '2 hours'),
(2, 6, 'Fine, let Alain decide as admin. The screenshot doesn''t lie.', NOW() - INTERVAL '2 days' + INTERVAL '3 hours'),
(3, 4, 'Golang is taking over. Rust is overhyped', NOW() - INTERVAL '4 days'),
(3, 2, 'Bold take! I''ll take that bet. Rust is the future', NOW() - INTERVAL '4 days' + INTERVAL '2 hours'),
(3, 4, 'Stack Overflow doesn''t lie. Go is more practical', NOW() - INTERVAL '3 days'),
(3, 2, 'We''ll see what the devs say in 2026 😤', NOW() - INTERVAL '3 days' + INTERVAL '1 hour');

INSERT INTO support_tickets (user_id, subject, status, priority, created_at, updated_at) VALUES
(5, 'How do I add more funds to my wallet?', 'OPEN', 'NORMAL', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days');

INSERT INTO ticket_messages (ticket_id, author_id, message, is_internal, created_at) VALUES
(1, 5, 'Hey team! Is there a way to deposit more money? I want to make some bigger bets', false, NOW() - INTERVAL '3 days');

INSERT INTO support_tickets (user_id, subject, status, priority, created_at, updated_at, assigned_to) VALUES
(3, 'My bet has been active for too long', 'IN_PROGRESS', 'HIGH', NOW() - INTERVAL '2 days', NOW() - INTERVAL '8 hours', 1);

INSERT INTO ticket_messages (ticket_id, author_id, message, is_internal, created_at) VALUES
(2, 3, 'I have a bet that''s been active for over a week and the arbiter hasn''t resolved it yet. Can admins help?', false, NOW() - INTERVAL '2 days'),
(2, 1, 'Hi Leo! I''m taking a look. Which bet ID is this?', false, NOW() - INTERVAL '1 day' + INTERVAL '18 hours'),
(2, 3, 'I think it was the Lakers playoff bet. The game already happened', false, NOW() - INTERVAL '1 day' + INTERVAL '12 hours'),
(2, 1, 'Found it. I''ve pinged the arbiter. If they don''t respond soon, I can resolve it as admin.', false, NOW() - INTERVAL '8 hours');

INSERT INTO support_tickets (user_id, subject, status, priority, created_at, updated_at, resolved_at, assigned_to) VALUES
(6, 'How does arbiter selection work?', 'RESOLVED', 'NORMAL', NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days' + INTERVAL '1 hour', NOW() - INTERVAL '6 days' + INTERVAL '1 hour', 1);

INSERT INTO ticket_messages (ticket_id, author_id, message, is_internal, created_at) VALUES
(3, 6, 'When I create a bet, how do I choose who the arbiter is? Is it automatic?', false, NOW() - INTERVAL '6 days'),
(3, 1, 'Great question! When creating a bet, you can search for and select any user as an arbiter. Choose someone both parties trust!', false, NOW() - INTERVAL '6 days' + INTERVAL '30 minutes'),
(3, 6, 'Perfect, that makes sense. Thanks Alain!', false, NOW() - INTERVAL '6 days' + INTERVAL '50 minutes');

INSERT INTO support_tickets (user_id, subject, status, priority, created_at, updated_at) VALUES
(7, 'Can I dispute a bet after it''s resolved?', 'OPEN', 'NORMAL', NOW() - INTERVAL '12 hours', NOW() - INTERVAL '12 hours');

INSERT INTO ticket_messages (ticket_id, author_id, message, is_internal, created_at) VALUES
(4, 7, 'One of my bets got resolved but I think the arbiter made a mistake. Can I dispute it after resolution?', false, NOW() - INTERVAL '12 hours');

INSERT INTO support_tickets (user_id, subject, status, priority, created_at, updated_at, assigned_to) VALUES
(8, 'Feature Request: Bet history graphs', 'OPEN', 'NORMAL', NOW() - INTERVAL '8 hours', NOW() - INTERVAL '8 hours', 1);

INSERT INTO ticket_messages (ticket_id, author_id, message, is_internal, created_at) VALUES
(5, 8, 'It would be cool to see a graph of our profit/loss over time on the profile page. Just a suggestion!', false, NOW() - INTERVAL '8 hours');

INSERT INTO app_settings (key, value) VALUES ('house_user_id', '1');
