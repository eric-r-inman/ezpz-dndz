module Ui.Duplicate exposing (DuplicateUi, fresh)

{-| Picker modal for the creature-card Duplicate button. Four
options:

  - **Exact** — clone the creature with all current state (HP,
    conditions, notes, etc.).
  - **Fresh** — re-instance from the compendium with unmodified
    state (full HP, no conditions, no notes). Requires the
    source creature to have a `creatureId`; otherwise the option
    is unavailable.
  - **Minion (½ max hp)** — Fresh, then halve max HP and
    match current to it.
  - **Minion (1 hp)** — Fresh, then set max HP to 1 and match
    current to it.

The substate is small: we only need the source creature's name
to dispatch the chosen mode.

@docs DuplicateUi, fresh

-}


{-| Picker substate. `creatureName` identifies which creature
in the queue the modal was opened over.
-}
type alias DuplicateUi =
    { creatureName : String
    }


{-| Build a fresh picker for the given creature.
-}
fresh : String -> DuplicateUi
fresh creatureName =
    { creatureName = creatureName
    }
