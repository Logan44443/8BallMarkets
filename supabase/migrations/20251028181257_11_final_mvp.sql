-- Final MVP cleanup: Keep ONLY what's needed for basic betting demo

-- Drop Order Book (focus on direct bets only for MVP)
DROP TABLE IF EXISTS Order_Matches CASCADE;
DROP TABLE IF EXISTS Order_Book CASCADE;

-- Drop Support system (not needed for MVP demo)
DROP TABLE IF EXISTS Ticket_Messages CASCADE;
DROP TABLE IF EXISTS Support_Tickets CASCADE;

-- Drop Comments (not needed for MVP - add later)
DROP TABLE IF EXISTS Comments CASCADE;
DROP TABLE IF EXISTS Bet_Threads CASCADE;

-- Drop Friends (not needed for MVP - add later)
DROP TABLE IF EXISTS friends CASCADE;
DROP TABLE IF EXISTS friend_requests CASCADE;

-- MVP now focuses on: users, direct_bets, and the bet ledger system

