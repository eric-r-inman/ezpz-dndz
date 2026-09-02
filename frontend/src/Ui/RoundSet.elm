module Ui.RoundSet exposing (RoundSetUi, fresh)

{-| State of the round-setter modal.

Only the typed text: the round it will set is parsed from this
on submit, so a half-typed value doesn't have to round-trip
through an `Int`.

@docs RoundSetUi, fresh

-}


type alias RoundSetUi =
    { roundText : String
    }


fresh : Int -> RoundSetUi
fresh round =
    { roundText = String.fromInt round
    }
