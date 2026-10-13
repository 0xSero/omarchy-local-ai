-- One row per install per UTC day. `id` is a random number the plugin made on first run; nothing else identifies it.
CREATE TABLE pings (
  day TEXT NOT NULL CHECK (length(day) = 10),
  id TEXT NOT NULL CHECK (length(id) = 32),
  version TEXT NOT NULL,
  hw TEXT NOT NULL DEFAULT '',
  running INTEGER NOT NULL DEFAULT 0 CHECK (running >= 0),
  PRIMARY KEY (day, id)
) WITHOUT ROWID;

CREATE INDEX pings_id ON pings (id, day);
