module Update.Condition exposing
    ( applyToSelectedToggle
    , close
    , countdownPhaseSet
    , countdownTurnsChanged
    , currentTurnInvalid
    , customNameChanged
    , delete
    , durationKindSet
    , maxConditionNoteLength
    , noteChanged
    , openEdit
    , openNew
    , pickStandard
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
    , untilTargetSet
    )

{-| Update branches for the condition / effect modal: the radio
list of standard conditions, custom-name field, the duration-kind
selector (manual / until-turn / countdown), the optional save-to-end
sub-form, the multi-target toggle, the submit / delete actions, the
chip-level remove + roll-save buttons on cards, and the
saving-throw result handler.
-}

import Dice
import Effects
import Encounter
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( DurationKind(..)
        , Msg(..)
        )
import Ui.Condition as ConditionUi exposing (ConditionUi)


{-| Hard cap on the chip-note text. Ten characters keeps the chip
small and prevents wrap-overflow on the card row 1.
-}
maxConditionNoteLength : Int
maxConditionNoteLength =
    10


withConditionUi : (ConditionUi -> ConditionUi) -> Model -> Model
withConditionUi fn model =
    case model.modal of
        Just (ModalCondition ui) ->
            { model | modal = Just (ModalCondition (fn ui)) }

        _ ->
            model


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
    ( withConditionUi (\u -> { u | name = label, customName = "" }) model
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


{-| Switching the reference creature can make "begin + current"
newly invalid (or no longer invalid). Repair the target field if
so — the GM doesn't want to babysit the radio after a dropdown
change.
-}
untilCreatureChanged : String -> Model -> ( Model, Cmd Msg )
untilCreatureChanged name model =
    ( withConditionUi
        (\u -> repairUntilTarget model { u | untilCreature = name })
        model
    , Cmd.none
    )


untilPhaseSet : Encounter.TurnPhase -> Model -> ( Model, Cmd Msg )
untilPhaseSet phase model =
    ( withConditionUi
        (\u -> repairUntilTarget model { u | untilPhase = phase })
        model
    , Cmd.none
    )


untilTargetSet : Encounter.TurnTarget -> Model -> ( Model, Cmd Msg )
untilTargetSet target model =
    ( withConditionUi (\u -> { u | untilTarget = target }) model, Cmd.none )


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


{-| Manual click on the save chip's d20 button. Same Cmd shape as
the auto-roll path, but flagged `wasAutoRoll = False` so a
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
    in
    ( m1 |> Effects.pushDiceRoll roll
    , Effects.persistDiceRoll roll
    )


saveNoticeDismiss : String -> Int -> Model -> ( Model, Cmd Msg )
saveNoticeDismiss name id model =
    ( { model | encounter = Encounter.removeSaveNotice name id model.encounter }
    , Cmd.none
    )



-- ── HELPERS ────────────────────────────────────────────────────────────


{-| Auto-correct the `untilTarget` field if the current
phase / creature combo has made `OnCurrentTurn` nonsensical.

A "Begin + Current turn" pairing is logically invalid when the
reference creature is currently active: the begin of their current
turn already fired when they became active, so there's no future
hook to expire on. Flip to `OnNextTurn` so the condition has a
real expiration point.

-}
repairUntilTarget : Model -> ConditionUi -> ConditionUi
repairUntilTarget model ui =
    if currentTurnInvalid model ui && ui.untilTarget == Encounter.OnCurrentTurn then
        { ui | untilTarget = Encounter.OnNextTurn }

    else
        ui


{-| True when `OnCurrentTurn` would be a no-op — only the
"Begin + active reference creature" case for now.
-}
currentTurnInvalid : Model -> ConditionUi -> Bool
currentTurnInvalid model ui =
    ui.untilPhase == Encounter.AtBegin && ui.untilCreature == model.encounter.activeName


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
            Encounter.DurationUntilTurn ui.untilPhase ui.untilTarget ui.untilCreature

        DurKindCountdown ->
            let
                isCurrentlyActive =
                    ui.target == model.encounter.activeName

                skipNextTick =
                    ui.countdownPhase == Encounter.AtEnd && isCurrentlyActive
            in
            Encounter.DurationCountdown ui.countdownPhase ui.countdownTurns skipNextTick
