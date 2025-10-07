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