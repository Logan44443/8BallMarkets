-- Fix bet_resolve to explicitly set resolved_by and resolved_at
-- This ensures the trigger has the necessary information even if auth context is missing

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
  UPDATE direct_bets
     SET status = 'RESOLVED',
         outcome = p_outcome,
         outcome_notes = p_notes,
         resolved_at = COALESCE(resolved_at, NOW()),
         resolved_by = COALESCE(resolved_by, actor)
   WHERE bet_id = p_bet_id;
END $$;

COMMENT ON FUNCTION bet_resolve IS 'Resolve a bet - runs with elevated privileges to manage ledger. Sets resolved_by and resolved_at explicitly.';

