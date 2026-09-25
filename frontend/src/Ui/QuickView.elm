module Ui.QuickView exposing (QuickViewUi, fresh)

{-| The quick view: a column beside the queue listing every
creature's name and hit points, for a glance at who is still in
the fight.

@docs QuickViewUi, fresh

-}


{-| Whether the column is showing, and whether it lists only the
creatures tagged Enemy. The filter outlives a close, so reopening
the column finds it as the GM left it.
-}
type alias QuickViewUi =
    { open : Bool
    , enemiesOnly : Bool
    }


{-| Closed, and listing every creature once it opens.
-}
fresh : QuickViewUi
fresh =
    { open = False
    , enemiesOnly = False
    }
