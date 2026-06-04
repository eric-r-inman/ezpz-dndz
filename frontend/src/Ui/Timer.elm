module Ui.Timer exposing
    ( TimerSetupUi, fresh
    , TimerPreset, toPreset, applyPreset
    )

{-| Card row 3 timer-setup modal state. The GM picks a count
(1..99) and a phase (begin/end of the bearer's turn), plus an
optional label. Apply writes the timer onto the creature;
cancel discards.

The Save / Load row in the modal footer mirrors the
Condition/Effect modal's preset flow: the GM can save the
current configuration under a user-given name and reload it
later. Per-application context (`target`) is excluded from the
preset; the form's transient menu / save-name / loaded-name
flags also live on `TimerSetupUi` rather than the preset.

@docs TimerSetupUi, fresh
@docs TimerPreset, toPreset, applyPreset

-}

import Encounter


type alias TimerSetupUi =
    { target : String
    , turnsText : String
    , turns : Int
    , phase : Encounter.TurnPhase
    , note : String
    , loadMenuOpen : Bool
    , pendingSaveName : Maybe String
    , loadedPresetName : Maybe String
    }


fresh : String -> TimerSetupUi
fresh target =
    { target = target
    , turnsText = "3"
    , turns = 3
    , phase = Encounter.AtEnd
    , note = ""
    , loadMenuOpen = False
    , pendingSaveName = Nothing
    , loadedPresetName = Nothing
    }


{-| Saved-named subset of `TimerSetupUi` — every field the GM
might want to reuse across encounters, excluding the per-
application `target` (the bearer changes) and the transient
UI flags.

`note` is included because a saved "Spell ends" or "Bardic
Inspiration" timer typically wants the label too; the GM can
clear it after loading if needed.

-}
type alias TimerPreset =
    { turnsText : String
    , turns : Int
    , phase : Encounter.TurnPhase
    , note : String
    }


{-| Project the current form state down to a savable preset.
-}
toPreset : TimerSetupUi -> TimerPreset
toPreset ui =
    { turnsText = ui.turnsText
    , turns = ui.turns
    , phase = ui.phase
    , note = ui.note
    }


{-| Overlay a saved preset on the current form state. Keeps the
form's `target` (the timer's bearer) and stashes the preset name
in `loadedPresetName` so the title bar shows "(loaded: …)".
Closes the menu and clears the save-name input so the post-load
footer reads cleanly.
-}
applyPreset : String -> TimerPreset -> TimerSetupUi -> TimerSetupUi
applyPreset presetName preset ui =
    { ui
        | turnsText = preset.turnsText
        , turns = preset.turns
        , phase = preset.phase
        , note = preset.note
        , loadMenuOpen = False
        , pendingSaveName = Nothing
        , loadedPresetName = Just presetName
    }
