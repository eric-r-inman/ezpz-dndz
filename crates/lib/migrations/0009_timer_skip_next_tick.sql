-- An encounter timer remembers when the turn it started on does not
-- count.  NULL with the rest of the timer pack, and on rows written
-- before this migration.  NULL reads as false.

-- Wire: Encounter.Wire's timer `skipNextTick`.
ALTER TABLE encounter_creatures ADD COLUMN timer_skip_next_tick BIGINT;
