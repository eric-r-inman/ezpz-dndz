//! Encounter-difficulty (CR) calculator.  *Stub.*
//!
//! Per OPTIMIZATION_AND_COMPLIANCE_PLAN Phase 7, this module
//! reserves the surface for the 5e DMG encounter-difficulty
//! computation.  The plan calls for a pure function:
//!
//! ```rust,ignore
//! pub fn encounter_difficulty(
//!     party: &[CharacterLevel],
//!     monsters: &[CreatureRef],
//! ) -> Difficulty;
//!
//! pub enum Difficulty { Easy, Medium, Hard, Deadly }
//! ```
//!
//! The frontend will mirror this in Elm so the same XP table is
//! used in both the CLI (~ezpz-dndz-cli calc-difficulty~) and the
//! browser (live preview in the compendium browser as the GM
//! picks creatures).
//!
//! Lives in the lib crate (not the server) because no HTTP route
//! is involved — the calculator is consumed by the CLI and
//! shared with the frontend via duplicated logic in `Elm`-land.
//! Open question (see OPTIMIZATION_AND_COMPLIANCE_PLAN's
//! "Open questions"): where in the UI does the calculator
//! surface — inside the compendium browser, or as a standalone
//! tool?
