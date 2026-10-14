-- 6.15.0: whether a model has ever answered on the install, and how many times it started, failed to start, opened an
-- agent and downloaded a model since its previous ping. Totals only: never which model, agent or folder.
ALTER TABLE pings ADD COLUMN launched INTEGER NOT NULL DEFAULT 0 CHECK (launched IN (0, 1));
ALTER TABLE pings ADD COLUMN started INTEGER NOT NULL DEFAULT 0 CHECK (started >= 0);
ALTER TABLE pings ADD COLUMN failed INTEGER NOT NULL DEFAULT 0 CHECK (failed >= 0);
ALTER TABLE pings ADD COLUMN opened INTEGER NOT NULL DEFAULT 0 CHECK (opened >= 0);
ALTER TABLE pings ADD COLUMN downloaded INTEGER NOT NULL DEFAULT 0 CHECK (downloaded >= 0);
