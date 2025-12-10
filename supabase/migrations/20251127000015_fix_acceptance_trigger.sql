-- ============================================================================
-- Fix acceptance trigger - proposer funds already HELD, only move acceptor funds
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_direct_bets_after_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  actor BIGINT := app__current_user_id();
  admin BOOLEAN := app__current_is_admin();
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
     ACCEPTANCE: PENDING→ACTIVE
     - Proposer funds already HELD from creation
     - Only place holds for acceptor
  ----------------------- */
  IF OLD.status = 'PENDING' AND NEW.status = 'ACTIVE' THEN
    INSERT INTO ledger_transactions(currency_code, tx_type, created_by, memo)
    VALUES (NEW.currency_code, 'HOLD', actor, 'Bet accepted: place holds for acceptor')
    RETURNING tx_id INTO tx;

    -- Move funds: AVAILABLE(-) and HELD(+) for acceptor only
    -- Proposer funds already HELD from bet creation
    INSERT INTO ledger_postings(tx_id, user_id, amount_cents, balance_kind)
      VALUES
        (tx, NEW.acceptor_id, -NEW.stake_acceptor_cents, 'AVAILABLE'),
        (tx, NEW.acceptor_id,  NEW.stake_acceptor_cents, 'HELD');

    INSERT INTO bet_ledger_links(bet_id, tx_id) VALUES (NEW.bet_id, tx);

    RETURN NEW;
  END IF;

  /* ----------------------
     PRE-ACCEPT CANCELED/EXPIRED
     - Release proposer's HELD funds back to AVAILABLE
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

COMMENT ON FUNCTION trg_direct_bets_after_update() IS 
  'Manages fund movements when bet status changes. Updated to only hold acceptor funds on acceptance (proposer already held).';

