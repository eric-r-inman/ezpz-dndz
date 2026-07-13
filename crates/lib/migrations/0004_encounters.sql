-- The encounter stores, normalized out of their JSON files: the
-- single auto-saved live encounter per user, and the user-named
-- save files behind the Save / Load modal.
--
-- Portability rules (same as 0001–0003; this file runs unchanged on
-- SQLite and PostgreSQL): TEXT primary keys holding UUID strings,
-- BIGINT for every integer, BIGINT 0/1 for booleans, and no
-- backend-specific types.
--
-- The two stores deliberately use DIFFERENT storage strategies:
--
-- - The LIVE encounter is fully typed (the tables below mirror
--   `frontend/src/Encounter/Wire.elm`, decoded through the lenient
--   codec in `crates/server/src/encounters/wire.rs`).  It is the
--   write-hot core state this migration exists for, and the
--   integration suite's live-encounter bodies either decode through
--   the Elm wire schema or carry no response assertions.
-- - The NAMED SAVES keep their bodies contractually opaque: the
--   HTTP surface has always echoed whatever JSON was PUT (the
--   integration suite pins 200 OK for bodies that do not decode as
--   an Encounter at all, e.g. `{"creatures":[]}` without the
--   required `activeName` / `round`), so the body is stored as a
--   relational JSON node tree (same design as
--   `compendium_save_nodes`, 0003) under typed metadata rows.
--
-- ── live encounter ──────────────────────────────────────────────────
-- One row per user; a user with no row reads as JSON `null` on
-- GET /api/encounter (the frontend's boot path branches on that to
-- keep its empty default).  PUT is a transactional swap: delete the
-- parent row (children cascade), reinsert the decoded replacement.
--
-- The treasure-settings record is always present after decode (the
-- Elm decoder defaults every knob), so its 24 fields flatten onto
-- the parent row, mirroring the treasure_profiles layout (0002).

CREATE TABLE encounters (
  user_id                 TEXT PRIMARY KEY
                            REFERENCES users (id) ON DELETE CASCADE,
  active_name             TEXT NOT NULL,
  round                   BIGINT NOT NULL,
  -- Treasure settings: count knobs 'fewer' | 'normal' | 'more'.
  coins_count             TEXT NOT NULL,
  gems_count              TEXT NOT NULL,
  art_count               TEXT NOT NULL,
  magic_count             TEXT NOT NULL,
  mundane_count           TEXT NOT NULL,
  weapons_count           TEXT NOT NULL,
  armor_count             TEXT NOT NULL,
  -- Value knobs: 'lower' | 'normal' | 'higher'.
  gems_value              TEXT NOT NULL,
  art_value               TEXT NOT NULL,
  magic_value             TEXT NOT NULL,
  -- Hoard toggle block (BIGINT 0/1 booleans).
  hoard_coins_none        BIGINT NOT NULL,
  hoard_gems_none         BIGINT NOT NULL,
  hoard_art_none          BIGINT NOT NULL,
  hoard_magic_none        BIGINT NOT NULL,
  hoard_mundane_none      BIGINT NOT NULL,
  hoard_weapons_none      BIGINT NOT NULL,
  hoard_armor_none        BIGINT NOT NULL,
  -- Individual toggle block.
  individual_coins_none   BIGINT NOT NULL,
  individual_gems_none    BIGINT NOT NULL,
  individual_art_none     BIGINT NOT NULL,
  individual_magic_none   BIGINT NOT NULL,
  individual_mundane_none BIGINT NOT NULL,
  individual_weapons_none BIGINT NOT NULL,
  individual_armor_none   BIGINT NOT NULL,
  magic_scroll_chance     BIGINT NOT NULL
);

-- One row per creature in the initiative queue, one column per
-- scalar wire field.  `row_id` is a surrogate key (creatures have
-- no wire-level identity beyond their name, which need not be
-- unique); `position` preserves queue order.  The optional timer
-- sub-record flattens to a column pack that is all NULL together
-- when absent (presence sentinel: timer_remaining).  creature_id
-- is the wire's nullable compendium link, NULL round-tripping as
-- JSON null.
CREATE TABLE encounter_creatures (
  row_id                          TEXT PRIMARY KEY,
  user_id                         TEXT NOT NULL
                                    REFERENCES encounters (user_id)
                                    ON DELETE CASCADE,
  position                        BIGINT NOT NULL,
  name                            TEXT NOT NULL,
  kind                            TEXT NOT NULL,
  initiative                      BIGINT NOT NULL,
  initiative_bonus                BIGINT NOT NULL,
  current_hp                      BIGINT NOT NULL,
  max_hp                          BIGINT NOT NULL,
  original_max_hp                 BIGINT NOT NULL,
  temp_hp                         BIGINT NOT NULL,
  armor_class                     BIGINT NOT NULL,
  speed                           BIGINT NOT NULL,
  selected                        BIGINT NOT NULL,
  -- 'none' | 'half' | 'threeQuarters' | 'full'.
  cover                           TEXT NOT NULL,
  concentrating                   BIGINT NOT NULL,
  hiding                          BIGINT NOT NULL,
  dodging                         BIGINT NOT NULL,
  flying                          BIGINT NOT NULL,
  fly_height                      BIGINT NOT NULL,
  bloodied                        BIGINT NOT NULL,
  death_save_successes            BIGINT NOT NULL,
  death_save_failures             BIGINT NOT NULL,
  accepting_death_saves           BIGINT NOT NULL,
  reaction_used                   BIGINT NOT NULL,
  readied                         BIGINT NOT NULL,
  inactive                        BIGINT NOT NULL,
  note                            TEXT NOT NULL,
  memo                            TEXT NOT NULL,
  -- Timer pack; all NULL together when the wire had "timer": null.
  timer_remaining                 BIGINT,
  -- 'atBegin' | 'atEnd'.
  timer_phase                     TEXT,
  timer_ringing                   BIGINT,
  timer_note                      TEXT,
  creature_id                     TEXT,
  legendary_actions_count         BIGINT NOT NULL,
  legendary_actions_lair_bonus    BIGINT NOT NULL,
  legendary_resistance_count      BIGINT NOT NULL,
  legendary_resistance_lair_bonus BIGINT NOT NULL,
  is_placeholder                  BIGINT NOT NULL,
  creature_kind                   TEXT NOT NULL,
  race                            TEXT NOT NULL,
  alignment                       TEXT NOT NULL,
  surprised                       BIGINT NOT NULL,
  has_special_reactions           BIGINT NOT NULL
);

CREATE INDEX idx_encounter_creatures_user
  ON encounter_creatures (user_id, position);

-- Conditions on a creature.  The Duration ADT flattens: kind is
-- 'manual' (no params) | 'untilTurn' (phase/target/name) |
-- 'countdown' (phase/remaining/skip_next).  The optional saveToEnd
-- sub-record is the save_* pack, all NULL together when absent.
CREATE TABLE encounter_creature_conditions (
  creature_row_id    TEXT NOT NULL
                       REFERENCES encounter_creatures (row_id)
                       ON DELETE CASCADE,
  position           BIGINT NOT NULL,
  -- The wire-level numeric condition id (frontend-minted).
  condition_id       BIGINT NOT NULL,
  name               TEXT NOT NULL,
  note               TEXT NOT NULL,
  duration_kind      TEXT NOT NULL,
  -- 'atBegin' | 'atEnd' (untilTurn + countdown).
  duration_phase     TEXT,
  -- 'current' | 'next' (untilTurn only).
  duration_target    TEXT,
  duration_name      TEXT,
  duration_remaining BIGINT,
  duration_skip_next BIGINT,
  save_ability       TEXT,
  save_dc            BIGINT,
  save_bonus         BIGINT,
  -- 'manual' | 'atBegin' | 'atEnd'.
  save_auto_roll     TEXT,
  PRIMARY KEY (creature_row_id, position)
);

CREATE TABLE encounter_creature_save_notices (
  creature_row_id TEXT NOT NULL
                    REFERENCES encounter_creatures (row_id)
                    ON DELETE CASCADE,
  position        BIGINT NOT NULL,
  notice_id       BIGINT NOT NULL,
  condition_name  TEXT NOT NULL,
  turns_remaining BIGINT NOT NULL,
  PRIMARY KEY (creature_row_id, position)
);

CREATE TABLE encounter_creature_recharge_abilities (
  creature_row_id TEXT NOT NULL
                    REFERENCES encounter_creatures (row_id)
                    ON DELETE CASCADE,
  position        BIGINT NOT NULL,
  name            TEXT NOT NULL,
  low             BIGINT NOT NULL,
  high            BIGINT NOT NULL,
  ready           BIGINT NOT NULL,
  awaiting_roll   BIGINT NOT NULL,
  PRIMARY KEY (creature_row_id, position)
);

-- The two spent-pip integer sets (legendaryActionsUsed /
-- legendaryResistanceUsed).  The wire encodes each as the sorted
-- ascending list of an Elm Set, which `position` preserves.
CREATE TABLE encounter_creature_pips (
  creature_row_id TEXT NOT NULL
                    REFERENCES encounter_creatures (row_id)
                    ON DELETE CASCADE,
  -- 'action' | 'resistance'.
  pip_kind        TEXT NOT NULL,
  position        BIGINT NOT NULL,
  value           BIGINT NOT NULL,
  PRIMARY KEY (creature_row_id, pip_kind, position)
);

-- The optional generated-treasure payload; presence of this row is
-- the "treasure": non-null sentinel.  The optional RowSource
-- sub-record does NOT get a column sentinel of its own — every one
-- of its members is individually optional, so an all-NULL pack is a
-- legitimate present-but-empty source — hence the explicit
-- has_source flag.
CREATE TABLE encounter_treasure (
  user_id          TEXT PRIMARY KEY
                     REFERENCES encounters (user_id) ON DELETE CASCADE,
  -- 'individual' | 'hoard'.
  kind             TEXT NOT NULL,
  -- '1to4' | '5to10' | '11to16' | '17plus'.
  bracket          TEXT NOT NULL,
  coin_copper      BIGINT NOT NULL,
  coin_silver      BIGINT NOT NULL,
  coin_electrum    BIGINT NOT NULL,
  coin_gold        BIGINT NOT NULL,
  coin_platinum    BIGINT NOT NULL,
  has_source       BIGINT NOT NULL,
  -- RowSource coin formulas: (count, faces, mult) triples, each
  -- coin's three columns all NULL together when the wire had null.
  src_copper_count   BIGINT,
  src_copper_faces   BIGINT,
  src_copper_mult    BIGINT,
  src_silver_count   BIGINT,
  src_silver_faces   BIGINT,
  src_silver_mult    BIGINT,
  src_electrum_count BIGINT,
  src_electrum_faces BIGINT,
  src_electrum_mult  BIGINT,
  src_gold_count     BIGINT,
  src_gold_faces     BIGINT,
  src_gold_mult      BIGINT,
  src_platinum_count BIGINT,
  src_platinum_faces BIGINT,
  src_platinum_mult  BIGINT,
  -- RowSource category specs: (count, faces, tier) triples.
  src_gems_count     BIGINT,
  src_gems_faces     BIGINT,
  src_gems_tier      TEXT,
  src_art_count      BIGINT,
  src_art_faces      BIGINT,
  src_art_tier       TEXT,
  src_magic_count    BIGINT,
  src_magic_faces    BIGINT,
  -- Magic-table letter 'A'–'I'.
  src_magic_table    TEXT
);

-- The per-creature contribution breakdown of a treasure roll.
CREATE TABLE encounter_treasure_contributions (
  user_id       TEXT NOT NULL
                  REFERENCES encounter_treasure (user_id)
                  ON DELETE CASCADE,
  position      BIGINT NOT NULL,
  creature_name TEXT NOT NULL,
  bracket       TEXT NOT NULL,
  coin_copper   BIGINT NOT NULL,
  coin_silver   BIGINT NOT NULL,
  coin_electrum BIGINT NOT NULL,
  coin_gold     BIGINT NOT NULL,
  coin_platinum BIGINT NOT NULL,
  PRIMARY KEY (user_id, position)
);

-- Every item list of a treasure roll — both the roll's own lists
-- (contribution_position = -1) and each contribution's
-- (contribution_position = that contribution's position; a real
-- sentinel rather than NULL so the column can sit in the primary
-- key on both backends).  category selects the populated value
-- columns: 'gems' | 'art' | 'mundane' | 'weapons' | 'armor' carry
-- value_gp, 'magic' carries rarity + table_key, 'loot' is the bare
-- name string.
CREATE TABLE encounter_treasure_items (
  user_id               TEXT NOT NULL
                          REFERENCES encounter_treasure (user_id)
                          ON DELETE CASCADE,
  contribution_position BIGINT NOT NULL,
  category              TEXT NOT NULL,
  position              BIGINT NOT NULL,
  name                  TEXT NOT NULL,
  value_gp              BIGINT,
  -- 'common' | 'uncommon' | 'rare' | 'very-rare' | 'legendary'.
  rarity                TEXT,
  table_key             TEXT,
  PRIMARY KEY (user_id, contribution_position, category, position)
);

-- ── named encounter saves ───────────────────────────────────────────
-- One row per named save plus a relational JSON tree for the body,
-- exactly mirroring compendium_saves / compendium_save_nodes (0003):
-- the body is contractually opaque on the wire, so it is normalized
-- structurally (one row per JSON node, no JSON columns) rather than
-- through the typed live-encounter tables above.
--
-- `position` is the per-user insertion sequence; the listing sorts
-- by updated_at DESC with position as the stable tiebreak, matching
-- the legacy Vec's stable sort.

CREATE TABLE encounter_saves (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL
               REFERENCES users (id) ON DELETE CASCADE,
  position   BIGINT NOT NULL,
  name       TEXT NOT NULL,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);

CREATE UNIQUE INDEX idx_encounter_saves_user_name
  ON encounter_saves (user_id, name);

-- One row per JSON node of a save body.  Same encoding as
-- compendium_save_nodes: the root has a NULL parent_id; children
-- order under a parent by position; object_key is set for object
-- members; kind selects the populated value column ('null' | 'bool'
-- | 'number' | 'string' | 'array' | 'object'), with numbers stored
-- as their serde_json canonical token so int/float distinction and
-- f64 precision round-trip exactly.  parent_id is a same-save tree
-- pointer without its own FK — deleting the save row cascades every
-- node via save_id regardless of tree shape.
CREATE TABLE encounter_save_nodes (
  id           TEXT PRIMARY KEY,
  save_id      TEXT NOT NULL
                 REFERENCES encounter_saves (id) ON DELETE CASCADE,
  parent_id    TEXT,
  position     BIGINT NOT NULL,
  object_key   TEXT,
  kind         TEXT NOT NULL,
  bool_value   BIGINT,
  number_text  TEXT,
  string_value TEXT
);

CREATE INDEX idx_encounter_save_nodes_tree
  ON encounter_save_nodes (save_id, parent_id, position);
