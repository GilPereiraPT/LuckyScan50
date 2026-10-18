CREATE TABLE IF NOT EXISTS draws (
 id INTEGER PRIMARY KEY, game TEXT NOT NULL, draw_id TEXT NOT NULL,
 draw_date TEXT NOT NULL, status TEXT NOT NULL, source_url TEXT NOT NULL,
 retrieved_at TEXT NOT NULL, updated_at TEXT NOT NULL, revision INTEGER NOT NULL,
 payload TEXT NOT NULL, fingerprint TEXT NOT NULL, UNIQUE(game,draw_id)
);
CREATE INDEX IF NOT EXISTS draws_date ON draws(draw_date,game);
CREATE TABLE IF NOT EXISTS draw_numbers (
 draw_id INTEGER NOT NULL REFERENCES draws(id), kind TEXT NOT NULL,
 position INTEGER NOT NULL, value INTEGER NOT NULL,
 PRIMARY KEY(draw_id,kind,position)
);
CREATE TABLE IF NOT EXISTS prize_tiers (
 draw_id INTEGER NOT NULL REFERENCES draws(id), tier INTEGER NOT NULL,
 main_matches INTEGER NOT NULL, star_matches INTEGER NOT NULL,
 amount_cents INTEGER, winners_portugal INTEGER, winners_total INTEGER,
 PRIMARY KEY(draw_id,tier)
);
CREATE TABLE IF NOT EXISTS milhao_results (
 draw_id INTEGER PRIMARY KEY REFERENCES draws(id), winning_code TEXT NOT NULL,
 amount_cents INTEGER
);
CREATE TABLE IF NOT EXISTS revisions (
 sequence INTEGER PRIMARY KEY AUTOINCREMENT,
 draw_id INTEGER NOT NULL REFERENCES draws(id), revision INTEGER NOT NULL,
 payload TEXT NOT NULL, fingerprint TEXT NOT NULL, imported_at TEXT NOT NULL,
 UNIQUE(draw_id,revision)
);
CREATE TABLE IF NOT EXISTS import_log (
 id INTEGER PRIMARY KEY, imported_at TEXT NOT NULL, source TEXT NOT NULL,
 changed INTEGER NOT NULL, unchanged INTEGER NOT NULL
);
PRAGMA user_version=1;
