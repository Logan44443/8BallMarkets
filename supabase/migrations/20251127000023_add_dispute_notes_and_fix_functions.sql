-- Add separate dispute_notes column and update dispute/resolve functions
-- This separates dispute notes from resolution notes for better clarity

-- Add dispute_notes column to direct_bets
ALTER TABLE direct_bets 
  ADD COLUMN IF NOT EXISTS dispute_notes TEXT;

-- Update bet_dispute to:
-- 1. Store notes in dispute_notes (not outcome_notes)
-- 2. Add proper authorization checks
CREATE OR REPLACE FUNCTION bet_dispute(
  p_bet_id BIGINT,
  p_notes TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor BIGINT;
  admin BOOLEAN;
  db_admin BOOLEAN := FALSE;
  bet_record RECORD;
BEGIN
  -- Get actor from session context
  actor := app__current_user_id();
  admin := app__current_is_admin();
  
  -- Fallback: check database is_admin field
  IF actor IS NOT NULL THEN
    SELECT COALESCE(is_admin, FALSE) INTO db_admin
    FROM users
    WHERE user_id = actor;
  END IF;
  
  admin := admin OR db_admin;
  
  -- Get bet info to check participants and status
  SELECT proposer_id, acceptor_id, arbiter_id, status INTO bet_record
  FROM direct_bets
  WHERE bet_id = p_bet_id
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bet % not found', p_bet_id;
  END IF;
  
  -- Check bet is in valid state (must be ACTIVE to dispute)
  IF bet_record.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Bet % is in status %, cannot be disputed. Must be ACTIVE', 
      p_bet_id, bet_record.status;
  END IF;
  
  -- Check authorization: must be proposer, acceptor, arbiter, or admin
  IF NOT admin AND (
    actor IS NULL OR 
    (actor != bet_record.proposer_id AND 
     actor != bet_record.acceptor_id AND 
     (bet_record.arbiter_id IS NULL OR actor != bet_record.arbiter_id))
  ) THEN
    RAISE EXCEPTION 'Only proposer, acceptor, arbiter, or admin can DISPUTE bet %. Current actor: %', 
      p_bet_id, actor;
  END IF;
  
  -- Validate notes are provided
  IF p_notes IS NULL OR length(trim(p_notes)) = 0 THEN
    RAISE EXCEPTION 'Dispute notes are required';
  END IF;
  
  -- Update bet: set status to DISPUTED and store notes in dispute_notes
  UPDATE direct_bets
     SET status = 'DISPUTED',
         dispute_notes = p_notes
   WHERE bet_id = p_bet_id;
END $$;

-- Update bet_resolve to:
-- 1. Preserve dispute_notes (don't overwrite)
-- 2. Use outcome_notes only for resolution notes
CREATE OR REPLACE FUNCTION bet_resolve(
  p_bet_id BIGINT,
  p_outcome TEXT,
  p_notes TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor BIGINT;
  admin BOOLEAN;
  db_admin BOOLEAN := FALSE;
  bet_record RECORD;
BEGIN
  -- Get actor from session context
  actor := app__current_user_id();
  admin := app__current_is_admin();
  
  -- Fallback: check database is_admin field
  IF actor IS NOT NULL THEN
    SELECT COALESCE(is_admin, FALSE) INTO db_admin
    FROM users
    WHERE user_id = actor;
  END IF;
  
  admin := admin OR db_admin;
  
  -- Get bet info to check arbiter and status
  SELECT arbiter_id, proposer_id, acceptor_id, status INTO bet_record
  FROM direct_bets
  WHERE bet_id = p_bet_id
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bet % not found', p_bet_id;
  END IF;
  
  -- Check authorization: must be admin OR arbiter
  IF NOT admin AND (actor IS NULL OR actor != bet_record.arbiter_id) THEN
    RAISE EXCEPTION 'Only arbiter or admin can RESOLVE bet %. Current actor: %, is_admin: %, arbiter_id: %', 
      p_bet_id, actor, admin, bet_record.arbiter_id;
  END IF;
  
  -- Check bet is in valid state
  IF bet_record.status NOT IN ('ACTIVE', 'DISPUTED') THEN
    RAISE EXCEPTION 'Bet % is in status %, cannot be resolved. Must be ACTIVE or DISPUTED', 
      p_bet_id, bet_record.status;
  END IF;
  
  -- Update bet with all necessary fields
  -- Note: dispute_notes is preserved, outcome_notes is set for resolution notes
  UPDATE direct_bets
     SET status = 'RESOLVED',
         outcome = p_outcome,
         outcome_notes = p_notes,  -- Resolution notes go here
         resolved_at = COALESCE(resolved_at, NOW()),
         resolved_by = COALESCE(resolved_by, actor)
   WHERE bet_id = p_bet_id;
END $$;

COMMENT ON FUNCTION bet_dispute IS 'Dispute a bet - runs with elevated privileges. Stores notes in dispute_notes and includes authorization checks.';
COMMENT ON FUNCTION bet_resolve IS 'Resolve a bet - runs with elevated privileges. Preserves dispute_notes and uses outcome_notes for resolution notes.';


