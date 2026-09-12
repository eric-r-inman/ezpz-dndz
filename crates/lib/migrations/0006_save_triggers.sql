-- Save Chain effects carry a damage trigger and a companion
-- condition, chains an area-effect phase, a condition's save-to-end
-- — on the encounter and in condition presets — that same damage
-- trigger, and an encounter condition a link to the condition it
-- rides on and an area-effect marker.  Every column is nullable so
-- rows written before this migration read back as "no setting".

-- Wire: `on_damage` in Encounter.SaveChain.Wire, NULL alongside a
-- NULL save_to_end.  'none' | 'ask' | 'roll' | 'roll_advantage'.
ALTER TABLE save_chain_effects ADD COLUMN on_damage TEXT;
-- Wire: `with`, the companion condition's name; NULL reads as "".
ALTER TABLE save_chain_effects ADD COLUMN with_name TEXT;

-- Wire: the chain's `area`, 'at_begin' | 'at_end'; NULL means the
-- chain is not an area effect.
ALTER TABLE save_chains ADD COLUMN area_phase TEXT;

-- Wire: `onDamage` in Ui.Condition.Wire's saveToEnd block; NULL
-- alongside a NULL save_ability, and NULL reads as 'none'.
ALTER TABLE condition_presets ADD COLUMN save_on_damage TEXT;

-- Wire: Encounter.Wire's saveToEnd.onDamage; NULL reads as 'none'.
ALTER TABLE encounter_creature_conditions ADD COLUMN save_on_damage TEXT;
-- Wire: `linkedTo`, the id of the condition this one ends with.
ALTER TABLE encounter_creature_conditions ADD COLUMN linked_to BIGINT;
-- Wire: the `area` object; a NULL chain means the condition is not
-- an area marker.  Phase is 'atBegin' | 'atEnd'.
ALTER TABLE encounter_creature_conditions ADD COLUMN area_chain TEXT;
ALTER TABLE encounter_creature_conditions ADD COLUMN area_ability TEXT;
ALTER TABLE encounter_creature_conditions ADD COLUMN area_dc BIGINT;
ALTER TABLE encounter_creature_conditions ADD COLUMN area_bonus BIGINT;
ALTER TABLE encounter_creature_conditions ADD COLUMN area_phase TEXT;
