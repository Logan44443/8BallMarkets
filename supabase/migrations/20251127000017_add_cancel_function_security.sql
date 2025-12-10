-- Add SECURITY DEFINER to bet_cancel_or_expire function
-- This allows the function to properly trigger the update that releases funds

DROP FUNCTION IF EXISTS bet_cancel_or_expire CASCADE;

CREATE OR REPLACE FUNCTION bet_cancel_or_expire(
  p_bet_id BIGINT,
  p_new_status TEXT  -- must be 'CANCELED' or 'EXPIRED'
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE s TEXT; 
BEGIN
  IF p_new_status NOT IN ('CANCELED','EXPIRED') THEN
    RAISE EXCEPTION 'Invalid terminal status %', p_new_status;
  END IF;
  SELECT status INTO s FROM direct_bets WHERE bet_id = p_bet_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bet % not found', p_bet_id;
  END IF;
  IF s <> 'PENDING' THEN
    RAISE EXCEPTION 'Only PENDING bets can be %', p_new_status;
  END IF;
  UPDATE direct_bets SET status = p_new_status WHERE bet_id = p_bet_id;
END $$;

COMMENT ON FUNCTION bet_cancel_or_expire IS 'Cancel or expire a pending bet - runs with elevated privileges to trigger fund release';

