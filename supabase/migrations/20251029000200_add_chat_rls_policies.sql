-- Disable RLS on chat tables for MVP (using localStorage auth, not Supabase auth)
-- In production, you would enable RLS and create proper policies

ALTER TABLE Bet_Threads DISABLE ROW LEVEL SECURITY;
ALTER TABLE Comments DISABLE ROW LEVEL SECURITY;

-- For production, you would use policies like:
-- CREATE POLICY "Users can view threads for their bets" ON Bet_Threads FOR SELECT ...
-- But for MVP with localStorage auth, we disable RLS entirely

