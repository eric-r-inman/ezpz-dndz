module Ui.Initiative exposing (InitiativeUi, fresh)

{-| Initiative editor state.

`target` identifies the creature the editor is aimed at — the
active one when the toolbar opened it, or the creature whose
blue init-circle was clicked. Buttons read this for their labels
("Apply & Sort: <target>", etc.).

`customValueText` is the raw text in the "Initiative Value:"
input. Tracking the characters lets the user type a transient
`-` while typing a negative initiative without the controlled
input clobbering it.

@docs InitiativeUi, fresh

-}


type alias InitiativeUi =
    { target : String
    , customValueText : String
    }


fresh : String -> InitiativeUi
fresh target =
    { target = target
    , customValueText = ""
    }
