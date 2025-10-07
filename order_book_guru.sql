CREATE TYPE order_status AS ENUM ('OPEN','PARTIAL','MATCHED','CANCELED','EXPIRED');
CREATE TYPE order_side AS ENUM ('YES','NO','OVER','UNDER');

CREATE TABLE Order_Book (
  order_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
  event_id BIGINT NOT NULL,
  side order_side NOT NULL,
  odds NUMERIC(10,4) NOT NULL CHECK (odds > 0),
  stake_amount NUMERIC(12,2) NOT NULL CHECK (stake_amount > 0),
  filled_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (filled_amount >= 0),
  status order_status NOT NULL DEFAULT 'OPEN',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_order_user_status ON Order_Book(user_id, status);
CREATE INDEX idx_order_event_side ON Order_Book(event_id, side);
CREATE INDEX idx_order_created_at ON Order_Book(created_at DESC);

CREATE TABLE Order_Matches (
  match_id BIGSERIAL PRIMARY KEY,
  buy_order_id BIGINT NOT NULL REFERENCES Order_Book(order_id) ON DELETE CASCADE,
  sell_order_id BIGINT NOT NULL REFERENCES Order_Book(order_id) ON DELETE CASCADE,
  matched_amount NUMERIC(12,2) NOT NULL CHECK (matched_amount > 0),
  matched_odds NUMERIC(10,4) NOT NULL CHECK (matched_odds > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  bet_id BIGINT REFERENCES Bets(bet_id) ON DELETE SET NULL
);

CREATE INDEX idx_match_orders ON Order_Matches(buy_order_id, sell_order_id);
CREATE INDEX idx_match_created ON Order_Matches(created_at DESC);

CREATE OR REPLACE FUNCTION fn_touch_order_book()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_touch_order_book
BEFORE UPDATE ON Order_Book
FOR EACH ROW EXECUTE FUNCTION fn_touch_order_book();

CREATE OR REPLACE FUNCTION fn_check_fill_amount()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.filled_amount > NEW.stake_amount THEN
    RAISE EXCEPTION 'filled_amount cannot exceed stake_amount';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_fill_amount
BEFORE INSERT OR UPDATE ON Order_Book
FOR EACH ROW EXECUTE FUNCTION fn_check_fill_amount();
