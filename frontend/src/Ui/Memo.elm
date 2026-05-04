module Ui.Memo exposing (MemoEditUi, maxMemoLength, fresh)

{-| Card row 3 memo-edit modal state. Same general shape as the
row 1 note editor but writes to a different field on `Creature`
(`memo` instead of `note`) so the two can coexist on a card.

@docs MemoEditUi, maxMemoLength, fresh

-}


type alias MemoEditUi =
    { target : String
    , text : String
    }


maxMemoLength : Int
maxMemoLength =
    20


fresh : String -> String -> MemoEditUi
fresh target current =
    { target = target
    , text = current
    }
