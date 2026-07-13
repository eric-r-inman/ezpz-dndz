-- The five per-user preset stores, normalized out of the opaque-JSON
-- per_user_store: lore groups, condition presets, Save Chain presets,
-- the singular treasure table, and treasure profiles.
--
-- Portability rules (same as 0001; this file runs unchanged on SQLite
-- and PostgreSQL): TEXT primary keys holding UUID strings, BIGINT for
-- every integer, BIGINT 0/1 for booleans, and no backend-specific
-- types.
--
-- Every feature has a per-user PRESENCE parent table keyed by
-- user_id.  The HTTP contract is tri-state: GET returns JSON `null`
-- when the user has never persisted the feature (no parent row), and
-- the exact persisted structure otherwise — including a
-- persisted-but-empty collection (parent row, zero children).  The
-- frontend's Update.UserSync migration logic depends on that
-- distinction to decide between "adopt the server copy" and "upload
-- the anonymous-mode localStorage snapshot".

-- ── lore groups ─────────────────────────────────────────────────────
-- Wire: a JSON LIST of groups (Encounter.RandomEncounter.Lore.Wire),
-- each with an ordered member list.  List order round-trips through
-- `position`.

CREATE TABLE lore_group_sets (
  user_id TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE
);

CREATE TABLE lore_groups (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL
                REFERENCES lore_group_sets (user_id) ON DELETE CASCADE,
  position    BIGINT NOT NULL,
  -- The wire-level group id ("id" in the JSON); distinct from the
  -- surrogate row id above because the wire never promises global
  -- uniqueness across users.
  group_id    TEXT NOT NULL,
  name        TEXT NOT NULL,
  weight      BIGINT NOT NULL,
  -- 'bundled' | 'user', normalized by the decoder (unknown → 'user').
  source      TEXT NOT NULL,
  description TEXT NOT NULL
);

CREATE INDEX idx_lore_groups_user ON lore_groups (user_id, position);

CREATE TABLE lore_group_members (
  group_row_id TEXT NOT NULL
                 REFERENCES lore_groups (id) ON DELETE CASCADE,
  position     BIGINT NOT NULL,
  name         TEXT NOT NULL,
  -- 'leader' | 'member' | 'minion' | 'pet' (unknown → 'member').
  role         TEXT NOT NULL,
  count_min    BIGINT NOT NULL,
  count_max    BIGINT NOT NULL,
  PRIMARY KEY (group_row_id, position)
);

-- ── condition presets ───────────────────────────────────────────────
-- Wire: a JSON dict keyed by the user's preset name
-- (Ui.Condition.Wire).  The nullable saveToEnd sub-record flattens
-- onto the row; save_ability IS NULL means "saveToEnd": null.

CREATE TABLE condition_preset_sets (
  user_id TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE
);

CREATE TABLE condition_presets (
  user_id              TEXT NOT NULL
                         REFERENCES condition_preset_sets (user_id)
                         ON DELETE CASCADE,
  preset_key           TEXT NOT NULL,
  condition_name       TEXT NOT NULL,
  custom_name          TEXT NOT NULL,
  note                 TEXT NOT NULL,
  -- 'manual' | 'untilTurn' | 'countdown'.
  duration_kind        TEXT NOT NULL,
  -- 'atBegin' | 'atEnd'.
  until_phase          TEXT NOT NULL,
  countdown_turns_text TEXT NOT NULL,
  countdown_turns      BIGINT NOT NULL,
  countdown_phase      TEXT NOT NULL,
  -- The optional save-to-end block; all six populated together.
  save_ability         TEXT,
  save_dc_text         TEXT,
  save_dc              BIGINT,
  save_bonus_text      TEXT,
  save_bonus           BIGINT,
  -- 'manual' | 'atBegin' | 'atEnd'.
  save_auto_roll       TEXT,
  category             TEXT NOT NULL,
  PRIMARY KEY (user_id, preset_key)
);

-- ── Save Chain presets ──────────────────────────────────────────────
-- Wire: a JSON dict keyed by preset name (Encounter.SaveChain.Wire).
-- The per-side HP effect flattens onto the chain row; the per-side
-- effect lists hang off save_chain_effects.

CREATE TABLE save_chain_sets (
  user_id TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE
);

CREATE TABLE save_chains (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL
                      REFERENCES save_chain_sets (user_id)
                      ON DELETE CASCADE,
  preset_key        TEXT NOT NULL,
  name              TEXT NOT NULL,
  -- 'str' | 'dex' | 'con' | 'int' | 'wis' | 'cha'.
  save_ability      TEXT NOT NULL,
  -- NULL round-trips as JSON null ("save_dc": null).
  save_dc           BIGINT,
  -- 'none' | 'damage' | 'heal' | 'half_fail'; amount is the dice
  -- formula string, populated only for 'damage' / 'heal'.
  fail_hp_kind      TEXT NOT NULL,
  fail_hp_amount    TEXT,
  success_hp_kind   TEXT NOT NULL,
  success_hp_amount TEXT
);

CREATE UNIQUE INDEX idx_save_chains_user_key
  ON save_chains (user_id, preset_key);

CREATE TABLE save_chain_effects (
  chain_id    TEXT NOT NULL
                REFERENCES save_chains (id) ON DELETE CASCADE,
  -- 'fail' | 'success'.
  side        TEXT NOT NULL,
  position    BIGINT NOT NULL,
  name        TEXT NOT NULL,
  note        TEXT NOT NULL,
  -- NULL | 'manual' | 'at_begin' | 'at_end'; NULL round-trips as
  -- "save_to_end": null.
  save_to_end TEXT,
  PRIMARY KEY (chain_id, side, position)
);

-- ── treasure table ──────────────────────────────────────────────────
-- Wire: the singular per-user table (Encounter.Treasure.TableWire).
-- The five original categories (individualBrackets, hoardBrackets,
-- gems, art, magic) are always present on the wire; the seven
-- later-added fields (mundane, mundaneRoll, weapons, weaponsRoll,
-- armor, armorRoll, scrollSpells) may be ABSENT on saves that predate
-- them, and absence is semantically distinct from empty: the Elm
-- decoder seeds bundled defaults for an absent field but keeps an
-- explicit empty list as the GM opting out.  The has_* flags preserve
-- that tri-state; the encoder omits a field whose flag is 0.

CREATE TABLE treasure_table_sets (
  user_id           TEXT PRIMARY KEY
                      REFERENCES users (id) ON DELETE CASCADE,
  has_mundane       BIGINT NOT NULL,
  has_mundane_roll  BIGINT NOT NULL,
  has_weapons       BIGINT NOT NULL,
  has_weapons_roll  BIGINT NOT NULL,
  has_armor         BIGINT NOT NULL,
  has_armor_roll    BIGINT NOT NULL,
  has_scroll_spells BIGINT NOT NULL
);

-- Dict keys for the dict-of-list categories ('individual' | 'hoard' |
-- 'gems' | 'art' | 'magic' | 'scrollSpells').  A key row with zero
-- item rows encodes a bracket whose list the GM emptied — the key
-- must survive the round-trip even with no entries under it.
CREATE TABLE treasure_table_brackets (
  user_id  TEXT NOT NULL
             REFERENCES treasure_table_sets (user_id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  bracket  TEXT NOT NULL,
  PRIMARY KEY (user_id, category, bracket)
);

-- One row per individualBrackets entry.  Each coin formula is a
-- (count, faces, mult) triple, all three NULL together when the wire
-- had null / absent for that coin.
CREATE TABLE treasure_individual_rows (
  user_id        TEXT NOT NULL
                   REFERENCES treasure_table_sets (user_id)
                   ON DELETE CASCADE,
  bracket        TEXT NOT NULL,
  position       BIGINT NOT NULL,
  weight         BIGINT NOT NULL,
  copper_count   BIGINT,
  copper_faces   BIGINT,
  copper_mult    BIGINT,
  silver_count   BIGINT,
  silver_faces   BIGINT,
  silver_mult    BIGINT,
  electrum_count BIGINT,
  electrum_faces BIGINT,
  electrum_mult  BIGINT,
  gold_count     BIGINT,
  gold_faces     BIGINT,
  gold_mult      BIGINT,
  platinum_count BIGINT,
  platinum_faces BIGINT,
  platinum_mult  BIGINT,
  PRIMARY KEY (user_id, bracket, position)
);

-- One row per hoardBrackets entry: the coin columns above plus the
-- optional gems/art/magic sub-roll specs ((count, faces, tier)
-- triples, NULL together when absent).
CREATE TABLE treasure_hoard_rows (
  user_id         TEXT NOT NULL
                    REFERENCES treasure_table_sets (user_id)
                    ON DELETE CASCADE,
  bracket         TEXT NOT NULL,
  position        BIGINT NOT NULL,
  weight          BIGINT NOT NULL,
  copper_count    BIGINT,
  copper_faces    BIGINT,
  copper_mult     BIGINT,
  silver_count    BIGINT,
  silver_faces    BIGINT,
  silver_mult     BIGINT,
  electrum_count  BIGINT,
  electrum_faces  BIGINT,
  electrum_mult   BIGINT,
  gold_count      BIGINT,
  gold_faces      BIGINT,
  gold_mult       BIGINT,
  platinum_count  BIGINT,
  platinum_faces  BIGINT,
  platinum_mult   BIGINT,
  gems_count      BIGINT,
  gems_faces      BIGINT,
  gems_tier       TEXT,
  art_count       BIGINT,
  art_faces       BIGINT,
  art_tier        TEXT,
  magic_count     BIGINT,
  magic_faces     BIGINT,
  magic_table_key TEXT,
  PRIMARY KEY (user_id, bracket, position)
);

-- The string-list dict categories: gems / art / magic names per tier
-- and scroll spells per spell level.
CREATE TABLE treasure_name_entries (
  user_id  TEXT NOT NULL
             REFERENCES treasure_table_sets (user_id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  bracket  TEXT NOT NULL,
  position BIGINT NOT NULL,
  name     TEXT NOT NULL,
  PRIMARY KEY (user_id, category, bracket, position)
);

-- The flat item lists ('mundane' | 'weapons' | 'armor').
CREATE TABLE treasure_flat_items (
  user_id  TEXT NOT NULL
             REFERENCES treasure_table_sets (user_id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  position BIGINT NOT NULL,
  name     TEXT NOT NULL,
  value_gp BIGINT NOT NULL,
  PRIMARY KEY (user_id, category, position)
);

-- The per-bracket roll dice for the flat categories ('mundane' |
-- 'weapons' | 'armor'): dict key → {count, faces}.
CREATE TABLE treasure_roll_specs (
  user_id   TEXT NOT NULL
              REFERENCES treasure_table_sets (user_id) ON DELETE CASCADE,
  category  TEXT NOT NULL,
  bracket   TEXT NOT NULL,
  die_count BIGINT NOT NULL,
  die_faces BIGINT NOT NULL,
  PRIMARY KEY (user_id, category, bracket)
);

-- ── treasure profiles ───────────────────────────────────────────────
-- Wire: a JSON dict keyed by the GM-given profile name, each value a
-- full TreasureSettings record (Encounter.Wire.encodeTreasureSettings)
-- — ten count/value adjustment knobs, two 7-bool toggle blocks, and
-- the scroll chance.

CREATE TABLE treasure_profile_sets (
  user_id TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE
);

CREATE TABLE treasure_profiles (
  user_id                 TEXT NOT NULL
                            REFERENCES treasure_profile_sets (user_id)
                            ON DELETE CASCADE,
  name                    TEXT NOT NULL,
  -- Count knobs: 'fewer' | 'normal' | 'more'.
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
  magic_scroll_chance     BIGINT NOT NULL,
  PRIMARY KEY (user_id, name)
);
