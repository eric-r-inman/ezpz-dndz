module Main exposing (main)

import Browser
import Browser.Dom
import Browser.Events
import Browser.Navigation as Nav
import Compendium
import Compendium.Parser
import Compendium.Wire
import Dice
import Effects
import Encounter
    exposing
        ( Cover(..)
        , Creature
        , Encounter
        )
import Encounter.Roster
import Encounter.Wire
import File exposing (File)
import File.Select
import HpChange
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, preventDefaultOn, stopPropagationOn)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Model exposing (Model)
import Msg
    exposing
        ( CompendiumField(..)
        , CompendiumSort(..)
        , DurationKind(..)
        , FeatureGroup(..)
        , HpField(..)
        , HpInputMode(..)
        , HpKind(..)
        , MeInfo
        , MeStatus(..)
        , Msg(..)
        , RollMode(..)
        , RollScope(..)
        )
import Process
import Random
import Route exposing (Route(..))
import Set exposing (Set)
import Task
import Ui.Compendium as CompendiumUi
    exposing
        ( CompendiumDb(..)
        , CompendiumEditUi
        , CompendiumPasteUi
        , CompendiumUi
        , EditMode(..)
        , FeatureDraft
        , PendingAction(..)
        )
import Ui.Condition as ConditionUi exposing (ConditionUi, SaveToEndUi)
import Ui.Dice as DiceUi exposing (DiceUi)
import Ui.HpChange as HpChangeUi exposing (HpChangeEntry, HpChangeUi, HpEdit)
import Ui.Initiative as InitiativeUi exposing (InitiativeUi)
import Ui.Memo as MemoUi exposing (MemoEditUi)
import Ui.Note as NoteUi exposing (NoteEditUi)
import Ui.Timer as TimerUi exposing (TimerSetupUi)
import Ui.Toast as ToastUi exposing (Toast, ToastKind(..))
import Update.Compendium
import Update.Condition
import Update.DeathSave
import Update.Dice
import Update.Encounter
import Update.HpChange
import Update.Initiative
import Update.LegendaryPip
import Update.Memo
import Update.Note
import Update.Shell
import Update.Timer
import Update.Toast
import Url exposing (Url)
import Util.Http
import Util.Keyboard
import View.AppBar
import View.Audio
import View.Modal
import View.Modal.Condition
import View.Modal.Dice
import View.Modal.HpChange
import View.Modal.Initiative
import View.Modal.Memo
import View.Modal.Note
import View.Modal.Timer
import View.PhaseToggle
import View.StatBlock
import View.Toast



-- The Model record alias lives in `Model.elm`; the route ADT
-- + URL parser live in `Route.elm`.  Both are imported below.


{-| Every message the runtime can send the update loop. Per-creature
messages carry the target creature's `name` as their identity; that's
how we look up which row of `encounter.creatures` to operate on.

`NextTurn` advances the queue one slot — it's the first piece of real
turn logic in the app and the place where future per-phase hooks
(begin / end / off / on) will land as separate pure functions.

-}
main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }


{-| Subscribe to keyboard events while the dice modal is open so Esc
can close it. Other routes don't need any subscriptions yet.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    if model.dice.open then
        Browser.Events.onKeyDown (escKey CloseDice)

    else if model.compendiumPaste /= Nothing then
        Browser.Events.onKeyDown (escKey CompendiumPasteCancel)

    else if model.compendiumEdit /= Nothing then
        Browser.Events.onKeyDown (escKey CompendiumEditCancel)

    else if model.compendium.open then
        Browser.Events.onKeyDown compendiumKeyDecoder

    else if model.noteEdit /= Nothing then
        Browser.Events.onKeyDown (escKey NoteEditCancel)

    else
        Sub.none


{-| Browser-modal keyboard decoder: `Esc` closes, `/` focuses
the search input. Both shortcuts ignore events whose target is
already an input/textarea so the GM doesn't trip them while
typing in the search box, the count input, or anywhere else.
-}
compendiumKeyDecoder : Decode.Decoder Msg
compendiumKeyDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "key" Decode.string)
        (Decode.at [ "target", "tagName" ] Decode.string)
        |> Decode.andThen
            (\( key, tagName ) ->
                case ( key, isFormTag tagName ) of
                    ( "Escape", _ ) ->
                        Decode.succeed CompendiumClose

                    ( "/", False ) ->
                        Decode.succeed CompendiumFocusSearch

                    _ ->
                        Decode.fail "ignored key"
            )


isFormTag : String -> Bool
isFormTag tagName =
    case tagName of
        "INPUT" ->
            True

        "TEXTAREA" ->
            True

        "SELECT" ->
            True

        _ ->
            False


escKey : Msg -> Decode.Decoder Msg
escKey =
    Util.Keyboard.escKey


init : () -> Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        route =
            Route.fromUrl url
    in
    ( { key = key
      , url = url
      , route = route
      , me = Loading
      , encounter = Encounter.empty
      , dice = DiceUi.empty
      , hpChange = Nothing
      , hpChangeLog = []
      , hpEdit = Nothing
      , initiative = Nothing
      , noteEdit = Nothing
      , conditionUi = Nothing
      , memoEdit = Nothing
      , timerSetup = Nothing
      , compendium = CompendiumUi.emptyCompendium
      , compendiumEdit = Nothing
      , compendiumPaste = Nothing
      , panelCreatureId = Nothing
      , toasts = []
      , nextToastId = 0
      }
      -- Always fetch the persisted dice history and the compendium
      -- library alongside whatever the current route needs. Failures
      -- are silently swallowed so a fresh server (no
      -- dice-history.json yet) still loads.
    , Cmd.batch
        [ Effects.cmdForRoute route
        , Effects.fetchDiceHistory
        , Compendium.Wire.fetchAll CompendiumLoaded
        , Encounter.Wire.fetchEncounterCmd EncounterLoaded
        ]
    )


{-| Top-level update wrapper: dispatches to `updateInner` and then,
if the encounter mutated as a result, batches a persist Cmd so the
save survives a page reload.

The diff-and-persist trick keeps the per-Msg branches focused on
their own work — they don't have to remember to call a save
helper. Only equality matters: trivial UI-state changes (modal
opens, toast pushes, etc.) leave the encounter untouched, so no
save fires for them.

The two save-flow Msgs themselves (`EncounterLoaded`,
`EncounterPersisted`) skip the diff to avoid an obvious infinite
loop where loading a saved encounter would re-trigger a save.

-}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        ( next, innerCmd ) =
            updateInner msg model

        saveCmd =
            if shouldPersistAfter msg && next.encounter /= model.encounter then
                Encounter.Wire.persistEncounterCmd EncounterPersisted next.encounter

            else
                Cmd.none
    in
    ( next, Cmd.batch [ innerCmd, saveCmd ] )


shouldPersistAfter : Msg -> Bool
shouldPersistAfter msg =
    case msg of
        EncounterLoaded _ ->
            False

        EncounterPersisted _ ->
            False

        _ ->
            True


updateInner : Msg -> Model -> ( Model, Cmd Msg )
updateInner msg model =
    case msg of
        UrlRequested req ->
            Update.Shell.urlRequested model.key req model

        UrlChanged url ->
            Update.Shell.urlChanged url model

        GotMe result ->
            Update.Shell.gotMe result model

        NextTurn ->
            Update.Encounter.nextTurn model

        SetActive name ->
            Update.Encounter.setActive name model

        ToggleSurprised name ->
            Update.Encounter.toggleSurprised name model

        CycleCover name ->
            Update.Encounter.cycleCover name model

        ToggleConcentration name ->
            Update.Encounter.toggleConcentration name model

        ToggleHiding name ->
            Update.Encounter.toggleHiding name model

        ToggleFlying name ->
            Update.Encounter.toggleFlying name model

        AdjustFlyHeight name delta ->
            Update.Encounter.adjustFlyHeight name delta model

        DeathSaveToggleSuccess name idx ->
            Update.DeathSave.toggleSuccess name idx model

        DeathSaveToggleFailure name idx ->
            Update.DeathSave.toggleFailure name idx model

        DeathSaveRoll name ->
            Update.DeathSave.roll name model

        DeathSaveRollLanded name roll ->
            Update.DeathSave.rollLanded name roll model

        ToggleHolding name ->
            Update.Encounter.toggleHolding name model

        -- Dice modal lifecycle
        OpenDice ->
            Update.Dice.open model

        CloseDice ->
            Update.Dice.close model

        DiceInputChanged text ->
            Update.Dice.inputChanged text model

        DiceCountChanged text ->
            Update.Dice.countChanged text model

        DiceModifierChanged text ->
            Update.Dice.modifierChanged text model

        DiceResetSliders ->
            Update.Dice.resetSliders model

        DiceRollFromInput ->
            Update.Dice.rollFromInput model

        DiceRollFaces faces ->
            Update.Dice.rollFaces faces model

        DiceRollAdvantage ->
            Update.Dice.rollAdvantage model

        DiceRollDisadvantage ->
            Update.Dice.rollDisadvantage model

        DiceFlipCoin ->
            Update.Dice.flipCoin model

        DiceRerun roll ->
            Update.Dice.rerun roll model

        DiceClearHistory ->
            Update.Dice.clearHistory model

        DiceRollLanded roll ->
            Update.Dice.rollLanded roll model

        DiceHistoryLoaded result ->
            Update.Dice.historyLoaded result model

        DicePersistResponse result ->
            Update.Dice.persistResponse result model

        DiceClearResponse result ->
            Update.Dice.clearResponse result model

        RollFromStatBlock creatureName expr ->
            Update.Dice.rollFromStatBlock creatureName expr model

        -- HP change modal lifecycle
        HpChangeOpen target kind ->
            Update.HpChange.open target kind model

        HpChangeClose ->
            Update.HpChange.close model

        HpChangeModeSet mode ->
            Update.HpChange.modeSet mode model

        HpChangeAmountChanged text ->
            Update.HpChange.amountChanged text model

        HpChangeExpressionChanged text ->
            Update.HpChange.expressionChanged text model

        HpChangeIgnoreTempToggle ->
            Update.HpChange.ignoreTempToggle model

        HpChangeApplyToSelectedToggle ->
            Update.HpChange.applyToSelectedToggle model

        HpChangeApply ->
            Update.HpChange.apply model

        HpChangeRollLanded roll ->
            Update.HpChange.rollLanded roll model

        HpEditStart name field current ->
            Update.HpChange.editStart name field current model

        HpEditChange text ->
            Update.HpChange.editChange text model

        HpEditCommit ->
            Update.HpChange.editCommit model

        HpEditCancel ->
            Update.HpChange.editCancel model

        -- Selection
        ToggleSelected name ->
            Update.Encounter.toggleSelected name model

        ShiftToggleSelected ->
            Update.Encounter.shiftToggleSelected model

        MoveCreatureUp name ->
            Update.Encounter.moveCreatureUp name model

        MoveCreatureDown name ->
            Update.Encounter.moveCreatureDown name model

        RemoveCreature name ->
            Update.Encounter.removeCreature name model

        DuplicateCreature name ->
            Update.Encounter.duplicateCreature name model

        -- Initiative manager
        InitiativeOpen target ->
            Update.Initiative.open target model

        InitiativeClose ->
            Update.Initiative.close model

        InitiativeCustomChanged text ->
            Update.Initiative.customChanged text model

        InitiativeQuickSort ->
            Update.Initiative.quickSort model

        InitiativeAutoRoll scope mode ->
            Update.Initiative.autoRoll scope mode model

        InitiativeApplyTarget ->
            Update.Initiative.applyTarget model

        InitiativeApplySelected ->
            Update.Initiative.applySelected model

        InitiativeRollsLanded results ->
            Update.Initiative.rollsLanded results model

        NoteEditOpen name current ->
            Update.Note.open name current model

        NoteEditChange text ->
            Update.Note.change text model

        NoteEditCommit ->
            Update.Note.commit model

        NoteEditCancel ->
            Update.Note.cancel model

        -- Condition / effect modal lifecycle
        ConditionOpenNew name ->
            Update.Condition.openNew name model

        ConditionOpenEdit name id ->
            Update.Condition.openEdit name id model

        ConditionClose ->
            Update.Condition.close model

        ConditionPickStandard label ->
            Update.Condition.pickStandard label model

        ConditionCustomNameChanged text ->
            Update.Condition.customNameChanged text model

        ConditionNoteChanged text ->
            Update.Condition.noteChanged text model

        ConditionDurationKindSet kind ->
            Update.Condition.durationKindSet kind model

        ConditionUntilCreatureChanged name ->
            Update.Condition.untilCreatureChanged name model

        ConditionUntilPhaseSet phase ->
            Update.Condition.untilPhaseSet phase model

        ConditionUntilTargetSet target ->
            Update.Condition.untilTargetSet target model

        ConditionCountdownTurnsChanged text ->
            Update.Condition.countdownTurnsChanged text model

        ConditionCountdownPhaseSet phase ->
            Update.Condition.countdownPhaseSet phase model

        ConditionSaveToggle ->
            Update.Condition.saveToggle model

        ConditionSaveAbilityChanged ability ->
            Update.Condition.saveAbilityChanged ability model

        ConditionSaveDcChanged text ->
            Update.Condition.saveDcChanged text model

        ConditionSaveBonusChanged text ->
            Update.Condition.saveBonusChanged text model

        ConditionSaveAutoRollSet mode ->
            Update.Condition.saveAutoRollSet mode model

        ConditionApplyToSelectedToggle ->
            Update.Condition.applyToSelectedToggle model

        ConditionSubmit ->
            Update.Condition.submit model

        ConditionDelete ->
            Update.Condition.delete model

        ConditionRemoveChip name id ->
            Update.Condition.removeChip name id model

        ConditionRollSave name id ->
            Update.Condition.rollSave name id model

        ConditionSaveLanded name id dc wasAutoRoll roll ->
            Update.Condition.saveLanded name id dc wasAutoRoll roll model

        SaveNoticeDismiss name id ->
            Update.Condition.saveNoticeDismiss name id model

        ActiveCardScrollChecked _ ->
            -- Result of the scroll-into-view Task. Either the scroll
            -- worked or the element wasn't found (defensive); either
            -- way, nothing further to do.
            ( model, Cmd.none )

        MemoOpen name ->
            Update.Memo.open name model

        MemoChange text ->
            Update.Memo.change text model

        MemoCommit ->
            Update.Memo.commit model

        MemoCancel ->
            Update.Memo.cancel model

        MemoClear name ->
            Update.Memo.clear name model

        TimerOpen name ->
            Update.Timer.open name model

        TimerSetupTurnsChanged text ->
            Update.Timer.turnsChanged text model

        TimerSetupPhaseSet phase ->
            Update.Timer.phaseSet phase model

        TimerSetupApply ->
            Update.Timer.apply model

        TimerSetupCancel ->
            Update.Timer.cancel model

        TimerDismiss name ->
            Update.Timer.dismiss name model

        CompendiumLoaded result ->
            Update.Compendium.loaded result model

        CompendiumOpen ->
            Update.Compendium.open model

        CompendiumClose ->
            Update.Compendium.close model

        CompendiumSearchChanged text ->
            Update.Compendium.searchChanged text model

        CompendiumKindToggled kind ->
            Update.Compendium.kindToggled kind model

        CompendiumSortChanged sort ->
            Update.Compendium.sortChanged sort model

        CompendiumSelect id ->
            Update.Compendium.select id model

        CompendiumAddCountChanged raw ->
            Update.Compendium.addCountChanged raw model

        CompendiumAddToQueue creatureId ->
            Update.Compendium.addToQueue creatureId model

        CompendiumInitiativeRolled creatureId rolls ->
            Update.Compendium.initiativeRolled creatureId rolls model

        CompendiumEditNew ->
            Update.Compendium.editNew model

        CompendiumEditExisting ->
            Update.Compendium.editExisting model

        CompendiumEditDuplicate ->
            Update.Compendium.editDuplicate model

        CompendiumEditCancel ->
            Update.Compendium.editCancel model

        CompendiumEditFieldChanged field text ->
            Update.Compendium.editFieldChanged field text model

        CompendiumEditKindSet kind ->
            Update.Compendium.editKindSet kind model

        CompendiumEditSizeSet size ->
            Update.Compendium.editSizeSet size model

        CompendiumEditSpeedHoverToggle ->
            Update.Compendium.editSpeedHoverToggle model

        CompendiumEditSavingThrowAdd ->
            Update.Compendium.editSavingThrowAdd model

        CompendiumEditSavingThrowRemove idx ->
            Update.Compendium.editSavingThrowRemove idx model

        CompendiumEditSavingThrowAbilitySet idx ability ->
            Update.Compendium.editSavingThrowAbilitySet idx ability model

        CompendiumEditSavingThrowBonusChanged idx text ->
            Update.Compendium.editSavingThrowBonusChanged idx text model

        CompendiumEditSkillAdd ->
            Update.Compendium.editSkillAdd model

        CompendiumEditSkillRemove idx ->
            Update.Compendium.editSkillRemove idx model

        CompendiumEditSkillNameChanged idx text ->
            Update.Compendium.editSkillNameChanged idx text model

        CompendiumEditSkillBonusChanged idx text ->
            Update.Compendium.editSkillBonusChanged idx text model

        CompendiumEditFeatureAdd group ->
            Update.Compendium.editFeatureAdd group model

        CompendiumEditFeatureRemove group idx ->
            Update.Compendium.editFeatureRemove group idx model

        CompendiumEditFeatureNameChanged group idx text ->
            Update.Compendium.editFeatureNameChanged group idx text model

        CompendiumEditFeatureDescriptionChanged group idx text ->
            Update.Compendium.editFeatureDescriptionChanged group idx text model

        CompendiumEditCustomSectionAdd ->
            Update.Compendium.editCustomSectionAdd model

        CompendiumEditCustomSectionRemove idx ->
            Update.Compendium.editCustomSectionRemove idx model

        CompendiumEditCustomSectionNameChanged idx text ->
            Update.Compendium.editCustomSectionNameChanged idx text model

        CompendiumEditCustomSectionBodyChanged idx text ->
            Update.Compendium.editCustomSectionBodyChanged idx text model

        CompendiumEditSubmit ->
            Update.Compendium.editSubmit model

        CompendiumEditSubmitResponse result ->
            Update.Compendium.editSubmitResponse result model

        CompendiumEditDelete ->
            Update.Compendium.editDelete model

        CompendiumEditDeleteResponse id result ->
            Update.Compendium.editDeleteResponse id result model

        CompendiumPasteOpen ->
            Update.Compendium.pasteOpen model

        CompendiumPasteCancel ->
            Update.Compendium.pasteCancel model

        CompendiumPasteTextChanged text ->
            Update.Compendium.pasteTextChanged text model

        CompendiumPasteApply ->
            Update.Compendium.pasteApply model

        PanelShowCreature creatureId ->
            Update.Compendium.panelShowCreature creatureId model

        ToggleLegendaryActionPip name idx ->
            Update.LegendaryPip.toggleAction name idx model

        ToggleLegendaryResistancePip name idx ->
            Update.LegendaryPip.toggleResistance name idx model

        EncounterLoaded result ->
            Update.Shell.encounterLoaded result model

        EncounterPersisted result ->
            Update.Shell.encounterPersisted result model

        CompendiumImportClick ->
            Update.Compendium.importClick model

        CompendiumImportFileChosen file ->
            Update.Compendium.importFileChosen file model

        CompendiumImportFileRead raw ->
            Update.Compendium.importFileRead raw model

        CompendiumResetClick ->
            Update.Compendium.resetClick model

        CompendiumDeleteFromBrowser id displayName ->
            Update.Compendium.deleteFromBrowser id displayName model

        CompendiumPendingCancel ->
            Update.Compendium.pendingCancel model

        CompendiumPendingConfirm ->
            Update.Compendium.pendingConfirm model

        CompendiumImportResponse result ->
            Update.Compendium.importResponse result model

        CompendiumResetResponse result ->
            Update.Compendium.resetResponse result model

        ToastDismiss id ->
            Update.Toast.dismiss id model

        CompendiumFocusSearch ->
            Update.Compendium.focusSearch model

        NoOp ->
            Update.Shell.noOp model


{-| Lift an `Encounter -> Encounter` transformation into a
`Model -> Model` transformation by threading it through the encounter
field. Keeps every per-creature update branch a one-liner and makes
the rest of `Model` (route, auth, nav key) literally invisible to
domain code, which is what the layering discipline demands.
-}
withEncounter : (Encounter -> Encounter) -> Model -> Model
withEncounter fn model =
    { model | encounter = fn model.encounter }


{-| Click handler for the row 1 selection checkbox.

We intercept the raw `click` event so we can read the Shift modifier:
holding Shift while clicking dispatches `ShiftToggleSelected` (bulk
select-all / deselect-all), and a plain click toggles just the
clicked creature. We always `preventDefault` so the browser doesn't
auto-toggle the checkbox visual — its `checked` attribute is driven
straight from the model on the next render, keeping a single source
of truth and avoiding the double-toggle that an `onCheck` listener
plus the browser's default would cause.

-}
selectionClickHandler : String -> Html.Attribute Msg
selectionClickHandler creatureName =
    preventDefaultOn "click"
        (Decode.field "shiftKey" Decode.bool
            |> Decode.map
                (\shift ->
                    if shift then
                        ( ShiftToggleSelected, True )

                    else
                        ( ToggleSelected creatureName, True )
                )
        )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "eZpZ-dndZ"
    , body =
        [ div [ class "app-shell" ]
            [ View.AppBar.view
            , viewPage model
            , View.Modal.Dice.view model.dice
            , View.Modal.HpChange.view model
            , View.Modal.Initiative.view model
            , View.Modal.Note.view model
            , View.Modal.Condition.view model
            , View.Modal.Memo.view model
            , View.Modal.Timer.view model
            , viewCompendiumModal model.compendium
            , viewCompendiumEditModal model.compendiumEdit
            , viewCompendiumPasteModal model.compendiumPaste
            , View.Toast.list model.toasts
            , View.Audio.ringer model
            ]
        ]
    }


viewPage : Model -> Html Msg
viewPage model =
    case model.route of
        Home ->
            viewWorkspace model

        Me ->
            div [ class "workspace" ]
                [ section [ class "panel panel--main" ]
                    [ div [ class "panel__header" ]
                        [ div [ class "panel__title" ] [ text "Account" ] ]
                    , div [ class "panel__body" ] [ View.AppBar.me model.me ]
                    ]
                ]

        CompendiumCreaturePage id ->
            viewCompendiumStandalone model id

        NotFound ->
            div [ class "workspace" ]
                [ section [ class "panel panel--main" ]
                    [ div [ class "panel__header" ]
                        [ div [ class "panel__title" ] [ text "Not Found" ] ]
                    , div [ class "panel__body" ]
                        [ p [ class "empty" ]
                            [ text "The page you requested does not exist." ]
                        ]
                    ]
                ]


{-| Standalone single-creature stat-block view at
`/compendium/creatures/:id`. Used as the deep link for the side
panel's ↗️ "open in new window" button — gives the GM a clean
reference page they can keep open in another window or print.

While the compendium fetch is in flight, render a loading
placeholder. If the fetch completes and the id isn't found,
render a 404-style message.

-}
viewCompendiumStandalone : Model -> String -> Html Msg
viewCompendiumStandalone model id =
    let
        body =
            case model.compendium.db of
                CompendiumDbLoading ->
                    p [ class "empty" ] [ text "Loading…" ]

                CompendiumDbFailed _ ->
                    p [ class "empty" ]
                        [ text "Couldn't load the compendium." ]

                CompendiumDbLoaded db ->
                    case Compendium.find id db of
                        Just creature ->
                            View.StatBlock.view RollFromStatBlock creature

                        Nothing ->
                            p [ class "empty" ]
                                [ text "Creature not found in the compendium." ]
    in
    div [ class "workspace workspace--standalone" ]
        [ section [ class "panel panel--standalone" ]
            [ div [ class "panel__body" ] [ body ] ]
        ]



-- WORKSPACE (mock)


viewWorkspace : Model -> Html Msg
viewWorkspace model =
    main_ [ class "workspace" ]
        [ viewPanelMain model.encounter model.hpEdit
        , viewPanelControls model.dice
        , viewPanelDetail model
        ]


{-| The encounter pane. `hpEdit` is threaded through so any open
inline-edit input (current/max HP) renders on the right card.
-}
viewPanelMain : Encounter -> Maybe HpEdit -> Html Msg
viewPanelMain enc hpEdit =
    section [ class "panel panel--main" ]
        [ div [ class "panel__header panel__header--encounter" ]
            [ viewEncounterBar enc ]
        , div [ class "panel__body" ]
            [ div [ class "creature-grid" ]
                (List.map (viewCreatureCard enc.activeName hpEdit) enc.creatures)
            ]
        ]


viewEncounterBar : Encounter -> Html Msg
viewEncounterBar enc =
    let
        active =
            Encounter.activeCreature enc

        activeName =
            Maybe.map .name active
                |> Maybe.withDefault "—"
    in
    div [ class "encounter-bar" ]
        [ div [ class "encounter-bar__group" ]
            [ span
                [ class "encounter-bar__info"
                , title "from file: "
                , attribute "aria-label" "Encounter file"
                , tabindex 0
                ]
                [ text "ⓘ" ]
            , span [ class "encounter-bar__round" ]
                [ text ("Round " ++ String.fromInt enc.round) ]
            , span [ class "encounter-bar__sep" ] [ text "|" ]
            , span [ class "encounter-bar__active" ] [ text activeName ]
            , viewEncounterBarHp active
            , span [ class "encounter-bar__hp-label" ] [ text "HP" ]
            , viewActiveStateIcons active
            , viewActiveConditionsText active
            ]
        , div [ class "encounter-bar__group encounter-bar__right" ]
            [ span [ class "encounter-bar__xp" ] [ text "93,000 XP" ]
            , span [ class "encounter-bar__xp-lair" ] [ text "(115,200 w/Lair)" ]
            , viewXpFilter
            ]
        ]


{-| HP readout for the encounter title bar. Reuses the same
.hp-display\* classes the card row 2 uses so the green/muted/blue
colors line up exactly. Renders an em-dash when no creature is
active (empty queue or activeName drift).
-}
viewEncounterBarHp : Maybe Creature -> Html Msg
viewEncounterBarHp active =
    case active of
        Just c ->
            span [ class "hp-display" ]
                [ span [ class "hp-display__current" ]
                    [ text (String.fromInt c.currentHp) ]
                , span [ class "hp-display__sep" ] [ text "/" ]
                , span [ class "hp-display__max" ]
                    [ text (String.fromInt c.maxHp) ]
                , if c.tempHp > 0 then
                    span
                        [ class "hp-display__temp"
                        , title "Temporary hit points"
                        ]
                        [ text ("+" ++ String.fromInt c.tempHp) ]

                  else
                    text ""
                ]

        Nothing ->
            span [ class "hp-display" ]
                [ span [ class "hp-display__max" ] [ text "—" ] ]


viewXpFilter : Html Msg
viewXpFilter =
    details [ class "xp-filter" ]
        [ summary
            [ class "xp-filter__summary"
            , attribute "aria-label" "Filter XP total"
            , title "Filter XP total"
            ]
            [ text "▾" ]
        , ul [ class "xp-filter__menu" ]
            [ li
                [ class "xp-filter__item"
                , attribute "aria-selected" "true"
                ]
                [ text "Enemies & NPCs" ]
            , li [ class "xp-filter__item" ] [ text "Enemies Only" ]
            , li [ class "xp-filter__item" ] [ text "NPCs Only" ]
            , li [ class "xp-filter__item" ] [ text "Selected Only" ]
            ]
        ]


{-| Latest dice-roll total displayed left of the Roll button. Bold
white integer (no formula, no source label) so the most recent
result is glanceable from across the table even with the modal
closed. Hidden when no rolls have landed yet.
-}
viewDiceLastTotal : DiceUi -> Html Msg
viewDiceLastTotal dice =
    case List.head dice.history.entries of
        Just roll ->
            span
                [ class "dice-last-total"
                , title "Last roll total"
                ]
                [ text (String.fromInt roll.total) ]

        Nothing ->
            text ""


{-| Left-facing arrow between the latest-total readout and the
Roll button, signalling that the number was emitted by the
roller. Hidden until at least one roll has landed so the cluster
isn't visually cluttered on first load.
-}
viewDiceArrow : DiceUi -> Html Msg
viewDiceArrow dice =
    if List.isEmpty dice.history.entries then
        text ""

    else
        span
            [ class "dice-arrow"
            , attribute "aria-hidden" "true"
            ]
            [ text "←" ]


viewPanelControls : DiceUi -> Html Msg
viewPanelControls dice =
    section [ class "panel panel--controls" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Encounter Controls" ]
            , div [ class "dice-roll-cluster" ]
                [ viewDiceLastTotal dice
                , viewDiceArrow dice
                , button
                    [ class
                        (if dice.unread then
                            "action-btn action-btn--green dice-roll-btn dice-roll-btn--unread"

                         else
                            "action-btn action-btn--green dice-roll-btn"
                        )
                    , onClick OpenDice
                    , title
                        (if dice.unread then
                            "Roll dice (new entries since last open)"

                         else
                            "Roll dice"
                        )
                    , attribute "aria-label" "Roll dice"
                    ]
                    [ text "🎲 Roll" ]
                ]
            ]
        , div [ class "panel__body" ]
            [ div [ class "btn-grid btn-grid--two-rows" ]
                [ button
                    [ class "action-btn action-btn--blue"
                    , onClick CompendiumOpen
                    , title "Browse the creature library"
                    ]
                    [ text "➕ Add Creature" ]
                , button [ class "action-btn action-btn--blue" ] [ text "💾 Save" ]
                , button [ class "action-btn action-btn--blue" ] [ text "📁 Load" ]
                , button
                    [ class "action-btn action-btn--green"
                    , onClick NextTurn
                    , title "Advance to the next creature in initiative order"
                    ]
                    [ text "⏭ Next Turn" ]
                , button [ class "action-btn action-btn--orange" ]
                    [ span [ class "btn-glyph" ] [ text "⟲" ]
                    , text " Reset"
                    ]
                , button [ class "action-btn action-btn--red" ] [ text "🗑 Clear" ]
                ]
            ]
        ]


viewPanelDetail : Model -> Html Msg
viewPanelDetail model =
    section [ class "panel panel--detail" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Compendium" ] ]
        , div [ class "panel__body" ]
            [ div [ class "btn-grid compendium-toolbar" ]
                [ button
                    [ class "action-btn action-btn--blue"
                    , onClick CompendiumOpen
                    , title "Open the creature library"
                    ]
                    [ text "📖 Open" ]
                , button
                    [ class "action-btn action-btn--blue"
                    , disabled True
                    , attribute "aria-disabled" "true"
                    , title "CR Calculator (not yet available)"
                    ]
                    [ text "⚔️ CR Calculator" ]
                ]
            , viewPanelStatBlock model
            ]
        ]


{-| The stat-block area in the side panel. Three states:

  - User has clicked a creature name with a compendium link AND
    the compendium's loaded → render the matched entry via
    `View.StatBlock.view` (clickable inline dice and all).
  - Compendium isn't loaded yet (rare race: the user clicks a
    name before the boot fetch lands) → fall through to the
    bundled mock so the panel isn't empty.
  - Nothing pinned → fall back to the bundled mock as a
    placeholder. This preserves the pre-Phase-3 default and
    gives users SOMETHING to look at on first load.

-}
viewPanelStatBlock : Model -> Html Msg
viewPanelStatBlock model =
    let
        pinned =
            case ( model.panelCreatureId, model.compendium.db ) of
                ( Just id, CompendiumDbLoaded db ) ->
                    Compendium.find id db

                _ ->
                    Nothing
    in
    case pinned of
        Just creature ->
            div [ class "panel-statblock" ]
                [ a
                    [ class "panel-statblock__open"
                    , href ("/compendium/creatures/" ++ creature.id)
                    , target "_blank"
                    , attribute "rel" "noopener"
                    , title "Open this creature's stat block in a new window"
                    , attribute "aria-label" "Open in new window"
                    ]
                    [ text "↗" ]
                , View.StatBlock.view RollFromStatBlock creature
                ]

        Nothing ->
            viewStatBlock mockStatBlock



-- COMPENDIUM MOCK DATA
--
-- The stat-block panel still renders against this hard-coded record;
-- it'll move into the domain layer alongside a real monster catalog
-- once the compendium feature actually does anything beyond display.


type alias StatBlock =
    { name : String
    , size : String
    , kind : String
    , alignment : String
    , armorClass : Int
    , hitPoints : String
    , speed : String
    , abilities : Abilities
    , traits : List ( String, String )
    }


type alias Abilities =
    { str : Int
    , dex : Int
    , con : Int
    , int : Int
    , wis : Int
    , cha : Int
    }


mockStatBlock : StatBlock
mockStatBlock =
    { name = "Brakka, Ogre Brute"
    , size = "Large"
    , kind = "giant"
    , alignment = "chaotic evil"
    , armorClass = 11
    , hitPoints = "59 (7d10 + 21)"
    , speed = "40 ft."
    , abilities =
        { str = 19
        , dex = 8
        , con = 16
        , int = 5
        , wis = 7
        , cha = 7
        }
    , traits =
        [ ( "Multiattack", "Brakka makes two greatclub attacks, or one greatclub attack and one javelin attack." )
        , ( "Greatclub", "Melee Weapon Attack: +6 to hit, reach 5 ft. Hit: 13 (2d8 + 4) bludgeoning damage." )
        , ( "Javelin", "Melee or Ranged Weapon Attack: +6 to hit, reach 5 ft. or range 30/120 ft. Hit: 11 (2d6 + 4) piercing damage." )
        , ( "Reckless", "At the start of its turn, Brakka can gain advantage on all melee weapon attack rolls during that turn, but attack rolls against it have advantage until the start of its next turn." )
        , ( "Brutish Charge", "If Brakka moves at least 10 feet straight toward a target and then hits it with a greatclub attack on the same turn, the target takes an extra 9 (2d8) bludgeoning damage and must succeed on a DC 14 Strength saving throw or be knocked prone." )
        , ( "Furious Roar", "Brakka unleashes a guttural roar. Each creature within 30 feet that can hear it must make a DC 13 Wisdom saving throw or be frightened until the end of Brakka's next turn." )
        , ( "Thick Hide", "Brakka has resistance to bludgeoning, piercing, and slashing damage from nonmagical attacks not made with silvered weapons." )
        ]
    }



-- CREATURE CARD


viewCreatureCard : String -> Maybe HpEdit -> Creature -> Html Msg
viewCreatureCard activeName hpEdit creature =
    let
        isActive =
            creature.name == activeName

        isDead =
            Encounter.isDeathSaveDead creature.deathSaves

        cardClass =
            String.join " "
                (List.filterMap identity
                    [ Just "creature-card"
                    , if isActive then
                        Just "creature-card--active"

                      else
                        Nothing
                    , if isDead then
                        Just "creature-card--dead"

                      else
                        Nothing
                    ]
                )
    in
    article [ id (Effects.cardId creature.name), class cardClass ]
        [ div [ class "creature-card__rail creature-card__rail--left" ]
            [ div [ class "creature-card__rail-group" ]
                [ input
                    [ type_ "checkbox"
                    , class "creature-card__select"
                    , checked creature.selected
                    , selectionClickHandler creature.name
                    , attribute "aria-label" ("Select " ++ creature.name)
                    , title "Shift-click to select / deselect all"
                    ]
                    []
                , button
                    [ class "icon-btn"
                    , onClick (MoveCreatureUp creature.name)
                    , title "Move up in queue (manual; ignores initiative)"
                    , attribute "aria-label" "Move up in queue"
                    ]
                    [ text "↑" ]
                , button
                    [ class "icon-btn"
                    , onClick (MoveCreatureDown creature.name)
                    , title "Move down in queue (manual; ignores initiative)"
                    , attribute "aria-label" "Move down in queue"
                    ]
                    [ text "↓" ]
                ]
            , div [ class "creature-card__rail-group" ]
                [ button
                    [ class "icon-btn icon-btn--accent"
                    , onClick (SetActive creature.name)
                    , title "Make active creature (does not advance the turn)"
                    , attribute "aria-label" "Make active"
                    ]
                    [ text "→" ]
                ]
            ]
        , div [ class "creature-card__center" ]
            [ viewCardRowTop creature
            , viewCardRowMid creature hpEdit
            , viewCardRowBot creature
            ]
        , viewLegendaryColumns creature
        , div [ class "creature-card__rail creature-card__rail--right" ]
            [ div [ class "creature-card__rail-group" ]
                [ button
                    [ class "icon-btn icon-btn--danger"
                    , onClick (RemoveCreature creature.name)
                    , title "Remove from queue"
                    , attribute "aria-label" "Remove"
                    ]
                    [ text "×" ]
                ]
            , div [ class "creature-card__rail-group" ]
                [ button
                    [ class "icon-btn"
                    , onClick (DuplicateCreature creature.name)
                    , title "Duplicate creature (insert below)"
                    , attribute "aria-label" "Duplicate"
                    ]
                    [ text "⧉" ]
                ]
            ]
        ]


viewCardRowTop : Creature -> Html Msg
viewCardRowTop creature =
    div [ class "creature-card__row creature-card__row--top" ]
        [ button
            [ class "init-circle init-circle--clickable"
            , onClick (InitiativeOpen creature.name)
            , title "Click to open the initiative manager"
            , attribute "aria-label"
                ("Initiative " ++ String.fromInt creature.initiative ++ " — open initiative manager")
            ]
            [ text (String.fromInt creature.initiative) ]
        , viewSurprisedToggle creature
        , viewCardCreatureName creature
        , viewNoteOrPencil creature
        , span [ class "ac-readout" ]
            [ text ("AC: " ++ String.fromInt creature.armorClass) ]
        , viewConditionChips creature
        ]


{-| The creature name on row 1 of each card. When the creature has
a `creatureId` back-reference to a compendium entry, the name is
rendered as a clickable element that pins that entry's stat block
in the side panel — and an underline-on-hover style hints at the
affordance. Legacy seed creatures (no compendium link) render as
a plain span.
-}
viewCardCreatureName : Creature -> Html Msg
viewCardCreatureName creature =
    case creature.creatureId of
        Just id ->
            span
                [ class "creature-name creature-name--default creature-name--linked"
                , onClick (PanelShowCreature id)
                , title "Show this creature's stat block in the side panel"
                ]
                [ text creature.name ]

        Nothing ->
            span [ class "creature-name creature-name--default" ]
                [ text creature.name ]


{-| Note-or-pencil sliver of row 1.

Empty note: just the pencil ✏️ button as an "add a note" affordance.

Non-empty note: the note itself (clickable, opens the same edit
modal so the user can rename or clear it) followed by a pipe
separator before the AC readout. The pencil is intentionally
hidden in this state — the note is now the click target, and
showing both would make the user wonder which one to use.

Returns a `List (Html Msg)` so the caller can splice it into the
row alongside the rest of the elements without a wrapper div
(which would break the row's flex gap).

-}
viewNoteOrPencil : Creature -> Html Msg
viewNoteOrPencil creature =
    if String.isEmpty creature.note then
        button
            [ class "icon-btn icon-btn--sm"
            , onClick (NoteEditOpen creature.name creature.note)
            , title "Add note"
            , attribute "aria-label" "Add note"
            ]
            [ text "✏️" ]

    else
        span [ class "creature-note-wrap" ]
            [ button
                [ class "creature-note creature-note--clickable"
                , onClick (NoteEditOpen creature.name creature.note)
                , title "Edit or clear note"
                , attribute "aria-label" ("Edit note: " ++ creature.note)
                ]
                [ text creature.note ]
            , span [ class "creature-note__sep" ] [ text "|" ]
            ]


{-| Two narrow vertical columns of pips on the creature card,
between the center column and the right rail. Each column has a
bold header letter ("LA" / "LR") followed by 4 toggleable
circular pips. The 4th pip is the in-lair bonus and renders
with a thinner border (and a faint divider above it) to mark
it as optional.

Conditional rendering — both columns spawn only when the
creature's compendium source has the matching feature, and the
flag was baked into the encounter creature at spawn time
(`Compendium.draftToInstance`):

  - `hasLegendaryActions = True` (compendium source had
    `legendary_actions /= Nothing`) → orange LA column.
  - `hasLegendaryResistance = True` (compendium source had a
    trait whose name contains "Legendary Resistance") → yellow
    LR column.

The LA pips reset to "all available" at the start of the
creature's turn — `Encounter.applyBeginOfTurn` clears the
`legendaryActionsUsed` set as part of the begin-of-turn hook.
LR pips do NOT auto-reset (legendary resistance is per long
rest in 5e, not per turn).

When the creature has neither feature, `viewLegendaryColumns`
returns `text ""` so the card flex row stays compact.

-}
viewLegendaryColumns : Creature -> Html Msg
viewLegendaryColumns creature =
    if not creature.hasLegendaryActions && not creature.hasLegendaryResistance then
        text ""

    else
        div [ class "creature-card__legendary" ]
            [ if creature.hasLegendaryActions then
                viewLegendaryColumn
                    { creatureName = creature.name
                    , kind = "la"
                    , label = "LA"
                    , used = creature.legendaryActionsUsed
                    , onToggle = ToggleLegendaryActionPip creature.name
                    }

              else
                text ""
            , if creature.hasLegendaryResistance then
                viewLegendaryColumn
                    { creatureName = creature.name
                    , kind = "lr"
                    , label = "LR"
                    , used = creature.legendaryResistanceUsed
                    , onToggle = ToggleLegendaryResistancePip creature.name
                    }

              else
                text ""
            ]


viewLegendaryColumn :
    { creatureName : String
    , kind : String
    , label : String
    , used : Set Int
    , onToggle : Int -> Msg
    }
    -> Html Msg
viewLegendaryColumn cfg =
    let
        pip idx =
            let
                filled =
                    Set.member idx cfg.used
            in
            button
                [ class
                    ("legendary-col__pip"
                        ++ (if filled then
                                " legendary-col__pip--filled"

                            else
                                ""
                           )
                        ++ (if idx == 3 then
                                " legendary-col__pip--lair"

                            else
                                ""
                           )
                    )
                , onClick (cfg.onToggle idx)
                , title
                    (cfg.label
                        ++ " pip "
                        ++ String.fromInt (idx + 1)
                        ++ (if filled then
                                ": used"

                            else
                                ": available"
                           )
                    )
                , attribute "aria-label"
                    (cfg.label ++ " pip " ++ String.fromInt (idx + 1))
                , attribute "aria-pressed"
                    (if filled then
                        "true"

                     else
                        "false"
                    )
                ]
                []
    in
    div [ class ("legendary-col legendary-col--" ++ cfg.kind) ]
        [ div [ class "legendary-col__header" ] [ text cfg.label ]
        , pip 0
        , pip 1
        , pip 2
        , div [ class "legendary-col__sep" ] []
        , pip 3
        ]


viewSurprisedToggle : Creature -> Html Msg
viewSurprisedToggle creature =
    let
        ( emoji, label ) =
            if creature.surprised then
                ( "😲", "Surprised — click for normal" )

            else
                ( "😠", "Normal — click for surprised" )
    in
    button
        [ class "surprise-btn"
        , onClick (ToggleSurprised creature.name)
        , title label
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if creature.surprised then
                "true"

             else
                "false"
            )
        ]
        [ text emoji ]


viewCardRowMid : Creature -> Maybe HpEdit -> Html Msg
viewCardRowMid creature hpEdit =
    div [ class "creature-card__row creature-card__row--mid" ]
        [ viewHpDisplay creature hpEdit
        , viewBloodied creature
        , viewDeathSaves creature
        , viewCoverToggle creature
        , span [ class "status-toggles__sep" ] [ text "|" ]
        , viewBoolToggle "🧠"
            "concentrating"
            creature.concentrating
            (ToggleConcentration creature.name)
        , span [ class "status-toggles__sep" ] [ text "|" ]
        , viewBoolToggle "👤"
            "hiding"
            creature.hiding
            (ToggleHiding creature.name)
        , span [ class "status-toggles__sep" ] [ text "|" ]
        , viewBoolToggle "🪽"
            "flying"
            creature.flying
            (ToggleFlying creature.name)
        , viewFlyHeight creature
        ]


{-| Card row 2 HP readout: green current / muted max, plus an inline
"+N" temp-HP marker when the creature is buffed. Renders the actual
creature state. Both the current and max values are click-to-edit:
clicking swaps the span for a small `<input>` (autofocus + onBlur
commits, Enter commits, Esc cancels). The temp HP doesn't get an
inline editor — it's not a value the GM normally types directly,
and the Temp HP modal is the canonical write path.
-}
viewHpDisplay : Creature -> Maybe HpEdit -> Html Msg
viewHpDisplay creature hpEdit =
    span [ class "hp-display" ]
        [ viewHpEditable creature hpEdit CurrentHpField creature.currentHp "hp-display__current"
        , span [ class "hp-display__sep" ] [ text "/" ]
        , viewHpEditable creature hpEdit MaxHpField creature.maxHp "hp-display__max"
        , if creature.tempHp > 0 then
            span
                [ class "hp-display__temp"
                , title "Temporary hit points"
                ]
                [ text ("+" ++ String.fromInt creature.tempHp) ]

          else
            text ""
        ]


{-| Render either a clickable value or the active inline-edit
input, depending on whether `hpEdit` is targeting this creature +
field. Same shape as the dice modifier field — the input value
mirrors `edit.text` (raw characters) so transient empty / "-"
states aren't clobbered.
-}
viewHpEditable : Creature -> Maybe HpEdit -> HpField -> Int -> String -> Html Msg
viewHpEditable creature hpEdit field current cls =
    let
        isEditing =
            case hpEdit of
                Just e ->
                    e.target == creature.name && e.field == field

                Nothing ->
                    False
    in
    if isEditing then
        input
            [ class "hp-display__edit"
            , type_ "number"
            , Html.Attributes.min "0"
            , Html.Attributes.max "9999"
            , value (Maybe.withDefault "" (Maybe.map .text hpEdit))
            , onInput HpEditChange
            , Html.Events.onBlur HpEditCommit
            , Html.Events.on "keydown" hpEditKeyDecoder
            , autofocus True
            ]
            []

    else
        span
            [ class (cls ++ " hp-display__editable")
            , onClick (HpEditStart creature.name field current)
            , title "Click to edit"
            ]
            [ text (String.fromInt current) ]


{-| Enter commits the inline HP edit, Esc cancels. Other keys fall
through to the input's normal handling.
-}
hpEditKeyDecoder : Decode.Decoder Msg
hpEditKeyDecoder =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                case key of
                    "Enter" ->
                        Decode.succeed HpEditCommit

                    "Escape" ->
                        Decode.succeed HpEditCancel

                    _ ->
                        Decode.fail "ignore"
            )


{-| Live render of a creature's conditions and any post-save
"Saved: <name>" notices on row 1 of the card. Empty for both →
empty text node so the row's flex gap collapses naturally.
Otherwise we render a leading separator pipe followed by chips
(active conditions first, then notices) so the eye lands on the
condition the GM is most likely to act on.
-}
viewConditionChips : Creature -> Html Msg
viewConditionChips creature =
    if List.isEmpty creature.conditions && List.isEmpty creature.saveNotices then
        text ""

    else
        span [ class "condition-chips-wrap" ]
            (span [ class "row-top__sep" ] [ text "|" ]
                :: List.map (viewConditionChip creature.name) creature.conditions
                ++ List.map (viewSaveNoticeChip creature.name) creature.saveNotices
            )


{-| "Saved: <Condition>" notice rendered as a small green chip.
Posted after a successful AUTO-roll save (manual chip-roll
successes remove the condition silently). Auto-removes on the
bearer's next end-of-turn; the × button dismisses earlier.
-}
viewSaveNoticeChip : String -> Encounter.SaveNotice -> Html Msg
viewSaveNoticeChip target notice =
    span
        [ class "save-notice"
        , title ("Saved against " ++ notice.conditionName ++ " — auto-clears on next end-of-turn")
        ]
        [ text ("Saved: " ++ notice.conditionName)
        , button
            [ class "save-notice__dismiss"
            , onClick (SaveNoticeDismiss target notice.id)
            , title "Dismiss"
            , attribute "aria-label" "Dismiss save notice"
            ]
            [ text "×" ]
        ]


{-| One condition chip. Layout (left → right):
[ name + note ][ optional save-roll button ] [ duration glyph ][ × ]

Clicking the name opens the edit modal; the × runs the remove
Msg directly (and stops propagation so it doesn't also open the
modal). The save-roll button (when the condition has a `saveToEnd`)
fires a 1d20 vs. the DC and removes the condition on success.

-}
viewConditionChip : String -> Encounter.Condition -> Html Msg
viewConditionChip target cond =
    span
        [ class "condition-chip"
        , title (chipTitle cond)
        ]
        [ button
            [ class "condition-chip__name"
            , onClick (ConditionOpenEdit target cond.id)
            , title "Click to edit"
            ]
            [ text cond.name
            , if String.isEmpty cond.note then
                text ""

              else
                span [ class "condition-chip__note" ]
                    [ text (" (" ++ cond.note ++ ")") ]
            ]
        , viewChipSaveButton target cond
        , viewChipDurationGlyph cond
        , button
            [ class "condition-chip__remove"
            , stopPropagationOn "click"
                (Decode.succeed ( ConditionRemoveChip target cond.id, True ))
            , title "Remove condition"
            , attribute "aria-label" "Remove condition"
            ]
            [ text "×" ]
        ]


{-| Tooltip text for the whole chip. Combines name, duration, and
(if present) the save-to-end terms so the GM can hover for full
context without opening the modal.
-}
chipTitle : Encounter.Condition -> String
chipTitle cond =
    let
        durPart =
            Encounter.describeDuration cond.duration

        savePart =
            case cond.saveToEnd of
                Just s ->
                    " · " ++ s.ability ++ " save DC " ++ String.fromInt s.dc

                Nothing ->
                    ""
    in
    cond.name ++ " — " ++ durPart ++ savePart


{-| Inline d20 button next to a chip when the condition has a
saving throw conditional. Click rolls 1d20 + bonus and removes
the chip on success. Hidden when no save is configured.
-}
viewChipSaveButton : String -> Encounter.Condition -> Html Msg
viewChipSaveButton target cond =
    case cond.saveToEnd of
        Just spec ->
            button
                [ class "condition-chip__save"
                , stopPropagationOn "click"
                    (Decode.succeed ( ConditionRollSave target cond.id, True ))
                , title
                    ("Roll "
                        ++ spec.ability
                        ++ " save (DC "
                        ++ String.fromInt spec.dc
                        ++ ", bonus "
                        ++ formatBonus spec.bonus
                        ++ ")"
                    )
                , attribute "aria-label" ("Roll save for " ++ cond.name)
                ]
                [ text "🎲" ]

        Nothing ->
            text ""


{-| Compact duration glyph appended to a chip. Manual durations
get nothing (the GM removes by hand); UntilTurn shows ⏱
N (where N is "Bk" or first 3 chars of the ref creature's name);
Countdown shows ⏳N.
-}
viewChipDurationGlyph : Encounter.Condition -> Html Msg
viewChipDurationGlyph cond =
    case cond.duration of
        Encounter.DurationManual ->
            text ""

        Encounter.DurationUntilTurn _ _ ref ->
            span [ class "condition-chip__duration" ]
                [ text ("⏱ " ++ String.left 4 ref) ]

        Encounter.DurationCountdown _ remaining _ ->
            span [ class "condition-chip__duration" ]
                [ text ("⏳ " ++ String.fromInt remaining) ]


formatBonus : Int -> String
formatBonus n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n


{-| Active-creature state icons in the encounter title bar.
Renders one icon per actual non-default state (cover, concentrating,
hiding, flying) — purely indicative, no click handlers. Hidden
when nothing is active.

Cover uses the same ◐ / ◕ / ● glyph vocabulary as the card row 2
toggle so the title bar reads consistently with the card.

-}
viewActiveStateIcons : Maybe Creature -> Html Msg
viewActiveStateIcons active =
    case active of
        Just c ->
            div [ class "encounter-bar__states" ]
                (List.filterMap identity
                    [ coverIcon c
                    , stateIconIf c.concentrating "🧠" "Concentrating"
                    , stateIconIf c.hiding "👤" "Hiding"
                    , flyingIcon c
                    ]
                )

        Nothing ->
            text ""


{-| Single state icon, shown only when `on` is True. Tooltip
labels it for accessibility. Returned as `Maybe (Html msg)` so
the caller can `filterMap identity` and skip the false ones.
-}
stateIconIf : Bool -> String -> String -> Maybe (Html Msg)
stateIconIf on glyph label =
    if on then
        Just
            (span
                [ class "encounter-bar__state"
                , title label
                , attribute "aria-label" label
                ]
                [ text glyph ]
            )

    else
        Nothing


coverIcon : Creature -> Maybe (Html Msg)
coverIcon c =
    case c.cover of
        Encounter.NoCover ->
            Nothing

        Encounter.HalfCover ->
            Just (stateIcon "◐" "Half cover")

        Encounter.ThreeQuartersCover ->
            Just (stateIcon "◕" "Three-quarters cover")

        Encounter.FullCover ->
            Just (stateIcon "●" "Full cover")


{-| Flying icon includes the height inline so the GM can read
"how high" at a glance without opening the card.
-}
flyingIcon : Creature -> Maybe (Html Msg)
flyingIcon c =
    if c.flying then
        Just
            (span
                [ class "encounter-bar__state"
                , title ("Flying — " ++ String.fromInt c.flyHeight ++ " ft")
                , attribute "aria-label" "Flying"
                ]
                [ text ("🪽 " ++ String.fromInt c.flyHeight) ]
            )

    else
        Nothing


stateIcon : String -> String -> Html Msg
stateIcon glyph label =
    span
        [ class "encounter-bar__state"
        , title label
        , attribute "aria-label" label
        ]
        [ text glyph ]


{-| Active-creature conditions slot in the title bar. Plain
purple text separated by " | ", not chips — the GM uses this as
a glanceable summary; the editable chips are on the card itself.
Hidden when there are no conditions.
-}
viewActiveConditionsText : Maybe Creature -> Html Msg
viewActiveConditionsText active =
    case active of
        Just c ->
            if List.isEmpty c.conditions then
                text ""

            else
                span [ class "encounter-bar__conditions" ]
                    (List.intersperse
                        (span [ class "encounter-bar__cond-sep" ] [ text "|" ])
                        (List.map
                            (\cond ->
                                span [ class "encounter-bar__cond" ]
                                    [ text cond.name ]
                            )
                            c.conditions
                        )
                    )

        Nothing ->
            text ""


viewBloodied : Creature -> Html Msg
viewBloodied creature =
    if creature.bloodied then
        span
            [ class "bloodied"
            , title "Bloodied — below half hit points"
            , attribute "aria-label" "Bloodied"
            ]
            [ text "🩸" ]

    else
        text ""


{-| The 5e death-save tracker as it appears in row 2 (right after
the bloodied indicator). Visibility is keyed off `currentHp == 0`
exclusively — the moment the creature is back above 0 HP they're
conscious, and the tracker shouldn't be on screen at all. The
HP-change engine already resets the counts on heal-to-positive,
so when the tracker re-appears (next time they hit 0) it starts
fresh.

Layout: three success pips (🌟), three failure pips (💀), and a
small 🎲 button that fires a 1d20 death save and resolves it per
5e. Once stable (3 successes) or dead (3 failures), the Roll
button disappears — the GM can still un-set pips manually if they
need to reset, but the automated flow stops.

-}
viewDeathSaves : Creature -> Html Msg
viewDeathSaves creature =
    if creature.currentHp == 0 then
        let
            ds =
                creature.deathSaves

            stable =
                Encounter.isDeathSaveStable ds

            dead =
                Encounter.isDeathSaveDead ds

            statusBadge =
                if dead then
                    span [ class "death-saves__badge death-saves__badge--dead" ]
                        [ text "💀 Dead" ]

                else if stable then
                    span [ class "death-saves__badge death-saves__badge--stable" ]
                        [ text "🛡 Stable" ]

                else
                    text ""

            rollButton =
                if dead || stable then
                    text ""

                else
                    button
                        [ class "death-saves__roll"
                        , onClick (DeathSaveRoll creature.name)
                        , title "Roll a 1d20 death save (5e: 10+ success, ≤9 failure, nat 20 revives, nat 1 = 2 failures)"
                        , attribute "aria-label" "Roll death save"
                        ]
                        [ text "🎲" ]
        in
        span
            [ class "death-saves"
            , attribute "role" "group"
            , attribute "aria-label" "Death saving throws"
            ]
            [ span [ class "death-saves__strip death-saves__strip--success" ]
                (span
                    [ class "death-saves__label"
                    , title "Successful death saves"
                    , attribute "aria-hidden" "true"
                    ]
                    [ text "🌟" ]
                    :: List.map (viewDeathSavePip creature.name DeathSaveToggleSuccess "🌟" "Success" ds.successes) [ 0, 1, 2 ]
                )
            , span [ class "death-saves__strip death-saves__strip--failure" ]
                (span
                    [ class "death-saves__label"
                    , title "Failed death saves"
                    , attribute "aria-hidden" "true"
                    ]
                    [ text "💀" ]
                    :: List.map (viewDeathSavePip creature.name DeathSaveToggleFailure "💀" "Failure" ds.failures) [ 0, 1, 2 ]
                )
            , rollButton
            , statusBadge
            ]

    else
        text ""


viewCardRowBot : Creature -> Html Msg
viewCardRowBot creature =
    div [ class "creature-card__row creature-card__row--bot" ]
        [ button
            [ class "action-btn action-btn--damage"
            , onClick (HpChangeOpen creature.name DamageKind)
            , title "Apply damage"
            ]
            [ text "Damage" ]
        , button
            [ class "action-btn action-btn--heal"
            , onClick (HpChangeOpen creature.name HealKind)
            , title "Heal hit points"
            ]
            [ text "Heal" ]
        , button
            [ class "action-btn action-btn--temp"
            , onClick (HpChangeOpen creature.name TempHpKind)
            , title "Add temporary hit points"
            ]
            [ text "Temp HP" ]
        , button
            [ class "action-btn action-btn--condition"
            , onClick (ConditionOpenNew creature.name)
            , title "Apply condition or effect"
            ]
            [ text "Condition/Effect" ]
        , viewHoldToggle creature
        , viewMemoSlot creature
        , viewTimerSlot creature
        ]


{-| Row 3 memo slot. Empty memo → 📝 button that opens the
memo-edit modal. Non-empty memo → white-text inline display with
an × dismiss button (clearing the memo restores the icon).
-}
viewMemoSlot : Creature -> Html Msg
viewMemoSlot creature =
    if String.isEmpty creature.memo then
        button
            [ class "action-btn action-btn--icon"
            , onClick (MemoOpen creature.name)
            , title "Add memo"
            , attribute "aria-label" "Add memo"
            ]
            [ text "📝" ]

    else
        span
            [ class "memo-pill"
            , title creature.memo
            ]
            [ button
                [ class "memo-pill__text"
                , onClick (MemoOpen creature.name)
                , title "Edit memo"
                ]
                [ text creature.memo ]
            , button
                [ class "memo-pill__dismiss"
                , onClick (MemoClear creature.name)
                , title "Clear memo"
                , attribute "aria-label" "Clear memo"
                ]
                [ text "×" ]
            ]


{-| Row 3 timer slot. Three states:

  - No timer set → ⏱ button that opens the timer-setup modal.
  - Timer counting → display the remaining count + × dismiss.
  - Timer ringing (`remaining = 0`) → flashing 0 + × dismiss.
    The browser also plays a ping sound courtesy of the
    page-level `<audio>` element mounted by `viewRingerAudio`.

-}
viewTimerSlot : Creature -> Html Msg
viewTimerSlot creature =
    case creature.timer of
        Nothing ->
            button
                [ class "action-btn action-btn--icon"
                , onClick (TimerOpen creature.name)
                , title "Set timer"
                , attribute "aria-label" "Set timer"
                ]
                [ text "⏱️" ]

        Just t ->
            span
                [ class
                    (if t.ringing then
                        "timer-pill timer-pill--ringing"

                     else
                        "timer-pill"
                    )
                , title (timerTooltip t)
                ]
                [ span [ class "timer-pill__count" ]
                    [ text (String.fromInt t.remaining) ]
                , button
                    [ class "timer-pill__dismiss"
                    , onClick (TimerDismiss creature.name)
                    , title "Cancel timer"
                    , attribute "aria-label" "Cancel timer"
                    ]
                    [ text "×" ]
                ]


timerTooltip : Encounter.Timer -> String
timerTooltip t =
    let
        phaseWord =
            case t.phase of
                Encounter.AtBegin ->
                    "begin"

                Encounter.AtEnd ->
                    "end"
    in
    if t.ringing then
        "Timer rang at " ++ phaseWord ++ "-of-turn — click × to dismiss"

    else
        "Timer: "
            ++ String.fromInt t.remaining
            ++ " left, ticks at "
            ++ phaseWord
            ++ "-of-turn"


viewHoldToggle : Creature -> Html Msg
viewHoldToggle creature =
    let
        ( bodyText, cls, label ) =
            if creature.holding then
                ( "✊ Holding"
                , "action-btn action-btn--holding"
                , "Holding action — click to release"
                )

            else
                ( "✋ Hold"
                , "action-btn action-btn--hold"
                , "Hold action — click to set"
                )
    in
    button
        [ class cls
        , onClick (ToggleHolding creature.name)
        , title label
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if creature.holding then
                "true"

             else
                "false"
            )
        ]
        [ text bodyText ]


{-| Render one pip of a death-save strip.

`msgFor name idx` is the toggle Msg constructor (success or
failure variant); `filledGlyph` and `kindLabel` differ between
strips. `currentCount` is the strip's current filled-pip count,
used to decide whether THIS pip (`idx`) is filled.

-}
viewDeathSavePip : String -> (String -> Int -> Msg) -> String -> String -> Int -> Int -> Html Msg
viewDeathSavePip name msgFor filledGlyph kindLabel currentCount idx =
    let
        filled =
            idx < currentCount

        glyph =
            if filled then
                filledGlyph

            else
                "○"

        stateLabel =
            if filled then
                "filled"

            else
                "empty"
    in
    button
        [ class
            (String.join " "
                [ "death-save-pip"
                , if filled then
                    "death-save-pip--filled"

                  else
                    "death-save-pip--empty"
                ]
            )
        , onClick (msgFor name idx)
        , title (kindLabel ++ " " ++ String.fromInt (idx + 1) ++ ": " ++ stateLabel)
        , attribute "aria-label" (kindLabel ++ " pip " ++ String.fromInt (idx + 1))
        , attribute "aria-pressed"
            (if filled then
                "true"

             else
                "false"
            )
        ]
        [ text glyph ]


viewBoolToggle : String -> String -> Bool -> Msg -> Html Msg
viewBoolToggle icon label isOn msg =
    let
        ( bodyText, cls, tip ) =
            if isOn then
                ( icon ++ " " ++ label
                , "status-toggle status-toggle--on"
                , label ++ " — click to clear"
                )

            else
                ( "not " ++ label
                , "status-toggle"
                , "not " ++ label ++ " — click to set"
                )
    in
    button
        [ class cls
        , onClick msg
        , title tip
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if isOn then
                "true"

             else
                "false"
            )
        ]
        [ text bodyText ]


viewCoverToggle : Creature -> Html Msg
viewCoverToggle creature =
    let
        ( bodyText, label, modifier ) =
            case creature.cover of
                NoCover ->
                    ( "○ no cover", "No cover", "status-toggle--off" )

                HalfCover ->
                    ( "◐ ½ cover", "Half cover", "status-toggle--on" )

                ThreeQuartersCover ->
                    ( "◕ ¾ cover", "Three-quarters cover", "status-toggle--on" )

                FullCover ->
                    ( "● full cover", "Full cover", "status-toggle--on" )
    in
    button
        [ class ("status-toggle " ++ modifier)
        , onClick (CycleCover creature.name)
        , title (label ++ " — click to cycle")
        , attribute "aria-label" ("Cover: " ++ label)
        ]
        [ text bodyText ]


viewFlyHeight : Creature -> Html Msg
viewFlyHeight creature =
    if creature.flying then
        span [ class "fly-height" ]
            [ button
                [ class "fly-height__btn"
                , onClick (AdjustFlyHeight creature.name 5)
                , title "Increase by 5 ft"
                , attribute "aria-label" "Increase flight height by 5 feet"
                ]
                [ text "▲" ]
            , span [ class "fly-height__value" ]
                [ text (String.fromInt creature.flyHeight) ]
            , button
                [ class "fly-height__btn"
                , onClick (AdjustFlyHeight creature.name -5)
                , title "Decrease by 5 ft"
                , attribute "aria-label" "Decrease flight height by 5 feet"
                ]
                [ text "▼" ]
            , span [ class "fly-height__unit" ] [ text "ft" ]
            , button
                [ class "icon-btn icon-btn--sm fly-height__fall"
                , title "Calculate falling damage (placeholder)"
                , attribute "aria-label" "Calculate falling damage"
                ]
                [ text "↯" ]
            ]

    else
        text ""


viewStat : String -> String -> Html Msg
viewStat label value =
    div [ class "stat" ]
        [ div [ class "stat__label" ] [ text label ]
        , div [ class "stat__value" ] [ text value ]
        ]


signed : Int -> String
signed n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n



-- STAT BLOCK


viewStatBlock : StatBlock -> Html Msg
viewStatBlock sb =
    div [ class "statblock" ]
        [ div [ class "statblock__head" ]
            [ div [ class "statblock__name" ] [ text sb.name ]
            , div [ class "statblock__type" ]
                [ text (sb.size ++ " " ++ sb.kind ++ ", " ++ sb.alignment) ]
            ]
        , hr [ class "statblock__divider" ] []
        , div [ class "statblock__meta" ]
            [ viewStat "AC" (String.fromInt sb.armorClass)
            , viewStat "HP" sb.hitPoints
            , viewStat "Speed" sb.speed
            ]
        , hr [ class "statblock__divider" ] []
        , div [ class "ability-row" ]
            [ viewAbility "STR" sb.abilities.str
            , viewAbility "DEX" sb.abilities.dex
            , viewAbility "CON" sb.abilities.con
            , viewAbility "INT" sb.abilities.int
            , viewAbility "WIS" sb.abilities.wis
            , viewAbility "CHA" sb.abilities.cha
            ]
        , hr [ class "statblock__divider" ] []
        , div [ class "statblock__traits" ]
            (List.map (viewTrait sb.name) sb.traits)
        ]


viewAbility : String -> Int -> Html Msg
viewAbility label score =
    let
        modifier =
            (score - 10) // 2
    in
    div [ class "ability" ]
        [ div [ class "ability__label" ] [ text label ]
        , div [ class "ability__value" ] [ text (String.fromInt score) ]
        , div [ class "ability__mod" ] [ text ("(" ++ signed modifier ++ ")") ]
        ]


viewTrait : String -> ( String, String ) -> Html Msg
viewTrait creatureName ( name, body ) =
    p []
        (strong [] [ text (name ++ ". ") ]
            :: List.map (viewSegment creatureName) (Dice.scan body)
        )


{-| Render one segment of scanned trait body. `Literal` runs render
as plain text; `DiceLink` segments render as clickable inline buttons
that fire a roll via the dice modal. `creatureName` is threaded
through so the resulting roll's `source` records which stat block
the formula came from.
-}
viewSegment : String -> Dice.Segment -> Html Msg
viewSegment creatureName segment =
    case segment of
        Dice.Literal s ->
            text s

        Dice.DiceLink shown expr ->
            button
                [ class "dice-link"
                , onClick (RollFromStatBlock creatureName expr)
                , title ("Roll " ++ shown)
                ]
                [ text shown ]



-- COMPENDIUM BROWSER MODAL


{-| Read-only browser for the creature library. Two-column layout:
filterable + sortable list on the left, full stat block on the
right. Phase 4 will add the "Add to Encounter" handoff in the
right pane's action bar; for now this is browse-only.
-}
viewCompendiumModal : CompendiumUi -> Html Msg
viewCompendiumModal ui =
    if not ui.open then
        text ""

    else
        View.Modal.view
            { close = CompendiumClose
            , noOp = NoOp
            , title = "📚 Compendium"
            , extraClass = "modal--compendium"
            , body =
                [ viewCompendiumFilterBar ui
                , viewCompendiumBulkBanner ui
                , viewCompendiumBody ui
                ]
            }


viewCompendiumBulkBanner : CompendiumUi -> Html Msg
viewCompendiumBulkBanner ui =
    case ( ui.pending, ui.bulkError ) of
        ( Just PendingReset, _ ) ->
            viewConfirmBanner
                { message =
                    "Reset to bundled? Every custom creature will be discarded "
                        ++ "and the library returned to the original 5 creatures."
                , confirmLabel = "Reset"
                , danger = True
                , busy = ui.bulkBusy
                }

        ( Just (PendingImport _ count), _ ) ->
            viewConfirmBanner
                { message =
                    "Import "
                        ++ String.fromInt count
                        ++ " creatures? This REPLACES the entire current library."
                , confirmLabel = "Replace library"
                , danger = True
                , busy = ui.bulkBusy
                }

        ( Just (PendingDelete _ displayName), _ ) ->
            viewConfirmBanner
                { message =
                    "Delete \""
                        ++ displayName
                        ++ "\" from the compendium? This cannot be undone."
                , confirmLabel = "Delete"
                , danger = True
                , busy = ui.bulkBusy
                }

        ( Nothing, Just err ) ->
            div [ class "compendium__bulk-error" ] [ text err ]

        ( Nothing, Nothing ) ->
            text ""


viewConfirmBanner :
    { message : String, confirmLabel : String, danger : Bool, busy : Bool }
    -> Html Msg
viewConfirmBanner cfg =
    div [ class "compendium__bulk-confirm" ]
        [ span [ class "compendium__bulk-confirm-msg" ] [ text cfg.message ]
        , button
            [ class "action-btn action-btn--blue"
            , onClick CompendiumPendingCancel
            , disabled cfg.busy
            ]
            [ text "Cancel" ]
        , button
            [ class
                (if cfg.danger then
                    "action-btn action-btn--red"

                 else
                    "action-btn action-btn--green"
                )
            , onClick CompendiumPendingConfirm
            , disabled cfg.busy
            ]
            [ text
                (if cfg.busy then
                    "Working…"

                 else
                    cfg.confirmLabel
                )
            ]
        ]


viewCompendiumFilterBar : CompendiumUi -> Html Msg
viewCompendiumFilterBar ui =
    div [ class "compendium__filter-bar" ]
        [ input
            [ class "compendium__search"
            , id Update.Compendium.searchId
            , type_ "search"
            , placeholder "🔍 Search by name, race, source, CR… (press / to focus)"
            , value ui.searchText
            , onInput CompendiumSearchChanged
            , attribute "aria-label" "Search compendium"
            ]
            []
        , div [ class "compendium__kind-filters" ]
            (List.map (viewKindFilter ui.kindFilter)
                [ Compendium.Player, Compendium.Enemy, Compendium.Npc ]
            )
        , viewCompendiumSortPicker ui.sort
        , viewCompendiumNewButton
        , viewCompendiumPasteButton
        , viewCompendiumBulkButtons
        ]


viewKindFilter : Set String -> Compendium.CreatureKind -> Html Msg
viewKindFilter active kind =
    let
        key =
            CompendiumUi.kindToString kind

        isActive =
            -- An empty filter set means "show all kinds"; the chip
            -- appears active in that case so the GM sees the default
            -- isn't filtering anything out.
            Set.isEmpty active || Set.member key active
    in
    button
        [ class
            ("compendium__kind-filter"
                ++ (if isActive then
                        " compendium__kind-filter--active"

                    else
                        ""
                   )
            )
        , onClick (CompendiumKindToggled kind)
        , attribute "aria-pressed"
            (if isActive then
                "true"

             else
                "false"
            )
        ]
        [ text (CompendiumUi.creatureKindLabel kind) ]


viewCompendiumSortPicker : CompendiumSort -> Html Msg
viewCompendiumSortPicker current =
    let
        opt sort label =
            option
                [ value (sortToString sort)
                , selected (sort == current)
                ]
                [ text label ]
    in
    Html.select
        [ class "compendium__sort"
        , onInput sortFromInput
        , attribute "aria-label" "Sort compendium"
        ]
        [ opt SortName "A–Z"
        , opt SortCr "By CR"
        , opt SortRecency "Newest first"
        ]


sortToString : CompendiumSort -> String
sortToString s =
    case s of
        SortName ->
            "name"

        SortCr ->
            "cr"

        SortRecency ->
            "recency"


sortFromInput : String -> Msg
sortFromInput raw =
    case raw of
        "cr" ->
            CompendiumSortChanged SortCr

        "recency" ->
            CompendiumSortChanged SortRecency

        _ ->
            CompendiumSortChanged SortName


viewCompendiumBody : CompendiumUi -> Html Msg
viewCompendiumBody ui =
    case ui.db of
        CompendiumDbLoading ->
            viewCompendiumSkeleton

        CompendiumDbFailed _ ->
            div [ class "compendium__placeholder compendium__placeholder--error" ]
                [ text "Couldn't load the compendium. Check the server logs." ]

        CompendiumDbLoaded _ ->
            viewCompendiumTwoColumn ui


viewCompendiumSkeleton : Html Msg
viewCompendiumSkeleton =
    div [ class "compendium__columns" ]
        [ div [ class "compendium__list" ]
            (List.repeat 8 viewSkeletonRow)
        , div [ class "compendium__detail compendium__detail--skeleton" ]
            [ div [ class "skeleton-block skeleton-block--title" ] []
            , div [ class "skeleton-block" ] []
            , div [ class "skeleton-block" ] []
            , div [ class "skeleton-block skeleton-block--short" ] []
            ]
        ]


viewSkeletonRow : Html Msg
viewSkeletonRow =
    div [ class "compendium__row compendium__row--skeleton" ]
        [ div [ class "skeleton-block skeleton-block--title" ] []
        , div [ class "skeleton-block skeleton-block--short" ] []
        ]


viewCompendiumTwoColumn : CompendiumUi -> Html Msg
viewCompendiumTwoColumn ui =
    let
        visible =
            CompendiumUi.compendiumVisible ui

        totalCount =
            case ui.db of
                CompendiumDbLoaded db ->
                    Compendium.count db

                _ ->
                    0
    in
    div [ class "compendium__columns" ]
        [ viewCompendiumList ui totalCount visible
        , viewCompendiumDetail ui visible
        ]


viewCompendiumList : CompendiumUi -> Int -> List Compendium.Creature -> Html Msg
viewCompendiumList ui totalCount visible =
    if List.isEmpty visible then
        if totalCount == 0 then
            div [ class "compendium__list compendium__list--empty" ]
                [ p [] [ text "Your compendium is empty." ]
                , p [ class "compendium__empty-hint" ]
                    [ text "Try "
                    , button
                        [ class "compendium__empty-link"
                        , onClick CompendiumEditNew
                        ]
                        [ text "creating one" ]
                    , text ", "
                    , button
                        [ class "compendium__empty-link"
                        , onClick CompendiumPasteOpen
                        ]
                        [ text "pasting a stat block" ]
                    , text ", or "
                    , button
                        [ class "compendium__empty-link"
                        , onClick CompendiumImportClick
                        ]
                        [ text "importing a JSON file" ]
                    , text "."
                    ]
                ]

        else
            div [ class "compendium__list compendium__list--empty" ]
                [ p [] [ text "No creatures match the current filters." ]
                , p [ class "compendium__empty-hint" ]
                    [ text (String.fromInt totalCount ++ " creatures hidden — try clearing the search or kind filters.") ]
                ]

    else
        div [ class "compendium__list" ]
            (List.map (viewCompendiumListItem ui.selectedId) visible)


viewCompendiumListItem : Maybe String -> Compendium.Creature -> Html Msg
viewCompendiumListItem selectedId c =
    let
        isSelected =
            selectedId == Just c.id

        rowClass =
            "compendium__row"
                ++ (if isSelected then
                        " compendium__row--selected"

                    else
                        ""
                   )
                ++ (" compendium__row--" ++ CompendiumUi.kindToString c.kind)
    in
    button
        [ class rowClass
        , onClick (CompendiumSelect c.id)
        , attribute "aria-pressed"
            (if isSelected then
                "true"

             else
                "false"
            )
        ]
        [ span [ class "compendium__row-name" ] [ text c.name ]
        , span [ class "compendium__row-meta" ]
            [ text (rowMetaLine c) ]
        ]


rowMetaLine : Compendium.Creature -> String
rowMetaLine c =
    let
        bits =
            List.filter (not << String.isEmpty)
                [ CompendiumUi.creatureKindLabel c.kind
                , c.race
                , "AC " ++ String.fromInt c.armorClass
                , "HP " ++ String.fromInt c.maxHp
                , crLabel c.challengeRating
                ]
    in
    String.join " · " bits


crLabel : String -> String
crLabel cr =
    if String.isEmpty cr then
        ""

    else
        "CR " ++ cr


viewCompendiumDetail : CompendiumUi -> List Compendium.Creature -> Html Msg
viewCompendiumDetail ui visible =
    let
        chosen =
            ui.selectedId
                |> Maybe.andThen (\id -> List.filter (\c -> c.id == id) visible |> List.head)
    in
    case chosen of
        Just creature ->
            div [ class "compendium__detail" ]
                [ viewCompendiumActionBar ui creature
                , View.StatBlock.view RollFromStatBlock creature
                ]

        Nothing ->
            div [ class "compendium__detail compendium__detail--empty" ]
                [ text "Select a creature on the left to see its stat block." ]


viewCompendiumActionBar : CompendiumUi -> Compendium.Creature -> Html Msg
viewCompendiumActionBar ui creature =
    div [ class "compendium__action-bar" ]
        [ label [ class "compendium__count-label" ]
            [ text "Count "
            , input
                [ class "compendium__count"
                , type_ "number"
                , Html.Attributes.min "1"
                , Html.Attributes.max (String.fromInt CompendiumUi.maxAddCount)
                , value ui.addCountText
                , onInput CompendiumAddCountChanged
                , attribute "aria-label" "Number of copies to add"
                ]
                []
            ]
        , button
            [ class "action-btn action-btn--green compendium__add-btn"
            , onClick (CompendiumAddToQueue creature.id)
            , title "Roll initiative and add to the encounter queue"
            ]
            [ text ("➕ Add to Encounter (" ++ String.fromInt ui.addCount ++ ")") ]
        , button
            [ class "action-btn action-btn--blue compendium__edit-btn"
            , onClick CompendiumEditExisting
            , title "Edit this creature"
            ]
            [ text "✏️ Edit" ]
        , button
            [ class "action-btn action-btn--blue compendium__edit-btn"
            , onClick CompendiumEditDuplicate
            , title "Duplicate this creature in the compendium"
            ]
            [ text "📋 Duplicate" ]
        , button
            [ class "action-btn action-btn--red compendium__delete-btn"
            , onClick (CompendiumDeleteFromBrowser creature.id creature.name)
            , title "Delete this creature from the compendium"
            , attribute "aria-label" "Delete creature"
            ]
            [ text "🗑" ]
        ]


viewCompendiumNewButton : Html Msg
viewCompendiumNewButton =
    button
        [ class "action-btn action-btn--green compendium__new-btn"
        , onClick CompendiumEditNew
        , title "Create a new creature from scratch"
        ]
        [ text "➕ New Creature" ]


viewCompendiumPasteButton : Html Msg
viewCompendiumPasteButton =
    button
        [ class "action-btn action-btn--blue"
        , onClick CompendiumPasteOpen
        , title "Paste a 5e stat block to import"
        ]
        [ text "📋 Paste Stat Block" ]


{-| Cluster of bulk operations on the right edge of the filter
bar: Import / Export / Reset to Bundled. Export is a plain anchor
with `download` so the browser handles it natively (no Cmd needed).
Import + Reset both go through the destructive-confirm banner
before firing.
-}
viewCompendiumBulkButtons : Html Msg
viewCompendiumBulkButtons =
    div [ class "compendium__bulk-cluster" ]
        [ button
            [ class "action-btn action-btn--blue"
            , onClick CompendiumImportClick
            , title "Import a creature library JSON file (replaces the current library)"
            ]
            [ text "📥 Import" ]
        , a
            [ class "action-btn action-btn--blue"
            , href "/api/compendium/export"
            , attribute "download" "compendium.json"
            , title "Download the entire library as JSON"
            ]
            [ text "📤 Export" ]
        , button
            [ class "action-btn action-btn--red"
            , onClick CompendiumResetClick
            , title "Reset the library to the bundled creature set"
            ]
            [ text "↺ Reset" ]
        ]



-- COMPENDIUM EDIT / CREATE MODAL


viewCompendiumEditModal : Maybe CompendiumEditUi -> Html Msg
viewCompendiumEditModal maybeUi =
    case maybeUi of
        Nothing ->
            text ""

        Just ui ->
            View.Modal.view
                { close = CompendiumEditCancel
                , noOp = NoOp
                , title = editModalTitle ui
                , extraClass = "modal--compendium-edit"
                , body =
                    [ viewEditError ui
                    , viewEditSection "Identity"
                        [ inlineRow
                            [ textField "Name" CFName ui.name [ attribute "required" "true" ]
                            , kindRadio ui.kind
                            ]
                        , inlineRow
                            [ sizeDropdown ui.size
                            , textField "Race" CFRace ui.race []
                            , textField "Subrace" CFSubrace ui.subrace []
                            ]
                        , inlineRow
                            [ textField "Alignment" CFAlignment ui.alignment []
                            , textField "Source" CFSource ui.source []
                            ]
                        , textareaField "Description (short blurb)" CFDescription ui.description 2
                        ]
                    , viewEditSection "Combat Core"
                        [ inlineRow
                            [ numberField "AC" CFArmorClass ui.armorClass [ attribute "required" "true" ]
                            , textField "AC Note" CFArmorClassNote ui.armorClassNote []
                            , numberField "Max HP" CFMaxHp ui.maxHp [ attribute "required" "true" ]
                            , textField "HP Formula" CFHpFormula ui.hpFormula []
                            , numberField "Init Bonus" CFInitiativeBonus ui.initiativeBonus []
                            ]
                        , inlineRow
                            [ numberField "Walk" CFSpeedWalk ui.speedWalk []
                            , numberField "Fly" CFSpeedFly ui.speedFly []
                            , numberField "Swim" CFSpeedSwim ui.speedSwim []
                            , numberField "Climb" CFSpeedClimb ui.speedClimb []
                            , numberField "Burrow" CFSpeedBurrow ui.speedBurrow []
                            , hoverToggle ui.speedHover
                            ]
                        ]
                    , viewEditSection "Abilities"
                        [ inlineRow
                            [ abilityField "STR" CFAbilityStr ui.abilityStr
                            , abilityField "DEX" CFAbilityDex ui.abilityDex
                            , abilityField "CON" CFAbilityCon ui.abilityCon
                            , abilityField "INT" CFAbilityInt ui.abilityInt
                            , abilityField "WIS" CFAbilityWis ui.abilityWis
                            , abilityField "CHA" CFAbilityCha ui.abilityCha
                            ]
                        ]
                    , viewEditSection "Saving Throws"
                        (viewSavingThrowsEditor ui.savingThrows)
                    , viewEditSection "Skills"
                        (viewSkillsEditor ui.skills)
                    , viewEditSection "Properties"
                        [ textField "Damage Vulnerabilities (comma-separated)" CFDamageVulnerabilities ui.damageVulnerabilities []
                        , textField "Damage Resistances" CFDamageResistances ui.damageResistances []
                        , textField "Damage Immunities" CFDamageImmunities ui.damageImmunities []
                        , textField "Condition Immunities" CFConditionImmunities ui.conditionImmunities []
                        , textField "Languages" CFLanguages ui.languages []
                        , inlineRow
                            [ textField "Challenge Rating" CFChallengeRating ui.challengeRating []
                            , numberField "XP" CFXp ui.xp []
                            , numberField "Proficiency Bonus" CFProficiencyBonus ui.proficiencyBonus []
                            ]
                        ]
                    , viewEditSection "Senses"
                        [ inlineRow
                            [ numberField "Blindsight" CFSensesBlindsight ui.sensesBlindsight []
                            , numberField "Darkvision" CFSensesDarkvision ui.sensesDarkvision []
                            , numberField "Tremorsense" CFSensesTremorsense ui.sensesTremorsense []
                            , numberField "Truesight" CFSensesTruesight ui.sensesTruesight []
                            , numberField "Passive Perception" CFSensesPassivePerception ui.sensesPassivePerception []
                            ]
                        ]
                    , viewEditSection "Traits"
                        (viewFeaturesEditor TraitsGroup ui.traits)
                    , viewEditSection "Actions"
                        (viewFeaturesEditor ActionsGroup ui.actions)
                    , viewEditSection "Bonus Actions"
                        (viewFeaturesEditor BonusActionsGroup ui.bonusActions)
                    , viewEditSection "Reactions"
                        (viewFeaturesEditor ReactionsGroup ui.reactions)
                    , viewEditSection "Custom Sections"
                        (viewCustomSectionsEditor ui.customSections)
                    , viewAdvancedSectionsNotice ui
                    , viewEditFooter ui
                    ]
                }


editModalTitle : CompendiumEditUi -> String
editModalTitle ui =
    case ui.mode of
        CreateMode ->
            "📚 New Creature"

        EditExisting _ ->
            "📚 Edit Creature"


viewEditError : CompendiumEditUi -> Html Msg
viewEditError ui =
    case ui.submitError of
        Nothing ->
            text ""

        Just msg ->
            div [ class "edit-error" ] [ text msg ]


viewEditSection : String -> List (Html Msg) -> Html Msg
viewEditSection heading children =
    Html.fieldset [ class "edit-section" ]
        (Html.legend [] [ text heading ] :: children)


inlineRow : List (Html Msg) -> Html Msg
inlineRow children =
    div [ class "edit-row" ] children


textField : String -> CompendiumField -> String -> List (Html.Attribute Msg) -> Html Msg
textField labelText field current extras =
    label [ class "edit-field" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , input
            ([ type_ "text"
             , value current
             , onInput (CompendiumEditFieldChanged field)
             , class "edit-field__input"
             ]
                ++ extras
            )
            []
        ]


numberField : String -> CompendiumField -> String -> List (Html.Attribute Msg) -> Html Msg
numberField labelText field current extras =
    label [ class "edit-field edit-field--number" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , input
            ([ type_ "number"
             , value current
             , onInput (CompendiumEditFieldChanged field)
             , class "edit-field__input"
             ]
                ++ extras
            )
            []
        ]


textareaField : String -> CompendiumField -> String -> Int -> Html Msg
textareaField labelText field current rows =
    label [ class "edit-field edit-field--textarea" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , Html.textarea
            [ value current
            , onInput (CompendiumEditFieldChanged field)
            , class "edit-field__input"
            , attribute "rows" (String.fromInt rows)
            ]
            []
        ]


abilityField : String -> CompendiumField -> String -> Html Msg
abilityField labelText field current =
    let
        score =
            String.toInt current |> Maybe.withDefault 10

        modValue =
            (score - 10) // 2
    in
    label [ class "edit-field edit-field--ability" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , input
            [ type_ "number"
            , value current
            , onInput (CompendiumEditFieldChanged field)
            , class "edit-field__input"
            ]
            []
        , span [ class "edit-field__hint" ] [ text ("(" ++ signedInt modValue ++ ")") ]
        ]


signedInt : Int -> String
signedInt n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n


kindRadio : Compendium.CreatureKind -> Html Msg
kindRadio current =
    let
        opt kind label_ =
            label [ class "edit-radio" ]
                [ input
                    [ type_ "radio"
                    , name "edit-kind"
                    , checked (kind == current)
                    , onClick (CompendiumEditKindSet kind)
                    ]
                    []
                , text label_
                ]
    in
    div [ class "edit-field edit-field--radio-group" ]
        [ span [ class "edit-field__label" ] [ text "Kind" ]
        , div [ class "edit-radio-row" ]
            [ opt Compendium.Player "Player"
            , opt Compendium.Enemy "Enemy"
            , opt Compendium.Npc "NPC"
            ]
        ]


sizeDropdown : Compendium.Size -> Html Msg
sizeDropdown current =
    let
        sizes =
            [ ( Compendium.Tiny, "Tiny" )
            , ( Compendium.Small, "Small" )
            , ( Compendium.Medium, "Medium" )
            , ( Compendium.Large, "Large" )
            , ( Compendium.Huge, "Huge" )
            , ( Compendium.Gargantuan, "Gargantuan" )
            ]
    in
    label [ class "edit-field" ]
        [ span [ class "edit-field__label" ] [ text "Size" ]
        , Html.select
            [ class "edit-field__input"
            , onInput sizeFromString
            ]
            (List.map
                (\( size, label_ ) ->
                    option
                        [ value (sizeKey size)
                        , selected (size == current)
                        ]
                        [ text label_ ]
                )
                sizes
            )
        ]


sizeKey : Compendium.Size -> String
sizeKey s =
    case s of
        Compendium.Tiny ->
            "tiny"

        Compendium.Small ->
            "small"

        Compendium.Medium ->
            "medium"

        Compendium.Large ->
            "large"

        Compendium.Huge ->
            "huge"

        Compendium.Gargantuan ->
            "gargantuan"


sizeFromString : String -> Msg
sizeFromString raw =
    let
        size =
            case raw of
                "tiny" ->
                    Compendium.Tiny

                "small" ->
                    Compendium.Small

                "large" ->
                    Compendium.Large

                "huge" ->
                    Compendium.Huge

                "gargantuan" ->
                    Compendium.Gargantuan

                _ ->
                    Compendium.Medium
    in
    CompendiumEditSizeSet size


hoverToggle : Bool -> Html Msg
hoverToggle current =
    label [ class "edit-field edit-field--checkbox" ]
        [ input
            [ type_ "checkbox"
            , checked current
            , onClick CompendiumEditSpeedHoverToggle
            ]
            []
        , text "hover"
        ]


viewSavingThrowsEditor : List ( Compendium.Ability, String ) -> List (Html Msg)
viewSavingThrowsEditor rows =
    List.indexedMap viewSavingThrowRow rows
        ++ [ button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick CompendiumEditSavingThrowAdd
                ]
                [ text "+ Add Save" ]
           ]


viewSavingThrowRow : Int -> ( Compendium.Ability, String ) -> Html Msg
viewSavingThrowRow idx ( ability, bonus ) =
    div [ class "edit-row edit-row--list-item" ]
        [ Html.select
            [ class "edit-field__input edit-field--narrow"
            , onInput (abilityFromString >> CompendiumEditSavingThrowAbilitySet idx)
            ]
            (List.map
                (\a ->
                    option
                        [ value (abilityKey a)
                        , selected (a == ability)
                        ]
                        [ text (abilityShort a) ]
                )
                [ Compendium.Str
                , Compendium.Dex
                , Compendium.Con
                , Compendium.Int_
                , Compendium.Wis
                , Compendium.Cha
                ]
            )
        , input
            [ type_ "number"
            , value bonus
            , onInput (CompendiumEditSavingThrowBonusChanged idx)
            , class "edit-field__input edit-field--narrow"
            , attribute "aria-label" "Bonus"
            ]
            []
        , button
            [ class "edit-row__remove"
            , onClick (CompendiumEditSavingThrowRemove idx)
            , title "Remove this save"
            ]
            [ text "×" ]
        ]


abilityKey : Compendium.Ability -> String
abilityKey a =
    case a of
        Compendium.Str ->
            "str"

        Compendium.Dex ->
            "dex"

        Compendium.Con ->
            "con"

        Compendium.Int_ ->
            "int"

        Compendium.Wis ->
            "wis"

        Compendium.Cha ->
            "cha"


abilityFromString : String -> Compendium.Ability
abilityFromString raw =
    case raw of
        "dex" ->
            Compendium.Dex

        "con" ->
            Compendium.Con

        "int" ->
            Compendium.Int_

        "wis" ->
            Compendium.Wis

        "cha" ->
            Compendium.Cha

        _ ->
            Compendium.Str


abilityShort : Compendium.Ability -> String
abilityShort a =
    case a of
        Compendium.Str ->
            "STR"

        Compendium.Dex ->
            "DEX"

        Compendium.Con ->
            "CON"

        Compendium.Int_ ->
            "INT"

        Compendium.Wis ->
            "WIS"

        Compendium.Cha ->
            "CHA"


viewSkillsEditor : List ( String, String ) -> List (Html Msg)
viewSkillsEditor rows =
    List.indexedMap viewSkillRow rows
        ++ [ button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick CompendiumEditSkillAdd
                ]
                [ text "+ Add Skill" ]
           ]


viewSkillRow : Int -> ( String, String ) -> Html Msg
viewSkillRow idx ( name, bonus ) =
    div [ class "edit-row edit-row--list-item" ]
        [ input
            [ type_ "text"
            , value name
            , placeholder "Skill name (e.g. Perception)"
            , onInput (CompendiumEditSkillNameChanged idx)
            , class "edit-field__input"
            ]
            []
        , input
            [ type_ "number"
            , value bonus
            , onInput (CompendiumEditSkillBonusChanged idx)
            , class "edit-field__input edit-field--narrow"
            , attribute "aria-label" "Bonus"
            ]
            []
        , button
            [ class "edit-row__remove"
            , onClick (CompendiumEditSkillRemove idx)
            , title "Remove this skill"
            ]
            [ text "×" ]
        ]


viewFeaturesEditor : FeatureGroup -> List FeatureDraft -> List (Html Msg)
viewFeaturesEditor group rows =
    List.indexedMap (viewFeatureRow group) rows
        ++ [ button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick (CompendiumEditFeatureAdd group)
                ]
                [ text "+ Add Entry" ]
           ]


viewFeatureRow : FeatureGroup -> Int -> FeatureDraft -> Html Msg
viewFeatureRow group idx draft =
    div [ class "edit-feature" ]
        [ div [ class "edit-row edit-row--list-item" ]
            [ input
                [ type_ "text"
                , value draft.name
                , placeholder "Name (e.g. Multiattack)"
                , onInput (CompendiumEditFeatureNameChanged group idx)
                , class "edit-field__input"
                ]
                []
            , button
                [ class "edit-row__remove"
                , onClick (CompendiumEditFeatureRemove group idx)
                , title "Remove this entry"
                ]
                [ text "×" ]
            ]
        , Html.textarea
            [ value draft.description
            , onInput (CompendiumEditFeatureDescriptionChanged group idx)
            , class "edit-field__input"
            , attribute "rows" "3"
            , placeholder "Description (free text; inline dice notation like 1d8+3 becomes clickable)"
            ]
            []
        ]


viewCustomSectionsEditor : List ( String, String ) -> List (Html Msg)
viewCustomSectionsEditor rows =
    List.indexedMap viewCustomSectionRow rows
        ++ [ button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick CompendiumEditCustomSectionAdd
                ]
                [ text "+ Add Section" ]
           ]


viewCustomSectionRow : Int -> ( String, String ) -> Html Msg
viewCustomSectionRow idx ( name, body ) =
    div [ class "edit-feature" ]
        [ div [ class "edit-row edit-row--list-item" ]
            [ input
                [ type_ "text"
                , value name
                , placeholder "Section heading"
                , onInput (CompendiumEditCustomSectionNameChanged idx)
                , class "edit-field__input"
                ]
                []
            , button
                [ class "edit-row__remove"
                , onClick (CompendiumEditCustomSectionRemove idx)
                , title "Remove this section"
                ]
                [ text "×" ]
            ]
        , Html.textarea
            [ value body
            , onInput (CompendiumEditCustomSectionBodyChanged idx)
            , class "edit-field__input"
            , attribute "rows" "3"
            ]
            []
        ]


{-| Heads-up: the four advanced sections (legendary / lair /
regional / spellcasting) aren't editable in this MVP form yet.
If the source creature had any populated, they're preserved
verbatim through submit; if you're starting from scratch they
just stay empty.
-}
viewAdvancedSectionsNotice : CompendiumEditUi -> Html Msg
viewAdvancedSectionsNotice ui =
    let
        hasAny =
            ui.legendaryActions
                /= Nothing
                || ui.lairActions
                /= Nothing
                || ui.regionalEffects
                /= Nothing
                || ui.spellcasting
                /= Nothing
    in
    if hasAny then
        div [ class "edit-advanced-notice" ]
            [ text "Note: this creature has Legendary / Lair / Regional / Spellcasting data that this form doesn't yet edit. Those sections will be preserved on save." ]

    else
        text ""


viewEditFooter : CompendiumEditUi -> Html Msg
viewEditFooter ui =
    div [ class "edit-footer" ]
        [ if isEditingExisting ui then
            button
                [ class "action-btn action-btn--red"
                , onClick CompendiumEditDelete
                , disabled ui.submitting
                , title "Delete this creature from the compendium"
                ]
                [ text "🗑 Delete" ]

          else
            text ""
        , div [ class "edit-footer__spacer" ] []
        , button
            [ class "action-btn action-btn--blue"
            , onClick CompendiumEditCancel
            , disabled ui.submitting
            ]
            [ text "Cancel" ]
        , button
            [ class "action-btn action-btn--green"
            , onClick CompendiumEditSubmit
            , disabled ui.submitting
            ]
            [ text
                (if ui.submitting then
                    "Saving…"

                 else
                    submitLabel ui.mode
                )
            ]
        ]


submitLabel : EditMode -> String
submitLabel mode =
    case mode of
        CreateMode ->
            "Create"

        EditExisting _ ->
            "Save"


isEditingExisting : CompendiumEditUi -> Bool
isEditingExisting ui =
    case ui.mode of
        CreateMode ->
            False

        EditExisting _ ->
            True



-- COMPENDIUM PASTE / PARSE MODAL


viewCompendiumPasteModal : Maybe CompendiumPasteUi -> Html Msg
viewCompendiumPasteModal maybeUi =
    case maybeUi of
        Nothing ->
            text ""

        Just ui ->
            View.Modal.view
                { close = CompendiumPasteCancel
                , noOp = NoOp
                , title = "📋 Paste Stat Block"
                , extraClass = "modal--compendium-paste"
                , body =
                    [ div [ class "paste-modal__columns" ]
                        [ viewPasteInput ui
                        , viewPastePreview ui
                        ]
                    , viewPasteFooter ui
                    ]
                }


viewPasteInput : CompendiumPasteUi -> Html Msg
viewPasteInput ui =
    div [ class "paste-modal__input-col" ]
        [ div [ class "paste-modal__hint" ]
            [ text "Paste a 5e stat block here. Lines like \"Armor Class 15 (leather armor, shield)\" and \"STR 8 (-1) DEX 14 (+2) …\" parse automatically." ]
        , Html.textarea
            [ class "paste-modal__textarea"
            , value ui.text
            , onInput CompendiumPasteTextChanged
            , placeholder "Goblin\nSmall humanoid (goblinoid), neutral evil\nArmor Class 15 (leather armor, shield)\nHit Points 7 (2d6)\nSpeed 30 ft.\nSTR 8 (-1) DEX 14 (+2) CON 10 (+0) INT 10 (+0) WIS 8 (-1) CHA 8 (-1)\n…"
            , attribute "rows" "20"
            , attribute "spellcheck" "false"
            ]
            []
        ]


viewPastePreview : CompendiumPasteUi -> Html Msg
viewPastePreview ui =
    div [ class "paste-modal__preview-col" ]
        [ div [ class "paste-modal__preview-heading" ] [ text "Live preview" ]
        , case ui.parseResult of
            Ok creature ->
                div [ class "paste-modal__preview" ]
                    [ View.StatBlock.view RollFromStatBlock creature ]

            Err err ->
                div [ class "paste-modal__preview paste-modal__preview--error" ]
                    [ text (parseErrorLabel err) ]
        ]


parseErrorLabel : Compendium.Parser.ParseError -> String
parseErrorLabel err =
    case err of
        Compendium.Parser.EmptyInput ->
            "Paste a stat block to see the live preview."

        Compendium.Parser.MissingHeader ->
            "Need at least two lines: a name and a type line (e.g. \"Small humanoid, neutral evil\")."


viewPasteFooter : CompendiumPasteUi -> Html Msg
viewPasteFooter ui =
    let
        isOk =
            case ui.parseResult of
                Ok _ ->
                    True

                Err _ ->
                    False
    in
    div [ class "paste-modal__footer" ]
        [ div [ class "paste-modal__footer-spacer" ] []
        , button
            [ class "action-btn action-btn--blue"
            , onClick CompendiumPasteCancel
            ]
            [ text "Cancel" ]
        , button
            [ class "action-btn action-btn--green"
            , onClick CompendiumPasteApply
            , disabled (not isOk)
            , title
                (if isOk then
                    "Open the edit modal pre-filled with the parsed data"

                 else
                    "Fix the parse errors first"
                )
            ]
            [ text "Apply to Form" ]
        ]
