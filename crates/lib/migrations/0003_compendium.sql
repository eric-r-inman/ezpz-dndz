-- The per-user compendium stores, normalized out of their JSON
-- files: user creatures, compendium groups, and named compendium
-- snapshots (saves).
--
-- Portability rules (same as 0001/0002; this file runs unchanged on
-- SQLite and PostgreSQL): TEXT primary keys holding UUID strings,
-- BIGINT for every integer, BIGINT 0/1 for booleans, and no
-- backend-specific types.
--
-- The bundled (SRD) creature set is NOT here: it ships embedded in
-- the binary (`compendium/bundled.rs`) and is content, not state.
-- The legacy SHARED compendium (`compendium/creatures.json` plus its
-- bundle-seed hash sidecar) also gets no tables — post-split it is
-- only input to the one-shot split migration, which keeps reading
-- the JSON file directly.
--
-- Unlike the preset stores (0002) there are no presence-parent
-- tables: the compendium HTTP contract has no null-vs-empty
-- tri-state.  A user with zero rows and a user who persisted an
-- empty list are indistinguishable on the wire (both read as "just
-- the bundled set" / `[]`).
--
-- ── user creatures ──────────────────────────────────────────────────
-- One row per per-user creature, one column per scalar field of
-- `ezpz_dndz_lib::compendium::Creature` (the serde shape IS the wire
-- format; the Elm decoders mirror it).  `row_id` is a surrogate key:
-- the wire-level `creature_id` is NOT globally unique — a user can
-- import another user's export file, which preserves creature ids,
-- and the legacy Vec even tolerated duplicate ids within one user.
-- `position` preserves the legacy JSON list order per user.
--
-- The four Option sub-records (legendary actions, lair actions,
-- regional effects, spellcasting) flatten onto the row as column
-- packs whose members are all NULL together when the record is
-- absent; the presence sentinel is the pack's first column
-- (`legendary_uses`, `lair_initiative`, `regional_description`,
-- `spellcasting_ability` — each NOT NULL whenever the record
-- exists).  `is_bundled` is deliberately not stored: it is
-- server-computed on output and always false for per-user rows.

CREATE TABLE user_creatures (
  row_id                    TEXT PRIMARY KEY,
  user_id                   TEXT NOT NULL
                              REFERENCES users (id) ON DELETE CASCADE,
  position                  BIGINT NOT NULL,
  creature_id               TEXT NOT NULL,
  name                      TEXT NOT NULL,
  -- 'player' | 'enemy' | 'npc'.
  kind                      TEXT NOT NULL,
  -- 'tiny' | 'small' | 'medium' | 'large' | 'huge' | 'gargantuan'.
  size                      TEXT NOT NULL,
  race                      TEXT NOT NULL,
  subrace                   TEXT NOT NULL,
  alignment                 TEXT NOT NULL,
  source                    TEXT NOT NULL,
  description               TEXT NOT NULL,
  armor_class               BIGINT NOT NULL,
  armor_class_note          TEXT NOT NULL,
  max_hp                    BIGINT NOT NULL,
  hp_formula                TEXT NOT NULL,
  initiative_bonus          BIGINT NOT NULL,
  speed_walk                BIGINT NOT NULL,
  speed_fly                 BIGINT NOT NULL,
  speed_swim                BIGINT NOT NULL,
  speed_climb               BIGINT NOT NULL,
  speed_burrow              BIGINT NOT NULL,
  speed_hover               BIGINT NOT NULL,
  ability_str               BIGINT NOT NULL,
  ability_dex               BIGINT NOT NULL,
  ability_con               BIGINT NOT NULL,
  ability_int               BIGINT NOT NULL,
  ability_wis               BIGINT NOT NULL,
  ability_cha               BIGINT NOT NULL,
  senses_blindsight         BIGINT NOT NULL,
  senses_darkvision         BIGINT NOT NULL,
  senses_tremorsense        BIGINT NOT NULL,
  senses_truesight          BIGINT NOT NULL,
  passive_perception        BIGINT NOT NULL,
  challenge_rating          TEXT NOT NULL,
  xp                        BIGINT NOT NULL,
  xp_in_lair                BIGINT NOT NULL,
  proficiency_bonus         BIGINT NOT NULL,
  -- Legendary-actions pack; options live in
  -- user_creature_legendary_options.
  legendary_uses            BIGINT,
  legendary_uses_in_lair    BIGINT,
  legendary_description     TEXT,
  -- Lair-actions pack; options are 'lair_option' rows in
  -- user_creature_features.
  lair_initiative           BIGINT,
  lair_description          TEXT,
  -- Regional-effects pack; effects are 'regional_effect' rows in
  -- user_creature_features.
  regional_description      TEXT,
  regional_fade_after       TEXT,
  -- Spellcasting pack; spell lists live in the spell tables below.
  spellcasting_ability      TEXT,
  spellcasting_description  TEXT,
  spellcasting_save_dc      BIGINT,
  spellcasting_attack_bonus BIGINT,
  created_at                BIGINT NOT NULL,
  updated_at                BIGINT NOT NULL,
  has_special_reactions     BIGINT NOT NULL
);

CREATE INDEX idx_user_creatures_user
  ON user_creatures (user_id, position);
CREATE INDEX idx_user_creatures_wire_id
  ON user_creatures (user_id, creature_id);

CREATE TABLE user_creature_saving_throws (
  creature_row_id TEXT NOT NULL
                    REFERENCES user_creatures (row_id) ON DELETE CASCADE,
  position        BIGINT NOT NULL,
  -- 'str' | 'dex' | 'con' | 'int' | 'wis' | 'cha'.
  ability         TEXT NOT NULL,
  bonus           BIGINT NOT NULL,
  PRIMARY KEY (creature_row_id, position)
);

CREATE TABLE user_creature_skills (
  creature_row_id TEXT NOT NULL
                    REFERENCES user_creatures (row_id) ON DELETE CASCADE,
  position        BIGINT NOT NULL,
  name            TEXT NOT NULL,
  bonus           BIGINT NOT NULL,
  PRIMARY KEY (creature_row_id, position)
);

-- The four damage/condition string lists share one table;
-- `relation` is 'vulnerability' | 'resistance' | 'immunity' |
-- 'condition_immunity'.
CREATE TABLE user_creature_damage_relations (
  creature_row_id TEXT NOT NULL
                    REFERENCES user_creatures (row_id) ON DELETE CASCADE,
  relation        TEXT NOT NULL,
  position        BIGINT NOT NULL,
  value           TEXT NOT NULL,
  PRIMARY KEY (creature_row_id, relation, position)
);

-- The five plain string lists share one table; `list_kind` is
-- 'language' | 'habitat' | 'treasure' | 'tag' | 'loot'.  Habitats
-- and treasures store their wire spellings (kebab-case / lowercase
-- serde enum tokens).
CREATE TABLE user_creature_strings (
  creature_row_id TEXT NOT NULL
                    REFERENCES user_creatures (row_id) ON DELETE CASCADE,
  list_kind       TEXT NOT NULL,
  position        BIGINT NOT NULL,
  value           TEXT NOT NULL,
  PRIMARY KEY (creature_row_id, list_kind, position)
);

-- Every Vec<Feature> on a creature shares one table; feature_group
-- is 'trait' | 'action' | 'bonus_action' | 'reaction' |
-- 'lair_option' | 'regional_effect'.  The optional Usage enum
-- flattens: usage_kind is NULL for "usage": null, otherwise
-- 'recharge' (low/high set) | 'per_day' | 'per_short_rest' |
-- 'per_long_rest' (uses set) | 'at_will' (no params).
CREATE TABLE user_creature_features (
  creature_row_id TEXT NOT NULL
                    REFERENCES user_creatures (row_id) ON DELETE CASCADE,
  feature_group   TEXT NOT NULL,
  position        BIGINT NOT NULL,
  name            TEXT NOT NULL,
  description     TEXT NOT NULL,
  usage_kind      TEXT,
  usage_low       BIGINT,
  usage_high      BIGINT,
  usage_uses      BIGINT,
  PRIMARY KEY (creature_row_id, feature_group, position)
);

CREATE TABLE user_creature_legendary_options (
  creature_row_id TEXT NOT NULL
                    REFERENCES user_creatures (row_id) ON DELETE CASCADE,
  position        BIGINT NOT NULL,
  name            TEXT NOT NULL,
  cost            BIGINT NOT NULL,
  description     TEXT NOT NULL,
  PRIMARY KEY (creature_row_id, position)
);

CREATE TABLE user_creature_custom_sections (
  creature_row_id TEXT NOT NULL
                    REFERENCES user_creatures (row_id) ON DELETE CASCADE,
  position        BIGINT NOT NULL,
  name            TEXT NOT NULL,
  body            TEXT NOT NULL,
  PRIMARY KEY (creature_row_id, position)
);

-- Spellcasting slot levels ({level, slots, spells}) and innate
-- per-day groups ({uses, spells}); the spell-name lists for both —
-- plus the flat at_will list — live in user_creature_spell_names.
CREATE TABLE user_creature_spell_levels (
  creature_row_id TEXT NOT NULL
                    REFERENCES user_creatures (row_id) ON DELETE CASCADE,
  position        BIGINT NOT NULL,
  spell_level     BIGINT NOT NULL,
  slots           BIGINT NOT NULL,
  PRIMARY KEY (creature_row_id, position)
);

CREATE TABLE user_creature_innate_groups (
  creature_row_id TEXT NOT NULL
                    REFERENCES user_creatures (row_id) ON DELETE CASCADE,
  position        BIGINT NOT NULL,
  uses            BIGINT NOT NULL,
  PRIMARY KEY (creature_row_id, position)
);

-- list_kind 'at_will' (list_position 0), 'slot' (list_position =
-- the spell_levels position), or 'innate' (list_position = the
-- innate_groups position).
CREATE TABLE user_creature_spell_names (
  creature_row_id TEXT NOT NULL
                    REFERENCES user_creatures (row_id) ON DELETE CASCADE,
  list_kind       TEXT NOT NULL,
  list_position   BIGINT NOT NULL,
  position        BIGINT NOT NULL,
  name            TEXT NOT NULL,
  PRIMARY KEY (creature_row_id, list_kind, list_position, position)
);

-- ── compendium groups ───────────────────────────────────────────────
-- `ezpz_dndz_lib::compendium::Group`, per user.  Same surrogate-key
-- rationale as user_creatures: group ids travel inside export files
-- and are only unique per user.  The tagged InitiativeMode enum
-- flattens to a kind ('each_rolls' | 'shared_rolled' |
-- 'shared_manual') plus the value column that only 'shared_manual'
-- populates.

CREATE TABLE compendium_groups (
  row_id           TEXT PRIMARY KEY,
  user_id          TEXT NOT NULL
                     REFERENCES users (id) ON DELETE CASCADE,
  position         BIGINT NOT NULL,
  group_id         TEXT NOT NULL,
  name             TEXT NOT NULL,
  initiative_kind  TEXT NOT NULL,
  initiative_value BIGINT,
  created_at       BIGINT NOT NULL,
  updated_at       BIGINT NOT NULL
);

CREATE INDEX idx_compendium_groups_user
  ON compendium_groups (user_id, position);

CREATE TABLE compendium_group_entries (
  group_row_id TEXT NOT NULL
                 REFERENCES compendium_groups (row_id) ON DELETE CASCADE,
  position     BIGINT NOT NULL,
  creature_id  TEXT NOT NULL,
  -- The spawn multiplier ("count" on the wire).
  spawn_count  BIGINT NOT NULL,
  -- 'none' | 'half' | 'one'.
  minion_type  TEXT NOT NULL,
  PRIMARY KEY (group_row_id, position)
);

-- ── named compendium saves ──────────────────────────────────────────
-- One row per named snapshot plus a relational JSON tree for the
-- body.  The snapshot body ("creatures") is deliberately NOT
-- normalized into the creature tables above: the HTTP surface has
-- always stored it as an opaque JSON value (see compendium/saves.rs)
-- so the frontend can evolve the exported shape without a server
-- migration, and callers may legitimately PUT bodies that do not
-- decode as `Creature` at all.  Decoding through the typed schema
-- would reject those bodies and change the route contract.  The
-- node tree below keeps the store fully relational (no JSON
-- columns) while preserving the opaque exact-round-trip contract.
--
-- `position` is the per-user insertion sequence; the listing sorts
-- by updated_at DESC with position as the stable tiebreak, matching
-- the legacy Vec's stable sort.

CREATE TABLE compendium_saves (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL
               REFERENCES users (id) ON DELETE CASCADE,
  position   BIGINT NOT NULL,
  name       TEXT NOT NULL,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);

CREATE UNIQUE INDEX idx_compendium_saves_user_name
  ON compendium_saves (user_id, name);

-- One row per JSON node of a snapshot body.  The root node has a
-- NULL parent_id; children order under a parent by position.
-- object_key is set for object members and NULL for array items and
-- the root.  kind selects the populated value column: 'null' |
-- 'bool' (bool_value) | 'number' (number_text, the serde_json
-- canonical token so int/float distinction and f64 precision
-- round-trip exactly) | 'string' (string_value) | 'array' |
-- 'object' (children only).  parent_id is a same-save tree pointer
-- without its own FK — deleting the save row cascades every node
-- via save_id regardless of tree shape.
CREATE TABLE compendium_save_nodes (
  id           TEXT PRIMARY KEY,
  save_id      TEXT NOT NULL
                 REFERENCES compendium_saves (id) ON DELETE CASCADE,
  parent_id    TEXT,
  position     BIGINT NOT NULL,
  object_key   TEXT,
  kind         TEXT NOT NULL,
  bool_value   BIGINT,
  number_text  TEXT,
  string_value TEXT
);

CREATE INDEX idx_compendium_save_nodes_tree
  ON compendium_save_nodes (save_id, parent_id, position);
