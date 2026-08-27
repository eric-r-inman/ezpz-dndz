module Ui.Duplicate exposing (DuplicateLogEntry, DuplicateUi, fresh, maxDuplicateLogEntries)

{-| Duplicate editor state — the encounter toolbar's docked
editor that copies creatures in one of five flavors:

  - **Exact** — clone the creature with all current state (HP,
    conditions, notes, etc.).
  - **Fresh** — re-instance from the compendium with unmodified
    state. Falls back to Exact for a creature without a live
    compendium source.
  - **Minion (½ max hp)** — Fresh, then halve max HP and
    match current to it.
  - **Minion (1 hp)** — Fresh, then set max HP to 1 and match
    current to it.
  - **Pudding** — split into two half-HP copies and remove the
    original.

@docs DuplicateLogEntry, DuplicateUi, fresh, maxDuplicateLogEntries

-}

import Msg exposing (DuplicateMode(..))


type alias DuplicateUi =
    { target : String
    , mode : DuplicateMode
    , applyToSelected : Bool
    }


{-| One row of the editor's recent-applies log: which flavor,
which creatures it was applied to, and the copies that appeared
(for Pudding, the two halves).
-}
type alias DuplicateLogEntry =
    { modeLabel : String
    , sources : List String
    , created : List String
    }


{-| Cap on the duplicate log, matching the HP log's depth.
-}
maxDuplicateLogEntries : Int
maxDuplicateLogEntries =
    10


{-| Fresh editor state targeted at a creature. Exact is the
default flavor — the only one that needs no compendium source.
-}
fresh : String -> DuplicateUi
fresh target =
    { target = target
    , mode = DupExact
    , applyToSelected = False
    }
