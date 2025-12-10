-- Fix admin check in trigger to also check database is_admin field
-- This ensures admins who unlock via password can resolve bets

CREATE OR REPLACE FUNCTION trg_direct_bets_before_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  actor BIGINT := app__current_user_id();
  admin BOOLEAN := app__current_is_admin();
  db_admin BOOLEAN := FALSE;
BEGIN
  -- Also check database is_admin field as fallback
  -- This handles cases where session variable might not be set properly
  IF actor IS NOT NULL THEN
    SELECT COALESCE(is_admin, FALSE) INTO db_admin
    FROM users
    WHERE user_id = actor;
  END IF;
  
  -- Use either session variable OR database value
  admin := admin OR db_admin;

  /* -- Accepting a bet: acceptor_id transitions from NULL to NOT NULL */
  IF TG_OP = 'UPDATE'
     AND OLD.acceptor_id IS NULL
     AND NEW.acceptor_id IS NOT NULL THEN

    IF NEW.stake_acceptor_cents IS NULL OR NEW.stake_acceptor_cents <= 0 THEN
      RAISE EXCEPTION 'stake_acceptor_cents must be > 0 when accepting';
    END IF;

    IF NEW.currency_code <> OLD.currency_code THEN
      RAISE EXCEPTION 'currency_code cannot change on acceptance';
    END IF;

    -- ODDS model guardrails at accept time (DECIMAL odds only for now)
    IF COALESCE(NEW.payout_model,'EVENS') = 'ODDS' THEN
      IF NEW.odds_format <> 'DECIMAL' THEN
        RAISE EXCEPTION 'For payout_model=ODDS, odds_format must be DECIMAL';
      END IF;
      IF NEW.odds_acceptor IS NULL OR NEW.odds_acceptor <= 1.0 THEN
        RAISE EXCEPTION 'odds_acceptor must be > 1.0 for ODDS';
      END IF;
      IF NEW.odds_proposer IS NULL OR NEW.odds_proposer <= 1.0 THEN
        RAISE EXCEPTION 'odds_proposer must be > 1.0 for ODDS';
      END IF;
    END IF;

    -- freeze core terms right at accept time
    IF NEW.stake_proposer_cents <> OLD.stake_proposer_cents
       OR NEW.odds_format <> OLD.odds_format
       OR NEW.odds_proposer <> OLD.odds_proposer
       OR NEW.event_description <> OLD.event_description
       OR NEW.payout_model <> OLD.payout_model
       OR NEW.fee_bps <> OLD.fee_bps
       OR COALESCE(NEW.odds_acceptor, OLD.odds_acceptor) <> COALESCE(OLD.odds_acceptor, NEW.odds_acceptor)
    THEN
      RAISE EXCEPTION 'Terms are immutable upon acceptance';
    END IF;

    NEW.accepted_at := NOW();
    NEW.status := 'ACTIVE';
  END IF;

  /* -- Currency cannot change after acceptance */
  IF OLD.acceptor_id IS NOT NULL AND NEW.currency_code <> OLD.currency_code THEN
    RAISE EXCEPTION 'currency_code cannot change after acceptance';
  END IF;

  /* -- Status transition rules & authorization */
  IF NEW.status <> OLD.status THEN
    CASE OLD.status
      WHEN 'PENDING' THEN
        IF NEW.status NOT IN ('PENDING','ACTIVE','CANCELED','EXPIRED') THEN
          RAISE EXCEPTION 'Invalid transition from PENDING to %', NEW.status;
        END IF;
        IF NEW.status = 'ACTIVE' AND NEW.acceptor_id IS NULL THEN
          RAISE EXCEPTION 'Cannot set ACTIVE without an acceptor';
        END IF;

      WHEN 'ACTIVE' THEN
        IF NEW.status NOT IN ('ACTIVE','RESOLVED','DISPUTED','CANCELED','EXPIRED') THEN
          RAISE EXCEPTION 'Invalid transition from ACTIVE to %', NEW.status;
        END IF;

        IF NEW.status = 'RESOLVED' THEN
          IF NEW.outcome IS NULL THEN
            RAISE EXCEPTION 'Outcome must be set to resolve';
          END IF;
          NEW.resolved_at := COALESCE(NEW.resolved_at, NOW());
          IF NOT (admin OR (actor IS NOT NULL AND actor = NEW.arbiter_id)) THEN
            RAISE EXCEPTION 'Only arbiter or admin can RESOLVE';
          END IF;
          NEW.resolved_by := COALESCE(NEW.resolved_by, actor);
        END IF;

        IF NEW.status = 'DISPUTED' THEN
          IF NEW.outcome_notes IS NULL OR length(trim(NEW.outcome_notes)) = 0 THEN
            RAISE EXCEPTION 'Outcome notes required to open a dispute';
          END IF;
          IF NOT (admin OR actor IN (NEW.proposer_id, NEW.acceptor_id, NEW.arbiter_id)) THEN
            RAISE EXCEPTION 'Only parties or arbiter/admin can DISPUTE';
          END IF;
        END IF;

      WHEN 'DISPUTED' THEN
        IF NEW.status NOT IN ('DISPUTED','ACTIVE','RESOLVED','CANCELED') THEN
          RAISE EXCEPTION 'Invalid transition from DISPUTED to %', NEW.status;
        END IF;

        IF NEW.status = 'RESOLVED' THEN
          IF NEW.outcome IS NULL THEN
            RAISE EXCEPTION 'Outcome must be set to resolve from DISPUTED';
          END IF;
          NEW.resolved_at := COALESCE(NEW.resolved_at, NOW());
          IF NOT (admin OR (actor IS NOT NULL AND actor = NEW.arbiter_id)) THEN
            RAISE EXCEPTION 'Only arbiter or admin can RESOLVE a dispute';
          END IF;
          NEW.resolved_by := COALESCE(NEW.resolved_by, actor);
        END IF;

      WHEN 'RESOLVED','CANCELED','EXPIRED' THEN
        IF NEW.status <> OLD.status THEN
          RAISE EXCEPTION 'Terminal state % is immutable', OLD.status;
        END IF;

      ELSE
        RAISE EXCEPTION 'Unknown previous status %', OLD.status;
    END CASE;
  END IF;

  /* -- Terms become immutable after acceptance */
  IF OLD.acceptor_id IS NOT NULL THEN
    IF NEW.stake_proposer_cents <> OLD.stake_proposer_cents
       OR NEW.stake_acceptor_cents <> OLD.stake_acceptor_cents
       OR NEW.odds_acceptor <> OLD.odds_acceptor
       OR NEW.payout_model <> OLD.payout_model
       OR NEW.fee_bps <> OLD.fee_bps
    THEN
      RAISE EXCEPTION 'Stake/odds/fee fields are immutable after acceptance';
    END IF;
  END IF;

  RETURN NEW;
END $$;

