-- Save Chain effects carry a duration and a failed-save outcome,
-- chains a success-side immunity, and a condition's save-to-end —
-- on the encounter and in condition presets — that same failed-save
-- outcome.  Every column is nullable so rows written before this
-- migration read back as "no setting".

-- Wire: the `duration` object in Encounter.SaveChain.Wire.
-- 'manual' | 'until_turn' | 'countdown' | 'one_minute'; NULL reads
-- as manual.
ALTER TABLE save_chain_effects ADD COLUMN duration_kind TEXT;
-- 'at_begin' | 'at_end' (until_turn + countdown).
ALTER TABLE save_chain_effects ADD COLUMN duration_phase TEXT;
-- 'bearer' | 'active' | 'named' (until_turn only).
ALTER TABLE save_chain_effects ADD COLUMN duration_of TEXT;
-- The creature a 'named' reference watches.
ALTER TABLE save_chain_effects ADD COLUMN duration_name TEXT;
ALTER TABLE save_chain_effects ADD COLUMN duration_turns BIGINT;
-- Wire: the `on_failed_save` object; both NULL while the effect has
-- no save, and each NULL on its own when unset.
ALTER TABLE save_chain_effects ADD COLUMN fail_damage TEXT;
ALTER TABLE save_chain_effects ADD COLUMN fail_becomes TEXT;

-- Wire: the chain's `immunity`, a duration in the effect's encoding;
-- a NULL kind means the chain grants none.
ALTER TABLE save_chains ADD COLUMN immunity_kind TEXT;
ALTER TABLE save_chains ADD COLUMN immunity_phase TEXT;
ALTER TABLE save_chains ADD COLUMN immunity_of TEXT;
ALTER TABLE save_chains ADD COLUMN immunity_name TEXT;
ALTER TABLE save_chains ADD COLUMN immunity_turns BIGINT;

-- Wire: `failDamage` / `failBecomes` in Ui.Condition.Wire's saveToEnd
-- block, "" when unset; NULL alongside a NULL save_ability.
ALTER TABLE condition_presets ADD COLUMN save_fail_damage TEXT;
ALTER TABLE condition_presets ADD COLUMN save_fail_becomes TEXT;

-- Wire: Encounter.Wire's saveToEnd.onFail; NULL when unset.
ALTER TABLE encounter_creature_conditions ADD COLUMN save_fail_damage TEXT;
ALTER TABLE encounter_creature_conditions ADD COLUMN save_fail_becomes TEXT;
