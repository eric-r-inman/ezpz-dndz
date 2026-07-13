-- Users and dice-roll history, plus the schema_meta key/value table
-- that one-shot migrations use to record completion markers.
--
-- Portability rules (this file runs unchanged on SQLite and
-- PostgreSQL): TEXT primary keys holding UUID strings, BIGINT for
-- every integer (SQLite gives it INTEGER affinity; PostgreSQL's
-- plain INTEGER is 32-bit and would overflow millisecond
-- timestamps), BIGINT 0/1 for booleans, DOUBLE PRECISION for floats
-- (REAL affinity on SQLite), and no backend-specific types.

CREATE TABLE users (
  id            TEXT PRIMARY KEY,
  email         TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  display_name  TEXT NOT NULL,
  created_at    BIGINT NOT NULL
);

CREATE TABLE schema_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- One row per persisted roll.  The scalar columns mirror the Elm
-- encoder in frontend/src/Dice.elm (encodeRoll): kind, formula,
-- total, timestamp (millis), the expression's constant and nullable
-- damageType, and the optional source {feature, target}.  A NULL
-- source_feature means the entry carried no source object at all;
-- a NULL source_target inside a present source means target: null.
-- timestamp_ms is NULLable because the server historically accepted
-- opaque entries without one.  position is a per-user insertion
-- sequence; newest rolls have the highest position.
CREATE TABLE dice_rolls (
  id                      TEXT PRIMARY KEY,
  user_id                 TEXT NOT NULL
                            REFERENCES users (id) ON DELETE CASCADE,
  position                BIGINT NOT NULL,
  kind                    TEXT NOT NULL,
  formula                 TEXT NOT NULL,
  total                   BIGINT NOT NULL,
  timestamp_ms            BIGINT,
  expression_constant     BIGINT NOT NULL,
  expression_damage_type  TEXT,
  source_feature          TEXT,
  source_target           TEXT
);

CREATE INDEX idx_dice_rolls_user_position
  ON dice_rolls (user_id, position);

-- The expression's requested dice terms ({count, faces, sign}),
-- ordered by position within the roll.
CREATE TABLE dice_roll_expression_dice (
  roll_id   TEXT NOT NULL
              REFERENCES dice_rolls (id) ON DELETE CASCADE,
  position  BIGINT NOT NULL,
  die_count BIGINT NOT NULL,
  die_faces BIGINT NOT NULL,
  die_sign  TEXT NOT NULL,
  PRIMARY KEY (roll_id, position)
);

-- One row per rolled group: the group's dice term plus its subtotal.
-- The individual rolled faces live in dice_roll_faces.
CREATE TABLE dice_roll_groups (
  id        TEXT PRIMARY KEY,
  roll_id   TEXT NOT NULL
              REFERENCES dice_rolls (id) ON DELETE CASCADE,
  position  BIGINT NOT NULL,
  die_count BIGINT NOT NULL,
  die_faces BIGINT NOT NULL,
  die_sign  TEXT NOT NULL,
  subtotal  BIGINT NOT NULL
);

CREATE INDEX idx_dice_roll_groups_roll
  ON dice_roll_groups (roll_id, position);

CREATE TABLE dice_roll_faces (
  group_id TEXT NOT NULL
             REFERENCES dice_roll_groups (id) ON DELETE CASCADE,
  position BIGINT NOT NULL,
  face     BIGINT NOT NULL,
  kept     BIGINT NOT NULL,
  PRIMARY KEY (group_id, position)
);

-- Unknown scalar top-level fields on a roll entry, preserved so the
-- re-encoded JSON matches what was POSTed byte-for-byte in content.
-- The Elm encoder never emits extras; this exists for the opaque
-- round-trip contract the HTTP surface has always had.  value_kind
-- is one of 'null' | 'bool' | 'int' | 'float' | 'string' and selects
-- which value column is populated.
CREATE TABLE dice_roll_extras (
  roll_id    TEXT NOT NULL
               REFERENCES dice_rolls (id) ON DELETE CASCADE,
  key        TEXT NOT NULL,
  value_kind TEXT NOT NULL,
  bool_value BIGINT,
  int_value  BIGINT,
  real_value DOUBLE PRECISION,
  text_value TEXT,
  PRIMARY KEY (roll_id, key)
);
