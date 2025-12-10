-- ============================================================================
-- Hold funds when bet is created (not just when accepted)
-- ============================================================================
-- This ensures proposers can't over-commit funds by creating multiple bets
-- Funds are held immediately when bet is created, and released if bet is canceled

-- Trigger function to hold funds when bet is created
CREATE OR REPLACE FUNCTION trg_direct_bets_after_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  actor BIGINT := app__current_user_id();
  tx BIGINT;
  available_balance_cents BIGINT;
BEGIN
  -- When a bet is created in PENDING status, hold the proposer's funds
  IF NEW.status = 'PENDING' THEN
    -- Check if proposer has enough available balance
    SELECT COALESCE(SUM(CASE WHEN balance_kind='AVAILABLE' THEN amount_cents ELSE 0 END), 0)
    INTO available_balance_cents
    FROM ledger_postings
    WHERE user_id = NEW.proposer_id;
    
    -- If no ledger entries exist, check wallet_balance (for initial setup)
    IF available_balance_cents = 0 THEN
      SELECT (wallet_balance * 100)::BIGINT
      INTO available_balance_cents
      FROM users
      WHERE user_id = NEW.proposer_id;
    END IF;
    
    -- Check if user has enough funds
    IF available_balance_cents < NEW.stake_proposer_cents THEN
      RAISE EXCEPTION 'Insufficient funds. Available: $%, Required: $%',
        (available_balance_cents / 100.0)::NUMERIC(12,2),
        (NEW.stake_proposer_cents / 100.0)::NUMERIC(12,2);
    END IF;
    
    -- Create ledger transaction to hold funds
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES (NEW.currency_code, 'HOLD', COALESCE(actor, NEW.proposer_id), 
            'Bet proposed: hold proposer funds')
    RETURNING tx_id INTO tx;
    
    -- Move funds from AVAILABLE to HELD for proposer
    INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
    VALUES
      (tx, NEW.proposer_id, -NEW.stake_proposer_cents, 'AVAILABLE'),
      (tx, NEW.proposer_id,  NEW.stake_proposer_cents, 'HELD');
    
    -- Link transaction to bet
    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);
  END IF;
  
  RETURN NEW;
END $$;

-- Create trigger on INSERT
DROP TRIGGER IF EXISTS direct_bets_after_insert ON direct_bets;
CREATE TRIGGER direct_bets_after_insert
AFTER INSERT ON direct_bets
FOR EACH ROW
EXECUTE FUNCTION trg_direct_bets_after_insert();

-- Update the existing after_update trigger to release funds when PENDING bet is canceled/expired
CREATE OR REPLACE FUNCTION trg_direct_bets_after_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  actor BIGINT := app__current_user_id();
  tx BIGINT;
BEGIN
  /* -- Always write a human-friendly audit record with before/after snapshots */
  INSERT INTO bet_audit_log(bet_id, actor_id, action, details)
  VALUES (NEW.bet_id, actor, 'UPDATE',
          jsonb_build_object('from', to_jsonb(OLD), 'to', to_jsonb(NEW)));

  /* -- OPTIONAL notifications for your async worker / websocket layer */
  PERFORM pg_notify('bets_changed', json_build_object(
    'bet_id', NEW.bet_id, 'old_status', OLD.status, 'new_status', NEW.status
  )::text);

  /* ----------------------
     PRE-ACCEPT CANCELED/EXPIRED
     - Release HELD funds back to AVAILABLE for proposer
  ----------------------- */
  IF OLD.status = 'PENDING' AND NEW.status IN ('CANCELED','EXPIRED') THEN
    -- Release the proposer's held funds
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES (NEW.currency_code, 'RELEASE', COALESCE(actor, NEW.proposer_id), 
            'Bet canceled/expired: release proposer holds')
    RETURNING tx_id INTO tx;
    
    INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
    VALUES
      (tx, NEW.proposer_id, -NEW.stake_proposer_cents, 'HELD'),
      (tx, NEW.proposer_id,  NEW.stake_proposer_cents, 'AVAILABLE');
    
    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);
    
    PERFORM pg_notify('bets_canceled_or_expired', NEW.bet_id::text);
    RETURN NEW;
  END IF;

  /* ----------------------
     ACCEPTANCE: PENDING→ACTIVE
     - place holds for acceptor (proposer already has funds HELD)
  ----------------------- */
  IF OLD.status = 'PENDING' AND NEW.status = 'ACTIVE' THEN
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES (NEW.currency_code, 'HOLD', actor, 'Bet accepted: place holds for acceptor')
    RETURNING tx_id INTO tx;

    -- Move funds: AVAILABLE(-) and HELD(+) for acceptor
    -- Proposer funds already HELD from creation, so we only move acceptor's funds
    INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
    VALUES
      (tx, NEW.acceptor_id, -NEW.stake_acceptor_cents, 'AVAILABLE'),
      (tx, NEW.acceptor_id,  NEW.stake_acceptor_cents, 'HELD');

    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);

    RETURN NEW;
  END IF;

  /* ----------------------
     RESOLUTION: ACTIVE/DISPUTED → RESOLVED
     - 1) RELEASE both HELD balances back to AVAILABLE
     - 2) Compute winnings by model, apply fee, move funds to winner & house
  ----------------------- */
  IF NEW.status = 'RESOLVED' AND OLD.status IN ('ACTIVE','DISPUTED') THEN
    /* 1) RELEASE both HELD balances back to AVAILABLE */
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES (NEW.currency_code, 'RELEASE', NEW.resolved_by, 'Bet resolved: release holds')
    RETURNING tx_id INTO tx;

    INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES
        (tx, NEW.proposer_id, -NEW.stake_proposer_cents, 'HELD'),
        (tx, NEW.proposer_id,  NEW.stake_proposer_cents, 'AVAILABLE'),
        (tx, NEW.acceptor_id, -NEW.stake_acceptor_cents, 'HELD'),
        (tx, NEW.acceptor_id,  NEW.stake_acceptor_cents, 'AVAILABLE');

    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);

    -- VOID: nothing else to move after releasing holds
    IF NEW.outcome = 'VOID' THEN
      PERFORM pg_notify('bets_resolved_void', NEW.bet_id::text);
      RETURN NEW;
    END IF;

    /* 2) Compute winnings, fees, and move net money (winner gains, loser pays, house gets fee) */
    DECLARE
      winner_id BIGINT;
      loser_id  BIGINT;
      stake_winner BIGINT;
      stake_loser  BIGINT;
      winnings BIGINT;
      fee BIGINT := 0;
      house BIGINT := app__house_user_id();
      odds NUMERIC(10,4);
    BEGIN
      IF NEW.outcome = 'PROPOSER_WIN' THEN
        winner_id := NEW.proposer_id; loser_id := NEW.acceptor_id;
        stake_winner := NEW.stake_proposer_cents; stake_loser := NEW.stake_acceptor_cents;
        odds := CASE WHEN NEW.payout_model='ODDS' THEN NEW.odds_proposer ELSE NULL END;
      ELSE
        winner_id := NEW.acceptor_id; loser_id := NEW.proposer_id;
        stake_winner := NEW.stake_acceptor_cents; stake_loser := NEW.stake_proposer_cents;
        odds := CASE WHEN NEW.payout_model='ODDS' THEN NEW.odds_acceptor ELSE NULL END;
      END IF;

      IF COALESCE(NEW.payout_model,'EVENS') = 'EVENS' THEN
        winnings := stake_loser;  -- classic even-money transfer
      ELSE
        -- ODDS: decimal odds already validated > 1.0; cap by opponent stake
        winnings := LEAST( FLOOR(stake_winner * (odds - 1.0)), stake_loser );
      END IF;

      -- Fee on winnings
      IF NEW.fee_bps > 0 THEN
        fee := (winnings * NEW.fee_bps) / 10000;  -- integer division floors
      END IF;

      INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
      VALUES (NEW.currency_code, 'PAYOUT', NEW.resolved_by, 'Bet resolved: transfer winnings and fee')
      RETURNING tx_id INTO tx;

      -- Winner gets winnings minus fee; loser pays full winnings; house gets fee
      INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind) VALUES
        (tx, winner_id, winnings - fee, 'AVAILABLE'),
        (tx, loser_id,  -winnings,      'AVAILABLE');

      IF fee > 0 THEN
        INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
        VALUES (tx, house, fee, 'AVAILABLE');
      END IF;

      INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);
    END;

    PERFORM pg_notify('bets_resolved', NEW.bet_id::text);
    RETURN NEW;
  END IF;

  /* ----------------------
     DISPUTED: audit/notify only (funds remain HELD)
  ----------------------- */
  IF NEW.status = 'DISPUTED' AND OLD.status = 'ACTIVE' THEN
    PERFORM pg_notify('bets_disputed', NEW.bet_id::text);
    RETURN NEW;
  END IF;

  RETURN NEW;
END $$;

COMMENT ON FUNCTION trg_direct_bets_after_insert() IS 
  'Holds proposer funds when bet is created in PENDING status';
  
COMMENT ON FUNCTION trg_direct_bets_after_update() IS 
  'Manages fund movements when bet status changes (updated to release funds on cancel/expire)';

