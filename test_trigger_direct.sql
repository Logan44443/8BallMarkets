-- Test if trigger exists and is attached
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE event_object_table = 'direct_bets'
  AND trigger_name LIKE '%insert%';

-- Check the function exists
SELECT 
  routine_name,
  routine_type,
  security_type
FROM information_schema.routines
WHERE routine_name = 'trg_direct_bets_after_insert';

-- Try to manually test the trigger by checking if it would work
-- First, let's see what the latest bet looks like
SELECT bet_id, proposer_id, status, stake_proposer_cents, created_at
FROM direct_bets
WHERE bet_id = 29;

