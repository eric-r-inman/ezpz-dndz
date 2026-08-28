module Ui.Replace exposing (ReplaceLogEntry, ReplaceUi, fresh, maxReplaceLogEntries)

{-| Replace editor state — the encounter toolbar's docked editor
that swaps queue creatures for a compendium pick, preserving
each old creature's queue position and initiative.

@docs ReplaceLogEntry, ReplaceUi, fresh, maxReplaceLogEntries

-}


type alias ReplaceUi =
    { target : String

    -- Compendium picker state: the search narrowing the list,
    -- and the id of the creature clicked as the replacement.
    , searchText : String
    , pickedId : Maybe String
    }


{-| One row of the editor's recent-applies log: the creatures
that were swapped out and the instances that took their places.
-}
type alias ReplaceLogEntry =
    { olds : List String
    , news : List String
    }


{-| Cap on the replace log, matching the HP log's depth.
-}
maxReplaceLogEntries : Int
maxReplaceLogEntries =
    10


fresh : String -> ReplaceUi
fresh target =
    { target = target
    , searchText = ""
    , pickedId = Nothing
    }
