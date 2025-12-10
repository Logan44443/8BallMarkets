-- ============================================================================
-- Remove the direct_bets_after_insert trigger since logic is now in bet_propose
-- The trigger was creating duplicate ledger entries
-- ============================================================================

-- Drop the trigger - we don't need it anymore since bet_propose handles everything
DROP TRIGGER IF EXISTS direct_bets_after_insert ON direct_bets CASCADE;

-- Also drop the trigger function to clean up
DROP FUNCTION IF EXISTS trg_direct_bets_after_insert() CASCADE;

COMMENT ON FUNCTION bet_propose IS 'Propose a new bet and hold proposer funds immediately. All logic is in this function, no trigger needed.';

