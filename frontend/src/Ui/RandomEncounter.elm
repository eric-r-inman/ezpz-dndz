module Ui.RandomEncounter exposing
    ( RandomEncounterUi, RollState(..)
    , fresh
    )

{-| Modal-local UI state for the Random Encounter generator.

The party (`model.party`) is shared with the CR Calculator and
lives on `Model` so the GM doesn't have to re-enter it. What's
modal-local here is the generator parameters — target
difficulty, scale, habitat filter, creature-type filter, and
the include-minions toggle — plus the current roll.

@docs RandomEncounterUi, RollState
@docs fresh

-}

import Compendium exposing (Creature, Habitat)
import Encounter.RandomEncounter exposing (Scale(..), TargetDifficulty(..))


{-| Result of the most recent generation attempt:

  - `RollIdle` — never rolled in this modal session (or just
    after the GM changed params).
  - `RollEmptyPool` — the params produced an empty filter
    pool; the view shows a "no matches" notice with a
    suggestion to widen the filter.
  - `RollOk groups` — one or more `(creature, count)` groups.

-}
type RollState
    = RollIdle
    | RollEmptyPool
    | RollOk (List ( Creature, Int ))


type alias RandomEncounterUi =
    { difficulty : TargetDifficulty
    , scale : Scale
    , habitat : Maybe Habitat

    -- OR-of-types filter.  Empty list is Any; each entry is a
    -- race string ("Dragon", "Fiend", ...).  The view renders
    -- one <select> per entry plus a trailing empty one so the
    -- GM can add or replace entries one at a time.
    , creatureTypes : List String
    , includeMinions : Bool

    -- Pinned creatures the GM has chosen to lock into the
    -- roll, deduplicated by creature id with a per-entry
    -- count.  Re-pinning increments the count.
    , pinned : List ( Creature, Int )

    -- Search-as-you-type text for the pin picker; the view
    -- shows up to 8 compendium matches as the GM types.
    , pinSearch : String
    , roll : RollState
    }


fresh : RandomEncounterUi
fresh =
    { difficulty = Moderate
    , scale = ScaleFew
    , habitat = Nothing
    , creatureTypes = []
    , includeMinions = False
    , pinned = []
    , pinSearch = ""
    , roll = RollIdle
    }
