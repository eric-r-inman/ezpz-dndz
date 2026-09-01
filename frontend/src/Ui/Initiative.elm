module Ui.Initiative exposing (InitiativeUi, fresh)

{-| Initiative editor state.

`target` identifies the creature the editor is aimed at — the
active one when the column opened it, or the creature whose
blue init-circle was clicked. The target-scoped buttons act on
it.

`customValueText` is the raw text in the "Initiative:" input.
Tracking the characters lets the user type a transient `-` while
typing a negative initiative without the controlled input
clobbering it.

`rollMode` is read by the roll buttons, so choosing how to roll
is separate from choosing who to roll for. `markSurprised` rides
with any of the editor's actions, rolled or typed.

@docs InitiativeUi, fresh

-}

import Msg exposing (RollMode(..))


type alias InitiativeUi =
    { target : String
    , customValueText : String
    , rollMode : RollMode
    , markSurprised : Bool
    }


fresh : String -> InitiativeUi
fresh target =
    { target = target
    , customValueText = ""
    , rollMode = ModeStandard
    , markSurprised = False
    }
