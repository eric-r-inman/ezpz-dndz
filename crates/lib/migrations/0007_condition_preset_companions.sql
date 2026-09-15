-- Condition presets carry companions: further conditions a preset
-- applies alongside its own, each ending when that one ends.

-- Wire: `companions` in Ui.Condition.Wire's preset body, one row per
-- entry, in list order.
CREATE TABLE condition_preset_companions (
  user_id    TEXT NOT NULL,
  preset_key TEXT NOT NULL,
  position   BIGINT NOT NULL,
  name       TEXT NOT NULL,
  PRIMARY KEY (user_id, preset_key, position),
  FOREIGN KEY (user_id, preset_key)
    REFERENCES condition_presets (user_id, preset_key) ON DELETE CASCADE
);
