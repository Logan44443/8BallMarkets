-- Schema
CREATE TYPE txn_type AS ENUM (
  'DEPOSIT',
  'WITHDRAWAL',
  'WAGER_HOLD',
  'WAGER_RELEASE',
  'WAGER_PAYOUT',
  'FEE'
);

CREATE TABLE account_balance (
  uid BIGINT PRIMARY KEY,
  balance_cents BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ledger (
  id BIGSERIAL PRIMARY KEY,
  uid BIGINT NOT NULL,
  type txn_type NOT NULL,
  amount_cents BIGINT NOT NULL,
  related_id TEXT,
  idempotency_key TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (uid) REFERENCES account_balance(uid)
);

CREATE INDEX idx_ledger_uid_created ON ledger(uid, created_at DESC);

-- Deposit
BEGIN;
  INSERT INTO ledger(uid, type, amount_cents, related_id, idempotency_key)
  VALUES ($user, 'DEPOSIT', $amount, $ref, $key)
  ON CONFLICT (idempotency_key) DO NOTHING;

  INSERT INTO account_balance(uid) VALUES ($user)
  ON CONFLICT (uid) DO NOTHING;

  UPDATE account_balance
  SET balance_cents = balance_cents + $amount, updated_at = now()
  WHERE uid = $user;
COMMIT;

-- Withdraw
BEGIN;
  SELECT balance_cents FROM account_balance WHERE uid = $user FOR UPDATE;

  DO $$
  BEGIN
    IF (SELECT balance_cents FROM account_balance WHERE uid = $user) < $amount THEN
      RAISE EXCEPTION 'insufficient funds';
    END IF;
  END$$;

  INSERT INTO ledger(uid, type, amount_cents, related_id, idempotency_key)
  VALUES ($user, 'WITHDRAWAL', -$amount, $ref, $key);

  UPDATE account_balance
  SET balance_cents = balance_cents - $amount, updated_at = now()
  WHERE uid = $user;
COMMIT;

-- Direct Bet Settlement
BEGIN;
  SELECT balance_cents FROM account_balance
  WHERE uid IN ($loser, $winner)
  ORDER BY uid FOR UPDATE;

  DO $$
  BEGIN
    IF (SELECT balance_cents FROM account_balance WHERE uid = $loser) < $payout THEN
      RAISE EXCEPTION 'insufficient funds to settle';
    END IF;
  END$$;

  INSERT INTO ledger(uid, type, amount_cents, related_id)
  VALUES 
    ($loser,  'WAGER_PAYOUT', -$payout, $bet_id),
    ($winner, 'WAGER_PAYOUT',  $payout,  $bet_id);

  UPDATE account_balance SET balance_cents = balance_cents - $payout, updated_at = now() WHERE uid = $loser;
  UPDATE account_balance SET balance_cents = balance_cents + $payout, updated_at = now() WHERE uid = $winner;
COMMIT;

-- History
SELECT id, type, amount_cents, related_id, created_at
FROM ledger
WHERE uid = $user
ORDER BY created_at DESC
LIMIT $limit OFFSET $offset;

-- Audit Check
SELECT a.uid,
       a.balance_cents AS stored,
       COALESCE(SUM(l.amount_cents),0) AS recomputed,
       a.balance_cents - COALESCE(SUM(l.amount_cents),0) AS diff
FROM account_balance a
LEFT JOIN ledger l ON l.uid = a.uid
GROUP BY a.uid, a.balance_cents
HAVING a.balance_cents <> COALESCE(SUM(l.amount_cents),0);

-- Transactions

-- 0) Safety: balance table (no-op if it already exists)
CREATE TABLE IF NOT EXISTS account_balance (
  uid BIGINT PRIMARY KEY,
  balance_cents BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1) Minimal sign enforcement for deposits/withdrawals
CREATE OR REPLACE FUNCTION fn_assert_basic_signs()
RETURNS trigger AS $$
BEGIN
  IF NEW.type = 'DEPOSIT' AND NEW.amount_cents <= 0 THEN
    RAISE EXCEPTION 'DEPOSIT must be positive';
  END IF;

  IF NEW.type = 'WITHDRAWAL' AND NEW.amount_cents >= 0 THEN
    RAISE EXCEPTION 'WITHDRAWAL must be negative';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_assert_basic_signs ON ledger;
CREATE TRIGGER trg_assert_basic_signs
BEFORE INSERT ON ledger
FOR EACH ROW EXECUTE FUNCTION fn_assert_basic_signs();

-- 2) Single source of truth: apply ledger deltas to account_balance
CREATE OR REPLACE FUNCTION fn_apply_ledger_to_balance()
RETURNS trigger AS $$
BEGIN
  -- Upsert and add the delta atomically
  INSERT INTO account_balance(uid, balance_cents, updated_at)
  VALUES (NEW.uid, NEW.amount_cents, NOW())
  ON CONFLICT (uid) DO UPDATE
    SET balance_cents = account_balance.balance_cents + EXCLUDED.balance_cents,
        updated_at    = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_apply_ledger ON ledger;
CREATE TRIGGER trg_apply_ledger
AFTER INSERT ON ledger
FOR EACH ROW EXECUTE FUNCTION fn_apply_ledger_to_balance();

-- 3) Tiny API: deposit / withdraw (use these instead of manual inserts)
CREATE OR REPLACE FUNCTION fn_deposit(p_uid BIGINT, p_amount BIGINT, p_ref TEXT DEFAULT NULL)
RETURNS BIGINT AS $$
DECLARE v_id BIGINT;
BEGIN
  -- Must be positive; trigger enforces sign
  INSERT INTO ledger(uid, type, amount_cents, related_id)
  VALUES (p_uid, 'DEPOSIT', p_amount, p_ref)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_withdraw(p_uid BIGINT, p_amount BIGINT, p_ref TEXT DEFAULT NULL)
RETURNS BIGINT AS $$
DECLARE v_id BIGINT;
BEGIN
  -- Must be negative; trigger enforces sign
  INSERT INTO ledger(uid, type, amount_cents, related_id)
  VALUES (p_uid, 'WITHDRAWAL', -p_amount, p_ref)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$ LANGUAGE plpgsql;
