module Ui.Condition exposing (ConditionUi, SaveToEndUi, freshSaveToEnd, fresh, fromCondition)

{-| Condition / effect modal state.

`target` is the creature whose Condition/Effect button (or chip)
was clicked. `editingId` is `Nothing` when creating a new
condition and `Just id` when editing an existing one — the
latter unlocks a "Delete" button in the modal footer.

The remaining fields mirror the rendered form. We track raw
text inputs alongside parsed integers (the same trick as the
dice modifier and HP edit fields) so transient typing states
don't get clobbered between keystrokes.

`customName` is the free-text input under the radio group; the
radio group itself sets `name` directly. When the user clicks
a radio, `customName` is cleared and `name` becomes the chosen
label. When the user types into the custom input, `name` and
`customName` are both updated to that value (so the radios
visually deselect).

`saveToEnd : Maybe SaveToEndUi` controls visibility of the save
section: `Nothing` hides it, `Just _` reveals.

@docs ConditionUi, SaveToEndUi, freshSaveToEnd, fresh, fromCondition

-}

import Encounter
import Msg exposing (DurationKind(..))


type alias ConditionUi =
    { target : String
    , editingId : Maybe Int
    , name : String
    , customName : String
    , note : String
    , durationKind : DurationKind
    , untilCreature : String
    , untilPhase : Encounter.TurnPhase
    , untilTarget : Encounter.TurnTarget
    , countdownTurnsText : String
    , countdownTurns : Int
    , countdownPhase : Encounter.TurnPhase
    , saveToEnd : Maybe SaveToEndUi
    , applyToSelected : Bool
    }


type alias SaveToEndUi =
    { ability : String
    , dcText : String
    , dc : Int
    , bonusText : String
    , bonus : Int
    , autoRoll : Encounter.AutoRollMode
    }


{-| Default save spec when the user enables "save to end" — DC
10 neutral save, no bonus, manual roll. Manual is the safest
default since auto-rolling at begin- or end-of-turn could
surprise the GM with an end-of-condition the moment they enable
save-to-end at all.
-}
freshSaveToEnd : SaveToEndUi
freshSaveToEnd =
    { ability = "WIS"
    , dcText = "10"
    , dc = 10
    , bonusText = "0"
    , bonus = 0
    , autoRoll = Encounter.AutoRollManual
    }


{-| Fresh condition-modal state for creating a new condition on
`target`. The "until X's turn" reference defaults to the target
itself — common for self-effects like "Concentrating until end
of my next turn".
-}
fresh : String -> ConditionUi
fresh target =
    { target = target
    , editingId = Nothing
    , name = ""
    , customName = ""
    , note = ""
    , durationKind = DurKindManual
    , untilCreature = target
    , untilPhase = Encounter.AtEnd
    , untilTarget = Encounter.OnNextTurn
    , countdownTurnsText = "1"
    , countdownTurns = 1
    , countdownPhase = Encounter.AtEnd
    , saveToEnd = Nothing
    , applyToSelected = False
    }


{-| Pre-fill the modal's form fields from an existing condition
so the GM can edit it. Reverse of the form-→-domain projection
the update layer does on submit: break a stored Condition apart
into the raw text states the form needs.
-}
fromCondition : String -> Encounter.Condition -> ConditionUi
fromCondition target cond =
    let
        durFields =
            case cond.duration of
                Encounter.DurationManual ->
                    { kind = DurKindManual
                    , untilCreature = target
                    , untilPhase = Encounter.AtEnd
                    , untilTarget = Encounter.OnNextTurn
                    , countdownTurns = 1
                    , countdownPhase = Encounter.AtEnd
                    }

                Encounter.DurationUntilTurn phase tgt ref ->
                    { kind = DurKindUntilTurn
                    , untilCreature = ref
                    , untilPhase = phase
                    , untilTarget = tgt
                    , countdownTurns = 1
                    , countdownPhase = Encounter.AtEnd
                    }

                Encounter.DurationCountdown phase n _ ->
                    { kind = DurKindCountdown
                    , untilCreature = target
                    , untilPhase = Encounter.AtEnd
                    , untilTarget = Encounter.OnNextTurn
                    , countdownTurns = n
                    , countdownPhase = phase
                    }

        saveUi =
            cond.saveToEnd
                |> Maybe.map
                    (\s ->
                        { ability = s.ability
                        , dcText = String.fromInt s.dc
                        , dc = s.dc
                        , bonusText = String.fromInt s.bonus
                        , bonus = s.bonus
                        , autoRoll = s.autoRoll
                        }
                    )
    in
    { target = target
    , editingId = Just cond.id
    , name = cond.name
    , customName =
        if List.member cond.name Encounter.standardConditions then
            ""

        else
            cond.name
    , note = cond.note
    , durationKind = durFields.kind
    , untilCreature = durFields.untilCreature
    , untilPhase = durFields.untilPhase
    , untilTarget = durFields.untilTarget
    , countdownTurnsText = String.fromInt durFields.countdownTurns
    , countdownTurns = durFields.countdownTurns
    , countdownPhase = durFields.countdownPhase
    , saveToEnd = saveUi
    , applyToSelected = False
    }
