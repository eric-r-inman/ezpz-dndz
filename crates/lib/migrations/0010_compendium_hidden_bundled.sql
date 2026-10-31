-- The bundled creatures a user has cleared from their library.  The
-- bundled set ships in the binary.  Hiding one is the only way a user
-- can take it out of their list.  A compendium reset empties the set.

-- Wire: none.  `POST /api/compendium/keep` writes the set and
-- `GET /api/compendium/creatures` leaves its creatures out.
CREATE TABLE compendium_hidden_bundled (
  user_id     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  creature_id TEXT NOT NULL,
  PRIMARY KEY (user_id, creature_id)
);
