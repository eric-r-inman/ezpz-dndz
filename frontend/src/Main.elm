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
import View.Card
import View.Modal
import View.Modal.Compendium
import View.Modal.CompendiumEdit
import View.Modal.CompendiumPaste
import View.Modal.Condition
import View.Modal.Dice
import View.Modal.HpChange
import View.Modal.Initiative
import View.Modal.Memo
import View.Modal.Note
import View.Modal.Timer
import View.PhaseToggle
import View.StatBlock
import View.StatBlockEmbed
import View.Toast
import View.Workspace



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
            , View.Modal.Compendium.view model.compendium
            , View.Modal.CompendiumEdit.view model.compendiumEdit
            , View.Modal.CompendiumPaste.view model.compendiumPaste
            , View.Toast.list model.toasts
            , View.Audio.ringer model
            ]
        ]
    }


viewPage : Model -> Html Msg
viewPage model =
    case model.route of
        Home ->
            View.Workspace.view model

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
