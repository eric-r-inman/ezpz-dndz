module Update.Condition exposing
    ( applyToSelectedToggle
    , close
    , countdownPhaseSet
    , countdownTurnsChanged
    , customNameChanged
    , delete
    , durationKindSet
    , maxConditionNoteLength
    , noteChanged
    , openEdit
    , openNew
    , pickStandard
    , presetCategoryToggle
    , presetDelete
    , presetLoad
    , presetLoadMenuClose
    , presetLoadMenuToggle
    , presetSaveCancel
    , presetSaveNameChanged
    , presetSaveStart
    , presetSaveSubmit
    , removeChip
    , rollSave
    , saveAbilityChanged
    , saveAutoRollSet
    , saveBonusChanged
    , saveDcChanged
    , saveLanded
    , saveNoticeDismiss
    , saveToggle
    , submit
    , untilCreatureChanged
    , untilPhaseSet
    )

{-| Update branches for the condition / effect modal: the radio
list of standard conditions, custom-name field, the duration-kind
selector (manual / until-turn / countdown), the optional save-to-end
sub-form, the multi-target toggle, the submit / delete actions, the
chip-level remove + roll-save buttons on cards, and the
saving-throw result handler.
-}

import Dice
import Dict
import Effects
import Encounter
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( DurationKind(..)
        , Msg(..)
        )
import Set
import Ui.Condition as ConditionUi exposing (ConditionUi)


{-| Hard cap on the chip-note text. Ten characters keeps the chip
small and prevents wrap-overflow on the card row 1.
-}
maxConditionNoteLength : Int
maxConditionNoteLength =
    10


withConditionUi : (ConditionUi -> ConditionUi) -> Model -> Model
withConditionUi =
    Model.mapModal Model.conditionLens


openNew : String -> Model -> ( Model, Cmd Msg )
openNew name model =
    ( { model | modal = Just (ModalCondition (ConditionUi.fresh name)) }
    , Cmd.none
    )


openEdit : String -> Int -> Model -> ( Model, Cmd Msg )
openEdit name id model =
    ( case Encounter.findCondition name id model.encounter of
        Just ( _, cond ) ->
            { model | modal = Just (ModalCondition (ConditionUi.fromCondition name cond)) }

        Nothing ->
            model
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


pickStandard : String -> Model -> ( Model, Cmd Msg )
pickStandard label model =
    ( withConditionUi
        (\u ->
            -- Clicking the already-selected condition clears the
            -- selection — the badge acts as a toggle, not a
            -- strict radio.  Custom-name field is cleared either
            -- way so re-selecting after typing custom text
            -- doesn't leave a stale value behind.
            if u.name == label then
                { u | name = "", customName = "" }

            else
                { u | name = label, customName = "" }
        )
        model
    , Cmd.none
    )


{-| Typing in the custom field both populates the name and clears
the standard radio selection (logically: "name" is whatever the
user last touched).
-}
customNameChanged : String -> Model -> ( Model, Cmd Msg )
customNameChanged text model =
    ( withConditionUi (\u -> { u | name = text, customName = text }) model
    , Cmd.none
    )


noteChanged : String -> Model -> ( Model, Cmd Msg )
noteChanged text model =
    ( withConditionUi
        (\u -> { u | note = String.left maxConditionNoteLength text })
        model
    , Cmd.none
    )


durationKindSet : DurationKind -> Model -> ( Model, Cmd Msg )
durationKindSet kind model =
    ( withConditionUi (\u -> { u | durationKind = kind }) model, Cmd.none )


untilCreatureChanged : String -> Model -> ( Model, Cmd Msg )
untilCreatureChanged name model =
    ( withConditionUi (\u -> { u | untilCreature = name }) model
    , Cmd.none
    )


untilPhaseSet : Encounter.TurnPhase -> Model -> ( Model, Cmd Msg )
untilPhaseSet phase model =
    ( withConditionUi (\u -> { u | untilPhase = phase }) model
    , Cmd.none
    )


countdownTurnsChanged : String -> Model -> ( Model, Cmd Msg )
countdownTurnsChanged text model =
    ( withConditionUi
        (\u ->
            { u
                | countdownTurnsText = text
                , countdownTurns =
                    String.toInt (String.trim text)
                        |> Maybe.map (Basics.max 1 >> Basics.min 99)
                        |> Maybe.withDefault u.countdownTurns
            }
        )
        model
    , Cmd.none
    )


countdownPhaseSet : Encounter.TurnPhase -> Model -> ( Model, Cmd Msg )
countdownPhaseSet phase model =
    ( withConditionUi (\u -> { u | countdownPhase = phase }) model, Cmd.none )


saveToggle : Model -> ( Model, Cmd Msg )
saveToggle model =
    ( withConditionUi
        (\u ->
            { u
                | saveToEnd =
                    case u.saveToEnd of
                        Just _ ->
                            Nothing

                        Nothing ->
                            Just ConditionUi.freshSaveToEnd
            }
        )
        model
    , Cmd.none
    )


saveAbilityChanged : String -> Model -> ( Model, Cmd Msg )
saveAbilityChanged ability model =
    ( withConditionUi
        (\u -> { u | saveToEnd = Maybe.map (\s -> { s | ability = ability }) u.saveToEnd })
        model
    , Cmd.none
    )


saveDcChanged : String -> Model -> ( Model, Cmd Msg )
saveDcChanged text model =
    ( withConditionUi
        (\u ->
            { u
                | saveToEnd =
                    Maybe.map
                        (\s ->
                            { s
                                | dcText = text
                                , dc =
                                    String.toInt (String.trim text)
                                        |> Maybe.withDefault s.dc
                            }
                        )
                        u.saveToEnd
            }
        )
        model
    , Cmd.none
    )


saveBonusChanged : String -> Model -> ( Model, Cmd Msg )
saveBonusChanged text model =
    ( withConditionUi
        (\u ->
            { u
                | saveToEnd =
                    Maybe.map
                        (\s ->
                            { s
                                | bonusText = text
                                , bonus =
                                    String.toInt (String.trim text)
                                        |> Maybe.withDefault s.bonus
                            }
                        )
                        u.saveToEnd
            }
        )
        model
    , Cmd.none
    )


saveAutoRollSet : Encounter.AutoRollMode -> Model -> ( Model, Cmd Msg )
saveAutoRollSet mode model =
    ( withConditionUi
        (\u ->
            { u
                | saveToEnd =
                    Maybe.map (\s -> { s | autoRoll = mode })
                        u.saveToEnd
            }
        )
        model
    , Cmd.none
    )


applyToSelectedToggle : Model -> ( Model, Cmd Msg )
applyToSelectedToggle model =
    ( withConditionUi (\u -> { u | applyToSelected = not u.applyToSelected }) model
    , Cmd.none
    )



-- ── PRESETS ──────────────────────────────────────────────────────────────


{-| GM clicked the Save button on the Add-Condition footer. Reveal
the name-prompt input by stashing an empty `pendingSaveName`. The
view replaces the static Save/Load buttons with `[input][Save]
[Cancel]` whenever `pendingSaveName /= Nothing`. Also closes the
load menu if it was open — only one preset affordance can be
active at a time.
-}
presetSaveStart : Model -> ( Model, Cmd Msg )
presetSaveStart model =
    ( withConditionUi
        (\u ->
            { u | pendingSaveName = Just "", loadMenuOpen = False }
        )
        model
    , Cmd.none
    )


presetSaveNameChanged : String -> Model -> ( Model, Cmd Msg )
presetSaveNameChanged text model =
    ( withConditionUi (\u -> { u | pendingSaveName = Just text }) model
    , Cmd.none
    )


presetSaveCancel : Model -> ( Model, Cmd Msg )
presetSaveCancel model =
    ( withConditionUi (\u -> { u | pendingSaveName = Nothing }) model
    , Cmd.none
    )


{-| Commit the current form state to the presets dict under the
user's typed name. Trimmed name; empty / whitespace-only names
are rejected (the input stays open so the GM can correct it).
Overwrites silently if a preset with the same name already
exists, per the user's spec — they explicitly didn't want a
confirm-prompt on overwrite.

Side effect: stamps the just-saved name into `loadedPresetName`
so the title bar shows it immediately, mirroring the load flow.

-}
presetSaveSubmit : Model -> ( Model, Cmd Msg )
presetSaveSubmit model =
    case model.modal of
        Just (ModalCondition ui) ->
            let
                trimmed =
                    Maybe.withDefault "" ui.pendingSaveName
                        |> String.trim
            in
            if String.isEmpty trimmed then
                ( model, Cmd.none )

            else
                let
                    preset =
                        ConditionUi.toPreset ui

                    newPresets =
                        Dict.insert trimmed preset model.conditionPresets
                in
                ( { model | conditionPresets = newPresets }
                    |> withConditionUi
                        (\u ->
                            { u
                                | pendingSaveName = Nothing
                                , loadedPresetName = Just trimmed
                            }
                        )
                , Cmd.none
                )

        _ ->
            ( model, Cmd.none )


presetLoadMenuToggle : Model -> ( Model, Cmd Msg )
presetLoadMenuToggle model =
    ( withConditionUi
        (\u ->
            { u
                | loadMenuOpen = not u.loadMenuOpen
                , pendingSaveName = Nothing
            }
        )
        model
    , Cmd.none
    )


presetLoadMenuClose : Model -> ( Model, Cmd Msg )
presetLoadMenuClose model =
    ( withConditionUi (\u -> { u | loadMenuOpen = False }) model
    , Cmd.none
    )


{-| Pick a preset from the load menu. Overlay its body onto the
current form state via `ConditionUi.applyPreset`, which preserves
target / editingId / applyToSelected and re-aims `untilCreature`
at the current target. No-op when the name isn't in the dict
(stale click after a delete, for example).
-}
presetLoad : String -> Model -> ( Model, Cmd Msg )
presetLoad name model =
    case Dict.get name model.conditionPresets of
        Just preset ->
            ( withConditionUi (ConditionUi.applyPreset name preset) model
            , Cmd.none
            )

        Nothing ->
            ( withConditionUi (\u -> { u | loadMenuOpen = False }) model
            , Cmd.none
            )


{-| Remove a preset by name. If the currently-loaded preset is
the one being deleted, also clear `loadedPresetName` so the title
bar drops the suffix — the form state is left alone so the GM
can keep editing the now-orphan configuration.
-}
presetDelete : String -> Model -> ( Model, Cmd Msg )
presetDelete name model =
    let
        newPresets =
            Dict.remove name model.conditionPresets
    in
    ( { model | conditionPresets = newPresets }
        |> withConditionUi
            (\u ->
                if u.loadedPresetName == Just name then
                    { u | loadedPresetName = Nothing }

                else
                    u
            )
    , Cmd.none
    )


{-| Flip the expand/collapse state of one category in the Load
menu's bundled-presets sections. Categories start collapsed
each time a fresh modal opens (`Ui.Condition.fresh` initialises
`expandedCategories = Set.empty`); the GM expands only the
ones they need to scan.
-}
presetCategoryToggle : String -> Model -> ( Model, Cmd Msg )
presetCategoryToggle category model =
    ( withConditionUi
        (\u ->
            { u
                | expandedCategories =
                    if Set.member category u.expandedCategories then
                        Set.remove category u.expandedCategories

                    else
                        Set.insert category u.expandedCategories
            }
        )
        model
    , Cmd.none
    )


{-| Validate that there's a name; empty-name conditions are
silently dropped (close the modal). Build a draft, then either
insert (creating) or update (editing).
-}
submit : Model -> ( Model, Cmd Msg )
submit model =
    case model.modal of
        Just (ModalCondition ui) ->
            let
                name =
                    String.trim ui.name
            in
            if String.isEmpty name then
                ( { model | modal = Nothing }, Cmd.none )

            else
                ( commitCondition ui name model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Delete from the modal's footer (only visible when editing).
-}
delete : Model -> ( Model, Cmd Msg )
delete model =
    case model.modal of
        Just (ModalCondition ui) ->
            case ui.editingId of
                Just id ->
                    ( { model
                        | encounter = Encounter.removeCondition ui.target id model.encounter
                        , modal = Nothing
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( { model | modal = Nothing }, Cmd.none )

        _ ->
            ( model, Cmd.none )


removeChip : String -> Int -> Model -> ( Model, Cmd Msg )
removeChip name id model =
    ( { model | encounter = Encounter.removeCondition name id model.encounter }
    , Cmd.none
    )


{-| Manual click on the chip's d20 save button. Same Cmd shape
as the auto-roll path, but flagged `wasAutoRoll = False` so a
successful save removes the condition silently rather than posting
a "Saved: <name>" notice on the card.
-}
rollSave : String -> Int -> Model -> ( Model, Cmd Msg )
rollSave name id model =
    case Encounter.findCondition name id model.encounter of
        Just ( _, cond ) ->
            case cond.saveToEnd of
                Just spec ->
                    ( model
                    , Dice.rollCmd (ConditionSaveLanded name id spec.dc False)
                        (Effects.saveSource cond name spec)
                        (Effects.saveExpression spec.bonus)
                    )

                Nothing ->
                    ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


{-| Save resolves: `roll.total >= dc` means the condition ends.
Look up the condition name BEFORE we remove it so the auto-roll
success path can post a notice with the right label. Manual rolls
remove silently.
-}
saveLanded : String -> Int -> Int -> Bool -> Dice.Roll -> Model -> ( Model, Cmd Msg )
saveLanded name id dc wasAutoRoll roll model =
    let
        conditionName =
            Encounter.findCondition name id model.encounter
                |> Maybe.map (\( _, cond ) -> cond.name)

        succeeded =
            roll.total >= dc

        m1 =
            if succeeded then
                let
                    removed =
                        { model
                            | encounter = Encounter.removeCondition name id model.encounter
                        }
                in
                case ( wasAutoRoll, conditionName ) of
                    ( True, Just label ) ->
                        { removed
                            | encounter =
                                Encounter.addSaveNotice name label removed.encounter
                        }

                    _ ->
                        removed

            else
                model

        ( pushed, flashCmd ) =
            Effects.pushDiceRoll roll m1
    in
    ( pushed
    , Cmd.batch [ Effects.persistDiceRoll roll, flashCmd ]
    )


saveNoticeDismiss : String -> Int -> Model -> ( Model, Cmd Msg )
saveNoticeDismiss name id model =
    ( { model | encounter = Encounter.removeSaveNotice name id model.encounter }
    , Cmd.none
    )



-- ── HELPERS ────────────────────────────────────────────────────────────


{-| Compute the `TurnTarget` discriminator for an "until-turn"
condition. The modal no longer asks the user — every condition
is "until the target's _next_ turn" — so we recover the existing
domain encoding from current encounter state at submit time.

The semantic: "the condition expires at the begin/end of the
target creature's turn, when that target's turn next comes up."

  - Target is currently active AND phase = AtEnd: the next AtEnd
    fire will be this current turn ending, but the GM means the
    _next_ one — so we encode `OnNextTurn` (skip first match).
  - All other cases: the first matching hook fire is already the
    target's next turn (AtBegin while target is active means the
    begin already happened; AtBegin/AtEnd while target is inactive
    means the first match is on their next turn). Encode as
    `OnCurrentTurn` (expire on first match).

-}
nextTurnTarget : ConditionUi -> Model -> Encounter.TurnTarget
nextTurnTarget ui model =
    if
        ui.untilCreature
            == model.encounter.activeName
            && ui.untilPhase
            == Encounter.AtEnd
    then
        Encounter.OnNextTurn

    else
        Encounter.OnCurrentTurn


{-| Translate the modal's UI state into a domain-level
`ConditionDraft`, then either insert it (when creating) or replace
the existing condition's fields (when editing). The "skip first
end-of-turn tick" rule is applied here for AtEnd countdowns
created on the currently-active creature.
-}
commitCondition : ConditionUi -> String -> Model -> Model
commitCondition ui name model =
    let
        duration =
            buildDuration ui model

        saveToEnd =
            Maybe.map
                (\s ->
                    { ability = s.ability
                    , dc = s.dc
                    , bonus = s.bonus
                    , autoRoll = s.autoRoll
                    }
                )
                ui.saveToEnd

        draft =
            { name = name
            , note = String.trim ui.note
            , duration = duration
            , saveToEnd = saveToEnd
            }
    in
    case ui.editingId of
        Just id ->
            { model
                | encounter =
                    Encounter.updateCondition ui.target
                        id
                        (\c ->
                            { c
                                | name = draft.name
                                , note = draft.note
                                , duration = draft.duration
                                , saveToEnd = draft.saveToEnd
                            }
                        )
                        model.encounter
                , modal = Nothing
            }

        Nothing ->
            let
                targets =
                    conditionTargets ui model.encounter

                addOne tgt enc =
                    Encounter.addCondition tgt draft enc
            in
            { model
                | encounter = List.foldl addOne model.encounter targets
                , modal = Nothing
            }


{-| Resolve which creatures a new condition applies to. When
`applyToSelected` is True, every creature with `selected = True`
gets a fresh copy (each gets its own id via `addCondition`).
Otherwise just the modal's `target`.
-}
conditionTargets : ConditionUi -> Encounter.Encounter -> List String
conditionTargets ui enc =
    if ui.applyToSelected then
        enc.creatures
            |> List.filter .selected
            |> List.map .name

    else
        [ ui.target ]


{-| Build the domain `Duration` from the UI's three sub-states.

For `DurKindCountdown` with `AtEnd` placed on the currently-active
creature, set `skipNextTick = True` so the bearer's imminent
end-of-turn (which is right around the corner) doesn't get counted
as a full turn.

-}
buildDuration : ConditionUi -> Model -> Encounter.Duration
buildDuration ui model =
    case ui.durationKind of
        DurKindManual ->
            Encounter.DurationManual

        DurKindUntilTurn ->
            Encounter.DurationUntilTurn
                ui.untilPhase
                (nextTurnTarget ui model)
                ui.untilCreature

        DurKindCountdown ->
            let
                isCurrentlyActive =
                    ui.target == model.encounter.activeName

                skipNextTick =
                    ui.countdownPhase == Encounter.AtEnd && isCurrentlyActive
            in
            Encounter.DurationCountdown ui.countdownPhase ui.countdownTurns skipNextTick
