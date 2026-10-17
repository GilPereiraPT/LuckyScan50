CREATE TABLE draws (
  draw_date DATE PRIMARY KEY,
  numbers SMALLINT[] NOT NULL CHECK (cardinality(numbers) = 5),
  stars SMALLINT[] NOT NULL CHECK (cardinality(stars) = 2),
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE prize_breakdowns (
  draw_date DATE NOT NULL REFERENCES draws(draw_date),
  tier SMALLINT NOT NULL CHECK (tier BETWEEN 1 AND 13),
  prize_amount_eur NUMERIC(14,2),
  winners INTEGER,
  PRIMARY KEY (draw_date,tier)
);
