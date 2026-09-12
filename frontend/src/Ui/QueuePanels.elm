module Ui.QueuePanels exposing (QueuePanels, fresh)

{-| Which of the encounter queue's reference drop-downs are
open.

These are not `Surface` variants: a `Surface` is the one thing
the GM is editing, while these are read-only references the GM
may want open together — the legendary actions a creature can
take alongside the spells it can cast.

@docs QueuePanels, fresh

-}


type alias QueuePanels =
    { legendaryActions : Bool
    , specialReactions : Bool
    , spells : Bool
    }


fresh : QueuePanels
fresh =
    { legendaryActions = False
    , specialReactions = False
    , spells = False
    }
