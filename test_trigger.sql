-- Test query to check if trigger is working
-- Check if ledger entries exist for bet_id 28

-- Check if trigger exists
SELECT trigger_name, event_manipulation, event_object_table 
FROM information_schema.triggers 
WHERE event_object_table = 'direct_bets' 
  AND trigger_name LIKE '%insert%';

-- Check ledger entries for bet 28
SELECT 
  lt.tx_id,
  lt.tx_type,
  lt.memo,
  lp.user_id,
  lp.amount_cents,
  lp.balance_kind
FROM ledger_transactions lt
JOIN ledger_postings lp ON lt.tx_id = lp.tx_id
WHERE lt.tx_id IN (
  SELECT tx_id FROM bet_ledger_links WHERE bet_id = 28
)
ORDER BY lt.tx_id, lp.balance_kind;

-- Check user's current ledger balance
SELECT 
  user_id,
  balance_kind,
  SUM(amount_cents) as total_cents
FROM ledger_postings
WHERE user_id = 1
GROUP BY user_id, balance_kind
ORDER BY balance_kind;

-- Check user's wallet_balance
SELECT user_id, username, wallet_balance 
FROM users 
WHERE user_id = 1;

