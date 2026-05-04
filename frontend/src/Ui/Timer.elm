module Ui.Timer exposing (TimerSetupUi, fresh)

{-| Card row 3 timer-setup modal state. The GM picks a count
(1..99) and a phase (begin/end of the bearer's turn). Apply
writes the timer onto the creature; cancel discards.

@docs TimerSetupUi, fresh

-}

import Encounter


type alias TimerSetupUi =
    { target : String
    , turnsText : String
    , turns : Int
    , phase : Encounter.TurnPhase
    }


fresh : String -> TimerSetupUi
fresh target =
    { target = target
    , turnsText = "3"
    , turns = 3
    , phase = Encounter.AtEnd
    }
