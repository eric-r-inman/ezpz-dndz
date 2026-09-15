-- An encounter condition carries its Exhaustion level, which the
-- creature card steps through.  NULL on every other condition, and on
-- rows written before this migration.

-- Wire: Encounter.Wire's `level`.
ALTER TABLE encounter_creature_conditions ADD COLUMN level BIGINT;
