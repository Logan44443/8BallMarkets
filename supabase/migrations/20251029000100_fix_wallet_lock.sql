-- Fix the wallet guard to not use FOR SHARE on grouped view
-- Instead, just check the balance without locking (simpler for MVP)

CREATE OR REPLACE FUNCTION trg_ledger_postings_before_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE cur_avail BIGINT; BEGIN
  -- Only guard AVAILABLE debits (amount_cents < 0)
  IF NEW.balance_kind = 'AVAILABLE' AND NEW.amount_cents < 0 THEN
    SELECT COALESCE(available_cents,0)
      INTO cur_avail
      FROM wallet_balances
     WHERE user_id = NEW.user_id;
     -- Removed FOR SHARE - can't use with GROUP BY in view

    IF cur_avail + NEW.amount_cents < 0 THEN
      RAISE EXCEPTION 'Insufficient AVAILABLE funds for user %', NEW.user_id;
    END IF;
  END IF;
  RETURN NEW;
END $$;

