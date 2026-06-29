module Ui.Condition exposing
    ( ConditionUi, SaveToEndUi, freshSaveToEnd, fresh, fromCondition
    , ConditionPreset, applyPreset, toPreset
    )

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
import Set exposing (Set)


{-| Modal state for the Add / Edit Condition dialog.

The "until turn" duration shape no longer carries an explicit
"current vs next" choice — every condition expires when the
target creature's turn next comes up, with the begin/end phase
controlling whether that's the start or end. The resolution
between `OnCurrentTurn` (expire on first match) and `OnNextTurn`
(skip the first match) is computed at submit time based on
whether the target is currently active and the chosen phase;
see `Update.Condition.buildDuration`.

-}
type alias ConditionUi =
    { target : String
    , editingId : Maybe Int
    , name : String
    , customName : String
    , note : String
    , durationKind : DurationKind
    , untilCreature : String
    , untilPhase : Encounter.TurnPhase
    , countdownTurnsText : String
    , countdownTurns : Int
    , countdownPhase : Encounter.TurnPhase
    , saveToEnd : Maybe SaveToEndUi
    , applyToSelected : Bool
    , loadMenuOpen : Bool
    , pendingSaveName : Maybe String
    , pendingSaveCategory : String
    , loadedPresetName : Maybe String
    , expandedCategories : Set String

    -- The "1 Minute" preset radio sits alongside Countdown but
    -- collapses to the same underlying countdown values (turns=10,
    -- phase=AtEnd).  This flag tells the view which radio is
    -- visually selected — without it, Countdown and 1 Minute
    -- would both highlight when the user has 10/end set, which
    -- reads as a bug.  Reset to False whenever the user touches
    -- duration in any other way.
    , useOneMinutePreset : Bool

    -- Disclosure state for the Custom Name + Note sections.
    -- Both default to collapsed on open to keep the modal tidy
    -- for the common-case "pick a standard condition" flow; the
    -- GM expands them when they actually need to override.
    , customNameExpanded : Bool
    , noteExpanded : Bool
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
    , countdownTurnsText = "1"
    , countdownTurns = 1
    , countdownPhase = Encounter.AtEnd
    , saveToEnd = Nothing
    , applyToSelected = False
    , loadMenuOpen = False
    , pendingSaveName = Nothing
    , pendingSaveCategory = ""
    , loadedPresetName = Nothing
    , expandedCategories = Set.empty
    , useOneMinutePreset = False
    , customNameExpanded = False
    , noteExpanded = False
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
                    , countdownTurns = 1
                    , countdownPhase = Encounter.AtEnd
                    }

                Encounter.DurationUntilTurn phase _ ref ->
                    -- Discard the saved TurnTarget; the modal no longer
                    -- exposes the current/next choice and `buildDuration`
                    -- recomputes it from current encounter state on submit.
                    { kind = DurKindUntilTurn
                    , untilCreature = ref
                    , untilPhase = phase
                    , countdownTurns = 1
                    , countdownPhase = Encounter.AtEnd
                    }

                Encounter.DurationCountdown phase n _ ->
                    { kind = DurKindCountdown
                    , untilCreature = target
                    , untilPhase = Encounter.AtEnd
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
    , countdownTurnsText = String.fromInt durFields.countdownTurns
    , countdownTurns = durFields.countdownTurns
    , countdownPhase = durFields.countdownPhase
    , saveToEnd = saveUi
    , applyToSelected = False
    , loadMenuOpen = False
    , pendingSaveName = Nothing
    , pendingSaveCategory = ""
    , loadedPresetName = Nothing
    , expandedCategories = Set.empty
    , useOneMinutePreset = False
    , customNameExpanded = False
    , noteExpanded = False
    }


{-| Saved-named subset of `ConditionUi` — the parts a user is
likely to reuse across encounters when they keep applying the
same condition shape (DM uses Stun a lot? save the whole config).

Excludes everything that's context-specific to one application:

  - `target` / `editingId` / `applyToSelected` — per-creature.
  - `untilCreature` — references a specific name; on load the
    handler defaults it to the current target so "Until self's
    next turn" comes through correctly.
  - `loadMenuOpen` / `pendingSaveName` / `loadedPresetName` —
    transient UI state, not part of the preset.

-}
type alias ConditionPreset =
    { conditionName : String
    , customName : String
    , note : String
    , durationKind : DurationKind
    , untilPhase : Encounter.TurnPhase
    , countdownTurnsText : String
    , countdownTurns : Int
    , countdownPhase : Encounter.TurnPhase
    , saveToEnd : Maybe SaveToEndUi
    , category : String
    }


{-| Project the current form state down to a savable preset.
Field names are renamed (`name` → `conditionName`) so the wire
shape is self-explanatory; the rest map straight through.
User-saved presets get `category = ""` and render in the "My
Presets" section at the top of the Load menu, above the four
bundled categories.
-}
toPreset : ConditionUi -> ConditionPreset
toPreset ui =
    { conditionName = ui.name
    , customName = ui.customName
    , note = ui.note
    , durationKind = ui.durationKind
    , untilPhase = ui.untilPhase
    , countdownTurnsText = ui.countdownTurnsText
    , countdownTurns = ui.countdownTurns
    , countdownPhase = ui.countdownPhase
    , saveToEnd = ui.saveToEnd
    , category = ""
    }


{-| Overlay a saved preset on the current form state. Keeps the
form's per-application context (`target`, `editingId`,
`applyToSelected`) and reuses the current target as the
`untilCreature` default — that's the natural fit for self-effect
presets like "Until self's next turn", which is what Stun and
many other 5e conditions look like in practice.

Stashes the preset name in `loadedPresetName` so the title bar
shows "(loaded: Stun)". Closes any open load menu and clears the
pending save-name input so the post-load footer reads cleanly.

-}
applyPreset : String -> ConditionPreset -> ConditionUi -> ConditionUi
applyPreset presetName preset ui =
    let
        -- `ui.name` is the effective chip label and drives the
        -- Apply button's enabled state.  For presets that use a
        -- standard condition, `conditionName` carries the label
        -- ("Stunned"); for custom-named bundled presets like
        -- *Bardic Inspiration*, `conditionName` is empty and the
        -- label lives in `customName` instead.  Fall back to the
        -- latter so loading a custom-named preset doesn't land
        -- with an unset name + a disabled Apply button.
        effectiveName =
            if String.isEmpty preset.conditionName then
                preset.customName

            else
                preset.conditionName
    in
    { ui
        | name = effectiveName
        , customName = preset.customName
        , note = preset.note
        , durationKind = preset.durationKind
        , untilCreature = ui.target
        , untilPhase = preset.untilPhase
        , countdownTurnsText = preset.countdownTurnsText
        , countdownTurns = preset.countdownTurns
        , countdownPhase = preset.countdownPhase
        , saveToEnd = preset.saveToEnd
        , loadMenuOpen = False
        , pendingSaveName = Nothing
        , pendingSaveCategory = ""
        , loadedPresetName = Just presetName
    }
