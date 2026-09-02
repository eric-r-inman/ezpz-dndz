module Ui.ActionGroups exposing (ActionGroups, fresh)

{-| Which of the Actions column's trigger groups are collapsed.

Not `Surface` variants: a `Surface` is the one thing the GM is
editing, while these only decide how much of the column is
folded away. Each is independent, and the column starts with
every group showing.

@docs ActionGroups, fresh

-}


type alias ActionGroups =
    { compendium : Bool
    , encounter : Bool
    , creature : Bool
    }


fresh : ActionGroups
fresh =
    { compendium = False
    , encounter = False
    , creature = False
    }
