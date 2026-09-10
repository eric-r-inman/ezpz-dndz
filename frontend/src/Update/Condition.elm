module Update.Condition exposing
    ( clear
    , countdownPhaseSet
    , countdownTurnsChanged
    , customNameChanged
    , damageTriggered
    , delete
    , durationKindSet
    , durationOneMinute
    , failDamageLanded
    , logToggle
    , maxConditionNoteLength
    , noteChanged
    , openEdit
    , openFor
    , pickStandard
    , presetCategoryToggle
    , presetDelete
    , presetLoad
    , presetLoadMenuClose
    , presetLoadMenuToggle
    , presetSaveCancel
    , presetSaveCategoryChanged
    , presetSaveNameChanged
    , presetSaveStart
    , presetSaveSubmit
    , removeChip
    , rollSave
    , saveAbilityChanged
    , saveAutoRollSet
    , saveBonusAdjust
    , saveBonusChanged
    , saveDcChanged
    , saveFailBecomesChanged
    , saveFailDamageChanged
    , saveLanded
    , saveNoticeDismiss
    , saveOnDamageSet
    , saveToggle
    , submit
    , submitSelected
    , undoLatest
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
import HpChange
import Model exposing (Model, Surface(..))
import Msg
    exposing
        ( DurationKind(..)
        , Msg(..)
        )
import Set
import Ui.Condition as ConditionUi exposing (ConditionUi)
import Ui.Condition.Bundled as Bundled


{-| The editor's own drawer entry, in the `Maybe Surface`
shape the pattern matches below were written against.
-}
drawerSurface : Model -> Maybe Surface
drawerSurface model =
    Model.drawerGet Model.conditionLens model
        |> Maybe.map SurfaceCondition


{-| Hard cap on the chip-note text, keeping the chip compact
enough that card row 1 doesn't wrap-overflow.
-}
maxConditionNoteLength : Int
maxConditionNoteLength =
    20


withConditionUi : (ConditionUi -> ConditionUi) -> Model -> Model
withConditionUi =
    Model.mapSurface Model.conditionLens


{-| A chip whose edit form is already open unfolds and scrolls
into view, the same as every other card control: the click asks
to see that condition. Every path scrolls the panel fully into
view, whether that means showing what is already open, or
opening it fresh onto the clicked condition.
-}
openEdit : String -> Int -> Model -> ( Model, Cmd Msg )
openEdit name id model =
    let
        nextModel =
            case drawerSurface model of
                Just (SurfaceCondition ui) ->
                    if ui.target == name && ui.editingId == Just id then
                        Model.unfoldDrawer Model.conditionLens model

                    else
                        openEditFresh name id model

                _ ->
                    openEditFresh name id model
    in
    ( nextModel
    , Effects.scrollDrawerIndex (Model.drawerIndexOf Model.conditionLens nextModel)
    )


openEditFresh : String -> Int -> Model -> Model
openEditFresh name id model =
    case Encounter.findCondition name id model.encounter of
        Just ( _, cond ) ->
            Model.openDrawer Model.conditionLens (ConditionUi.fromCondition name cond) model

        Nothing ->
            model


{-| Open the editor fresh for `target`, ready to add a new
condition — the gear icon's entry point, distinct from `openEdit`
which edits one the creature already carries. One already aimed
here unfolds and scrolls into view rather than being reset, the
same as every other editor's `openFor`.
-}
openFor : String -> Model -> ( Model, Cmd Msg )
openFor target model =
    let
        nextModel =
            case drawerSurface model of
                Just (SurfaceCondition ui) ->
                    if ui.target == target then
                        Model.unfoldDrawer Model.conditionLens model

                    else
                        Model.openDrawer Model.conditionLens (ConditionUi.fresh target) model

                _ ->
                    Model.openDrawer Model.conditionLens (ConditionUi.fresh target) model
    in
    ( nextModel
    , Effects.scrollDrawerIndex (Model.drawerIndexOf Model.conditionLens nextModel)
    )


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
    let
        clamped =
            String.left maxConditionNoteLength text
    in
    ( withConditionUi (\u -> { u | name = clamped, customName = clamped }) model
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
    ( withConditionUi
        (\u -> { u | durationKind = kind, useOneMinutePreset = False })
        model
    , Cmd.none
    )


{-| 1-Minute preset radio: snap the countdown fields to
turns=10 / phase=AtEnd and flag the preset so the radio stays
selected. Underlying durationKind becomes Countdown so the
existing build / persistence path handles the rest.
-}
durationOneMinute : Model -> ( Model, Cmd Msg )
durationOneMinute model =
    ( withConditionUi
        (\u ->
            { u
                | durationKind = DurKindCountdown
                , countdownTurns = 10
                , countdownTurnsText = "10"
                , countdownPhase = Encounter.AtEnd
                , useOneMinutePreset = True
            }
        )
        model
    , Cmd.none
    )


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

                -- Hand-editing turns means it's no longer the
                -- 1-Minute preset.
                , useOneMinutePreset = False
            }
        )
        model
    , Cmd.none
    )


countdownPhaseSet : Encounter.TurnPhase -> Model -> ( Model, Cmd Msg )
countdownPhaseSet phase model =
    ( withConditionUi
        (\u -> { u | countdownPhase = phase, useOneMinutePreset = False })
        model
    , Cmd.none
    )


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


{-| The Mod field's ▲ / ▼ spinner: nudge the bonus by one and
re-derive the text from it, matching the two-character field's
tighter typing room with a click path that reaches -10 or 20
either way.
-}
saveBonusAdjust : Int -> Model -> ( Model, Cmd Msg )
saveBonusAdjust delta model =
    ( withConditionUi
        (\u ->
            { u
                | saveToEnd =
                    Maybe.map
                        (\s ->
                            let
                                next =
                                    Basics.clamp -10 20 (s.bonus + delta)
                            in
                            { s | bonus = next, bonusText = String.fromInt next }
                        )
                        u.saveToEnd
            }
        )
        model
    , Cmd.none
    )


saveFailDamageChanged : String -> Model -> ( Model, Cmd Msg )
saveFailDamageChanged text model =
    ( withConditionUi
        (\u -> { u | saveToEnd = Maybe.map (\s -> { s | failDamageText = text }) u.saveToEnd })
        model
    , Cmd.none
    )


saveFailBecomesChanged : String -> Model -> ( Model, Cmd Msg )
saveFailBecomesChanged text model =
    ( withConditionUi
        (\u -> { u | saveToEnd = Maybe.map (\s -> { s | failBecomesText = text }) u.saveToEnd })
        model
    , Cmd.none
    )


saveOnDamageSet : Encounter.DamageTrigger -> Model -> ( Model, Cmd Msg )
saveOnDamageSet trigger model =
    ( withConditionUi
        (\u -> { u | saveToEnd = Maybe.map (\s -> { s | onDamage = trigger }) u.saveToEnd })
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



-- ── PRESETS ──────────────────────────────────────────────────────────────


{-| Empty every setting, keeping the target and the condition being
edited, if any, so the GM can rebuild the form from nothing.
-}
clear : Model -> ( Model, Cmd Msg )
clear model =
    ( withConditionUi
        (\u ->
            let
                blank =
                    ConditionUi.fresh u.target
            in
            { blank | editingId = u.editingId }
        )
        model
    , Cmd.none
    )


{-| GM clicked the Save button on the Add-Condition footer. Reveal
the name-prompt input by stashing an empty `pendingSaveName`. The
view replaces the static Save/Load buttons with `[input][Save]
[Cancel]` whenever `pendingSaveName /= Nothing`. Also closes the
load menu if it was open — only one preset affordance can be
active at a time.
-}
presetSaveStart : Model -> ( Model, Cmd Msg )
presetSaveStart model =
    let
        -- Pre-fill the category dropdown with the loaded preset's
        -- category when there is one, so "tweak + re-save" stays a
        -- single click in the dropdown.  Looks up via the merged
        -- view (user dict first, then bundled defaults) so a
        -- bundled preset loaded for tweaking still surfaces its
        -- canonical category.  Falls back to "" when no preset is
        -- loaded.
        prefillCategory =
            case drawerSurface model of
                Just (SurfaceCondition ui) ->
                    ui.loadedPresetName
                        |> Maybe.andThen (\name -> lookupPreset name model)
                        |> Maybe.map .category
                        |> Maybe.withDefault ""

                _ ->
                    ""
    in
    ( withConditionUi
        (\u ->
            { u
                | pendingSaveName = Just ""
                , pendingSaveCategory = prefillCategory
                , loadMenuOpen = False
            }
        )
        model
    , Cmd.none
    )


presetSaveNameChanged : String -> Model -> ( Model, Cmd Msg )
presetSaveNameChanged text model =
    ( withConditionUi (\u -> { u | pendingSaveName = Just text }) model
    , Cmd.none
    )


presetSaveCategoryChanged : String -> Model -> ( Model, Cmd Msg )
presetSaveCategoryChanged category model =
    ( withConditionUi (\u -> { u | pendingSaveCategory = category }) model
    , Cmd.none
    )


presetSaveCancel : Model -> ( Model, Cmd Msg )
presetSaveCancel model =
    ( withConditionUi
        (\u -> { u | pendingSaveName = Nothing, pendingSaveCategory = "" })
        model
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
    case drawerSurface model of
        Just (SurfaceCondition ui) ->
            let
                trimmed =
                    Maybe.withDefault "" ui.pendingSaveName
                        |> String.trim

                category =
                    String.trim ui.pendingSaveCategory
            in
            -- Both a name and a category are required.  Either
            -- missing keeps the save form open so the GM can
            -- correct it; the view-side `disabled` on the Save
            -- button already prevents the click in normal flow.
            if String.isEmpty trimmed || String.isEmpty category then
                ( model, Cmd.none )

            else
                let
                    preset =
                        ConditionUi.toPreset ui
                            |> (\p -> { p | category = category })

                    newPresets =
                        Dict.insert trimmed preset model.conditionPresets
                in
                ( { model | conditionPresets = newPresets }
                    |> withConditionUi
                        (\u ->
                            { u
                                | pendingSaveName = Nothing
                                , pendingSaveCategory = ""
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
                , pendingSaveCategory = ""
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
target / editingId and re-aims `untilCreature` at the current
target. No-op when the name isn't in the dict (stale click after
a delete, for example).
-}
presetLoad : String -> Model -> ( Model, Cmd Msg )
presetLoad name model =
    case lookupPreset name model of
        Just preset ->
            ( withConditionUi (ConditionUi.applyPreset name preset) model
            , Cmd.none
            )

        Nothing ->
            ( withConditionUi (\u -> { u | loadMenuOpen = False }) model
            , Cmd.none
            )


{-| Resolve a preset name against the user's dict first, falling
back to the bundled SRD defaults. Bundled entries are always
loadable even when the user has saved nothing of their own —
the view layer renders them as a read-only layer below any
user-saved overrides.
-}
lookupPreset : String -> Model -> Maybe ConditionUi.ConditionPreset
lookupPreset name model =
    case Dict.get name model.conditionPresets of
        Just preset ->
            Just preset

        Nothing ->
            Dict.get name Bundled.defaults


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


{-| Apply the form to the editor's own target.
-}
submit : Model -> ( Model, Cmd Msg )
submit model =
    case drawerSurface model of
        Just (SurfaceCondition ui) ->
            submitTo [ ui.target ] model

        _ ->
            ( model, Cmd.none )


{-| Apply the form to every selected creature; each one gets its
own copy of the condition.
-}
submitSelected : Model -> ( Model, Cmd Msg )
submitSelected model =
    submitTo
        (model.encounter.creatures
            |> List.filter .selected
            |> List.map .name
        )
        model


{-| Validate that there's a name; empty-name conditions are
silently dropped. Build a draft, then either insert it (creating)
or update the edited condition.
-}
submitTo : List String -> Model -> ( Model, Cmd Msg )
submitTo rawTargets model =
    case drawerSurface model of
        Just (SurfaceCondition ui) ->
            let
                targets =
                    Encounter.excludingPlaceholderNames model.encounter rawTargets

                name =
                    String.trim ui.name
            in
            if String.isEmpty name then
                ( Model.foldDrawer Model.conditionLens model, Cmd.none )

            else
                let
                    ( committed, logEntry ) =
                        commitCondition targets ui name model

                    withLog =
                        case logEntry of
                            Just entry ->
                                { committed
                                    | conditionLog =
                                        entry
                                            :: List.take
                                                (ConditionUi.maxConditionLogEntries - 1)
                                                committed.conditionLog
                                    , nextConditionLogSeq = committed.nextConditionLogSeq + 1
                                    , conditionLogOpen = True
                                }

                            Nothing ->
                                committed
                in
                ( withLog, Cmd.none )

        _ ->
            ( model, Cmd.none )


logToggle : Model -> ( Model, Cmd Msg )
logToggle model =
    ( { model | conditionLogOpen = not model.conditionLogOpen }, Cmd.none )


{-| Undo the newest condition application: remove every condition
instance that application created (by the ids captured at add
time), then drop the entry so the next undo chains backwards.
Instances the GM already removed by hand no-op harmlessly.
-}
undoLatest : Model -> ( Model, Cmd Msg )
undoLatest model =
    case model.conditionLog of
        entry :: rest ->
            ( { model
                | encounter =
                    List.foldl
                        (\t enc -> Encounter.removeCondition t.name t.conditionId enc)
                        model.encounter
                        entry.targets
                , conditionLog = rest
              }
            , Cmd.none
            )

        [] ->
            ( model, Cmd.none )


{-| Delete from the modal's footer (only visible when editing).
-}
delete : Model -> ( Model, Cmd Msg )
delete model =
    case drawerSurface model of
        Just (SurfaceCondition ui) ->
            case ui.editingId of
                Just id ->
                    ( { model
                        | encounter = Encounter.removeCondition ui.target id model.encounter
                        , surface = Nothing
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( Model.foldDrawer Model.conditionLens model, Cmd.none )

        _ ->
            ( model, Cmd.none )


removeChip : String -> Int -> Model -> ( Model, Cmd Msg )
removeChip name id model =
    ( { model | encounter = Encounter.removeCondition name id model.encounter }
    , Cmd.none
    )


{-| Manual click on the chip's d20 save button. Same Cmd shape
and same landing handler as the auto-roll path — a success posts
the same "Saved: <name>" notice either way.
-}
rollSave : String -> Int -> Model -> ( Model, Cmd Msg )
rollSave name id model =
    case Encounter.findCondition name id model.encounter of
        Just ( _, cond ) ->
            case cond.saveToEnd of
                Just spec ->
                    ( model
                    , Dice.rollCmd (ConditionSaveLanded name id spec.dc)
                        (Effects.saveSource cond name spec)
                        (Effects.saveExpression spec.bonus)
                    )

                Nothing ->
                    ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


{-| Save resolves: `roll.total >= dc` means the condition ends.
Look up the condition BEFORE we remove it so a success can post a
"Saved: <name>" notice with the right label, whether the roll was
auto-fired or the GM clicked the chip's own d20. A failure hands
off to the condition's failed-save outcome, if it has one.
-}
saveLanded : String -> Int -> Int -> Dice.Roll -> Model -> ( Model, Cmd Msg )
saveLanded name id dc roll model =
    let
        found =
            Encounter.findCondition name id model.encounter
                |> Maybe.map Tuple.second

        ( m1, failCmd ) =
            if roll.total >= dc then
                let
                    removed =
                        { model
                            | encounter = Encounter.removeCondition name id model.encounter
                        }
                in
                case found of
                    Just cond ->
                        ( { removed
                            | encounter =
                                Encounter.addSaveNotice name cond.name removed.encounter
                          }
                        , Cmd.none
                        )

                    Nothing ->
                        ( removed, Cmd.none )

            else
                failedSave name id found model

        ( pushed, broadcastCmd ) =
            Effects.pushDiceRoll roll m1
    in
    ( pushed
    , Cmd.batch [ Effects.persistDiceRoll roll, broadcastCmd, failCmd ]
    )


{-| A failed repeat save: the condition becomes what the spec says
it becomes — which also ends the saving, as a second failure that
petrifies leaves nothing to save against — and the bearer takes
the spec's damage, an integer at once and a formula through a
roll of its own.
-}
failedSave : String -> Int -> Maybe Encounter.Condition -> Model -> ( Model, Cmd Msg )
failedSave name id found model =
    case Maybe.andThen .saveToEnd found of
        Nothing ->
            ( model, Cmd.none )

        Just spec ->
            let
                label =
                    found |> Maybe.map .name |> Maybe.withDefault ""

                renamed =
                    case spec.onFail.becomes of
                        Just newName ->
                            { model
                                | encounter =
                                    Encounter.updateCondition name
                                        id
                                        (\c -> { c | name = newName, saveToEnd = Nothing })
                                        model.encounter
                            }

                        Nothing ->
                            model
            in
            case Maybe.map String.trim spec.onFail.damage of
                Nothing ->
                    ( renamed, Cmd.none )

                Just raw ->
                    case String.toInt raw of
                        Just n ->
                            ( { renamed | encounter = damageBearer name n renamed.encounter }
                            , Cmd.none
                            )

                        Nothing ->
                            case Dice.parse raw of
                                Ok expr ->
                                    ( renamed
                                    , Dice.rollCmd (ConditionFailDamageLanded name)
                                        { feature = "Failed save: " ++ label, target = Just name }
                                        expr
                                    )

                                Err _ ->
                                    ( renamed, Cmd.none )


{-| The damage roll a failed save fired has landed on the bearer.
-}
failDamageLanded : String -> Dice.Roll -> Model -> ( Model, Cmd Msg )
failDamageLanded name roll model =
    let
        ( pushed, broadcastCmd ) =
            Effects.pushDiceRoll roll
                { model | encounter = damageBearer name roll.total model.encounter }
    in
    ( pushed
    , Cmd.batch [ Effects.persistDiceRoll roll, broadcastCmd ]
    )


damageBearer : String -> Int -> Encounter.Encounter -> Encounter.Encounter
damageBearer name amount enc =
    Encounter.mapCreature name (HpChange.apply (HpChange.Damage amount)) enc


{-| The pass `Main.update` runs after every message: a creature
whose hit points (temporary ones included) fell during the
message took damage, and each of its conditions that saves again
when damaged gets what its trigger asks for — a flash of the chip,
or a roll fired outright. A save's own resolution is left out, or
a condition whose failed save deals damage would roll itself
without end; so are the messages that swap in a whole encounter
from storage or another tab, whose numbers are not hits.
-}
damageTriggered : Msg -> Model -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
damageTriggered msg before ( after, cmd ) =
    if not (canTriggerSaves msg) then
        ( after, cmd )

    else
        let
            damaged =
                List.filter (tookDamage before.encounter) after.encounter.creatures
                    |> List.map .name

            flashes =
                List.concatMap (\name -> Encounter.damageReminders name after.encounter) damaged

            rolls =
                List.concatMap
                    (\name ->
                        Encounter.damageRolls name after.encounter
                            |> List.map (\( id, spec, advantage ) -> Effects.damageSaveCmd name id spec advantage)
                    )
                    damaged
        in
        if List.isEmpty flashes then
            ( after, Cmd.batch (cmd :: rolls) )

        else
            ( { after | flashConditions = flashes ++ after.flashConditions }
            , Cmd.batch (cmd :: Effects.saveFlashExpiry :: rolls)
            )


tookDamage : Encounter.Encounter -> Encounter.Creature -> Bool
tookDamage before c =
    before.creatures
        |> List.filter (\b -> b.name == c.name)
        |> List.head
        |> Maybe.map (\b -> c.currentHp + c.tempHp < b.currentHp + b.tempHp)
        |> Maybe.withDefault False


canTriggerSaves : Msg -> Bool
canTriggerSaves msg =
    case msg of
        ConditionSaveLanded _ _ _ _ ->
            False

        ConditionFailDamageLanded _ _ ->
            False

        EncounterLoaded _ ->
            False

        EncounterFromOtherTab _ ->
            False

        AuthMeReceived _ ->
            False

        LocalEncounterMigrated _ _ ->
            False

        SaveLoadLoadRequested _ ->
            False

        SaveLoadServerResponse _ _ ->
            False

        SaveLoadDeviceFileRead _ ->
            False

        EncounterReset ->
            False

        EncounterClear ->
            False

        HpChangeUndoLatest ->
            False

        _ ->
            True


nonBlank : String -> Maybe String
nonBlank text =
    if String.isEmpty (String.trim text) then
        Nothing

    else
        Just (String.trim text)


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
commitCondition : List String -> ConditionUi -> String -> Model -> ( Model, Maybe ConditionUi.ConditionLogEntry )
commitCondition targets ui name model =
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
                    , onFail =
                        { damage = nonBlank s.failDamageText
                        , becomes = nonBlank s.failBecomesText
                        }
                    , onDamage = s.onDamage
                    }
                )
                ui.saveToEnd

        draft =
            { name = name
            , note = String.trim ui.note
            , duration = duration
            , saveToEnd = saveToEnd
            , linkedTo = Nothing
            , area = Nothing
            }
    in
    case ui.editingId of
        Just id ->
            ( { model
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
              }
            , Nothing
            )

        Nothing ->
            let
                addOne tgt acc =
                    let
                        ( withAdded, newId ) =
                            Encounter.addConditionWithId tgt draft acc.encounter
                    in
                    { encounter = withAdded
                    , applied = { name = tgt, conditionId = newId } :: acc.applied
                    }

                result =
                    List.foldl addOne { encounter = model.encounter, applied = [] } targets
            in
            ( { model | encounter = result.encounter }
            , if List.isEmpty result.applied then
                Nothing

              else
                Just
                    { seq = model.nextConditionLogSeq
                    , conditionName = draft.name
                    , note = draft.note
                    , summary = summarize draft.duration saveToEnd
                    , targets = List.reverse result.applied
                    }
            )


{-| The log row's one-line account of what was applied: the
duration, and the save that can end it sooner.
-}
summarize : Encounter.Duration -> Maybe { a | ability : String, dc : Int, autoRoll : Encounter.AutoRollMode } -> String
summarize duration saveToEnd =
    Encounter.describeDuration duration
        ++ (case saveToEnd of
                Just spec ->
                    " · DC " ++ String.fromInt spec.dc ++ " " ++ spec.ability ++ " save" ++ saveTiming spec.autoRoll

                Nothing ->
                    ""
           )


saveTiming : Encounter.AutoRollMode -> String
saveTiming mode =
    case mode of
        Encounter.AutoRollManual ->
            ", rolled by hand"

        Encounter.AutoRollAtBegin ->
            " at start of turn"

        Encounter.AutoRollAtEnd ->
            " at end of turn"

        Encounter.AutoRollAskAtEnd ->
            ", asked at end of turn"


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

        DurKindThisTurn ->
            Encounter.DurationUntilTurn Encounter.AtEnd Encounter.OnCurrentTurn ui.target

        DurKindCountdown ->
            let
                isCurrentlyActive =
                    ui.target == model.encounter.activeName

                skipNextTick =
                    ui.countdownPhase == Encounter.AtEnd && isCurrentlyActive
            in
            Encounter.DurationCountdown ui.countdownPhase ui.countdownTurns skipNextTick
