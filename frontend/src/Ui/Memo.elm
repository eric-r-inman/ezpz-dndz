module Ui.Memo exposing (MemoEditUi, maxMemoLength, fresh, inputId)

{-| Card row 3 memo-edit modal state. Same general shape as the
row 1 note editor but writes to a different field on `Creature`
(`memo` instead of `note`) so the two can coexist on a card.

@docs MemoEditUi, maxMemoLength, fresh, inputId

-}


type alias MemoEditUi =
    { target : String
    , text : String
    }


maxMemoLength : Int
maxMemoLength =
    20


{-| DOM id of the memo field. Only one card editor is open at a
time, so one id serves every card.
-}
inputId : String
inputId =
    "memo-input"


fresh : String -> String -> MemoEditUi
fresh target current =
    { target = target
    , text = current
    }
