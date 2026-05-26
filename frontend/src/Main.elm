module Main exposing (Flags, main)

import Auth
import Browser
import Browser.Dom
import Browser.Events
import Browser.Navigation as Nav
import Card.Layout
import Card.Wire
import Compendium
import Compendium.GroupWire
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
import Encounter.Xp exposing (XpScope(..))
import File exposing (File)
import File.Select
import HpChange
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, preventDefaultOn, stopPropagationOn)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( CompendiumField(..)
        , CompendiumSort(..)
        , ControlMenu(..)
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
        , Theme(..)
        )
import Ports
import Preferences
import Route exposing (Route(..))
import Task
import Ui.Account
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
import Ui.Login as LoginUi
import Ui.Toast
import Update.AbilitySave
import Update.Account
import Update.Auth
import Update.CardEditor
import Update.Compendium.Add
import Update.Compendium.AddGroup
import Update.Compendium.Browser
import Update.Compendium.Bulk
import Update.Compendium.Edit
import Update.Compendium.Group
import Update.Compendium.Paste
import Update.Condition
import Update.CrCalculator
import Update.DeathSave
import Update.Dice
import Update.Duplicate
import Update.Encounter
import Update.HpChange
import Update.Initiative
import Update.LegendaryPip
import Update.Load
import Update.LoadCompendium
import Update.Memo
import Update.Note
import Update.Preferences
import Update.QuickAdd
import Update.Save
import Update.SaveCompendium
import Update.Shell
import Update.Timer
import Update.Toast
import Url exposing (Url)
import Util.Keyboard
import View.Account
import View.AppBar
import View.Audio
import View.Card
import View.Footer
import View.Login
import View.Modal
import View.Modal.AbilitySave
import View.Modal.CardEditor
import View.Modal.Compendium
import View.Modal.CompendiumEdit
import View.Modal.CompendiumPaste
import View.Modal.Condition
import View.Modal.CrCalculator
import View.Modal.Dice
import View.Modal.Duplicate
import View.Modal.GroupEdit
import View.Modal.HpChange
import View.Modal.Initiative
import View.Modal.Load
import View.Modal.LoadCompendium
import View.Modal.Memo
import View.Modal.Note
import View.Modal.QuickAdd
import View.Modal.Save
import View.Modal.SaveCompendium
import View.Modal.Timer
import View.RollPopup
import View.StatBlock
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
main : Program Flags Model Msg
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

The XP-filter dropdown overlays whatever else is on the page;
when it's open we layer in two extra subscriptions on top of the
modal-stack handlers — Esc closes it, and any document-level click
that isn't stopped by the dropdown internals also closes it.

-}
subscriptions : Model -> Sub Msg
subscriptions model =
    let
        xpFilterSubs =
            if model.xpFilterOpen then
                [ Browser.Events.onKeyDown (escKey XpFilterClose)
                , Browser.Events.onMouseDown (Decode.succeed XpFilterClose)
                ]

            else
                []

        settingsSubs =
            if model.settingsOpen then
                [ Browser.Events.onKeyDown (escKey SettingsClose)
                , Browser.Events.onMouseDown (Decode.succeed SettingsClose)
                ]

            else
                []

        clearMenuSubs =
            if model.compendium.bulkMenu /= Nothing then
                [ Browser.Events.onKeyDown (escKey CompendiumBulkMenuClose)
                , Browser.Events.onMouseDown (Decode.succeed CompendiumBulkMenuClose)
                ]

            else
                []

        controlMenuSubs =
            case model.controlMenu of
                Just _ ->
                    [ Browser.Events.onKeyDown (escKey ControlMenuClose)
                    , Browser.Events.onMouseDown (Decode.succeed ControlMenuClose)
                    ]

                Nothing ->
                    []

        primary =
            if model.dice.open then
                Browser.Events.onKeyDown (escKey CloseDice)

            else
                case model.modal of
                    Just (ModalCompendiumPaste _) ->
                        Browser.Events.onKeyDown (escKey CompendiumPasteCancel)

                    Just (ModalCompendiumEdit _) ->
                        Browser.Events.onKeyDown (escKey CompendiumEditCancel)

                    Just (ModalNoteEdit _) ->
                        Browser.Events.onKeyDown (escKey NoteEditCancel)

                    Just (ModalSave _) ->
                        Browser.Events.onKeyDown (escKey SaveClose)

                    Just (ModalLoad _) ->
                        Browser.Events.onKeyDown (escKey LoadClose)

                    Just (ModalSaveCompendium _) ->
                        Browser.Events.onKeyDown (escKey SaveCompendiumClose)

                    Just (ModalLoadCompendium _) ->
                        Browser.Events.onKeyDown (escKey LoadCompendiumClose)

                    Just (ModalAbilitySave _) ->
                        Browser.Events.onKeyDown (escKey AbilitySaveClose)

                    Just (ModalQuickAdd _) ->
                        Browser.Events.onKeyDown (escKey QuickAddClose)

                    Just (ModalDuplicate _) ->
                        Browser.Events.onKeyDown (escKey DuplicateClose)

                    _ ->
                        if model.compendium.open then
                            Browser.Events.onKeyDown compendiumKeyDecoder

                        else
                            Sub.none
    in
    Sub.batch (primary :: xpFilterSubs ++ settingsSubs ++ clearMenuSubs ++ controlMenuSubs)


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


{-| Render the user's theme choice as the `data-theme` attribute
value on the `.app-shell` div. CSS picks it up via attribute
selectors in `style.css`; `auto` defers to the OS pref via the
embedded `@media (prefers-color-scheme: dark)` block.

Delegates to `Update.Preferences.themeKey` so the wire format
(localStorage value, HTML attribute, port payload) all share a
single source of truth.

-}
themeAttr : Theme -> String
themeAttr =
    Update.Preferences.themeKey


{-| Parse a theme flag string from the JS host. Any
unrecognized value falls back to `Auto`, matching the JS-side
default in `index.html`.
-}
themeFromFlag : String -> Theme
themeFromFlag raw =
    case raw of
        "modern" ->
            Modern

        -- Old key from before the Light → Modern rename.  Any
        -- localStorage value still saying "light" gets quietly
        -- promoted; the next preference write will replace it
        -- with "modern".
        "light" ->
            Modern

        "dark" ->
            Dark

        "accessible" ->
            Accessible

        _ ->
            Auto


{-| Init flags handed in by `index.html`.

  - `theme` — user's previously-saved theme (read from
    `localStorage` before Elm boots) so the first render matches
    the FOUC pre-set on `<html data-theme>`. Unknown / missing
    strings fall back to `Auto`, matching the JS-side default.
  - `localEncounter` — raw JSON snapshot of the live encounter
    read from `localStorage` at boot, used for anonymous-mode
    sessions. Stashed verbatim on the model until the auth probe
    resolves; on `AuthAnonymous` we decode and adopt it, on
    `AuthAuthenticated` we discard it (the server is the source
    of truth, the migration prompt is a later phase).

-}
type alias Flags =
    { theme : String
    , localEncounter : Maybe Decode.Value
    }


init : Flags -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        route =
            Route.fromUrl url

        defaultPrefs =
            Preferences.default

        prefs =
            { defaultPrefs | theme = themeFromFlag flags.theme }
    in
    ( { key = key
      , url = url
      , route = route
      , me = Loading
      , auth = Auth.AuthLoading
      , loginUi = LoginUi.empty
      , encounter = Encounter.empty
      , savedSnapshot = Nothing
      , savedAs = Nothing
      , dice = DiceUi.empty
      , hpChangeLog = []
      , hpEdit = Nothing
      , compendium = CompendiumUi.emptyCompendium
      , modal = Nothing
      , panelCreaturePin = Nothing
      , pendingControl = Nothing
      , xpScope = ScopeXpEnemiesAndNpcs
      , xpFilterOpen = False
      , settingsOpen = False
      , controlMenu = Nothing
      , toasts = []
      , nextToastId = 0
      , rollPopups = []
      , nextRollPopupId = 0
      , preferences = prefs
      , cardLayout = Card.Layout.defaultLayout
      , queueView = Card.Layout.ListView
      , savedCardLayouts = []
      , useCustomCardLayout = False
      , accountUi = Ui.Account.empty
      , party = []
      , nextPartyMemberId = 1
      , localEncounterRaw = flags.localEncounter
      }
      -- Always fetch the persisted dice history alongside whatever
      -- the current route needs. Failures are silently swallowed so
      -- a fresh server (no dice-history.json yet) still loads.
      --
      -- We deliberately do NOT call `fetchEncounterCmd` or the
      -- compendium / groups / card-layout fetches here: whether
      -- each one targets the authenticated `/api/*` endpoint or the
      -- public bundled fallback depends on the auth probe's
      -- result, so we defer those decisions to
      -- `Update.Auth.meReceived`.
    , Cmd.batch
        [ Effects.fetchAuthMe
        , Effects.cmdForRoute route
        , Effects.fetchDiceHistory
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

The destination of the persist Cmd depends on the auth state:
authenticated sessions PUT to `/api/encounter`, anonymous sessions
hand the JSON to the `persistLocalEncounter` port (JS writes
`localStorage`). `AuthLoading` skips persistence — the user
shouldn't be touching the encounter before the auth probe lands,
and silently writing somewhere we'll discard either way is worse
than a one-frame gap.

-}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        ( next, innerCmd ) =
            updateInner msg model

        saveCmd =
            if shouldPersistAfter msg && next.encounter /= model.encounter then
                persistEncounterFor next.auth next.encounter

            else
                Cmd.none
    in
    ( next, Cmd.batch [ innerCmd, saveCmd ] )


persistEncounterFor : Auth.AuthState -> Encounter -> Cmd Msg
persistEncounterFor auth encounter =
    case auth of
        Auth.AuthAuthenticated _ ->
            Encounter.Wire.persistEncounterCmd EncounterPersisted encounter

        Auth.AuthAnonymous ->
            Ports.persistLocalEncounter (Encounter.Wire.encodeEncounter encounter)

        Auth.AuthLoading ->
            Cmd.none


shouldPersistAfter : Msg -> Bool
shouldPersistAfter msg =
    case msg of
        EncounterLoaded _ ->
            False

        EncounterPersisted _ ->
            False

        -- Auth probe response on an anonymous boot adopts the
        -- local-storage encounter directly into the model.  The
        -- diff would trigger a persist back into the same
        -- localStorage slot — idempotent but wasteful, so we skip
        -- it.
        AuthMeReceived _ ->
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

        CycleCover name ->
            Update.Encounter.cycleCover name model

        ToggleConcentration name ->
            Update.Encounter.toggleConcentration name model

        ToggleHiding name ->
            Update.Encounter.toggleHiding name model

        ToggleDodging name ->
            Update.Encounter.toggleDodging name model

        ToggleFlying name ->
            Update.Encounter.toggleFlying name model

        AdjustFlyHeight name delta ->
            Update.Encounter.adjustFlyHeight name delta model

        RollFallDamage name ->
            Update.Encounter.rollFallDamage name model

        FallDamageLanded name roll ->
            Update.Encounter.fallDamageLanded name roll model

        DeathSaveToggleSuccess name idx ->
            Update.DeathSave.toggleSuccess name idx model

        DeathSaveToggleFailure name idx ->
            Update.DeathSave.toggleFailure name idx model

        DeathSaveRoll name ->
            Update.DeathSave.roll name model

        DeathSaveRollLanded name roll ->
            Update.DeathSave.rollLanded name roll model

        ToggleReadied name ->
            Update.Encounter.toggleReadied name model

        ToggleInactive name ->
            Update.Encounter.toggleInactive name model

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

        RollFromStatBlock creatureName expr x y ->
            Update.Dice.rollFromStatBlock creatureName expr x y model

        StatBlockRollLanded x y roll ->
            Update.Dice.statBlockRollLanded x y roll model

        RollPopupExpired id ->
            Update.Dice.rollPopupExpired id model

        DiceLastTotalFlashCleared ->
            Update.Dice.lastTotalFlashCleared model

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

        HpChangeUndoLatest ->
            Update.HpChange.undoLatest model

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

        DuplicateOpen name ->
            Update.Duplicate.open name model

        DuplicateClose ->
            Update.Duplicate.close model

        DuplicateExact ->
            Update.Duplicate.exact model

        DuplicateFresh ->
            Update.Duplicate.fresh model

        DuplicateMinionHalf ->
            Update.Duplicate.minionHalf model

        DuplicateMinionOne ->
            Update.Duplicate.minionOne model

        DuplicatePudding ->
            Update.Duplicate.pudding model

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

        TimerSetupNoteChanged text ->
            Update.Timer.noteChanged text model

        TimerSetupApply ->
            Update.Timer.apply model

        TimerSetupCancel ->
            Update.Timer.cancel model

        TimerDismiss name ->
            Update.Timer.dismiss name model

        CompendiumLoaded result ->
            Update.Compendium.Browser.loaded result model

        CompendiumOpen ->
            Update.Compendium.Browser.open model

        CompendiumClose ->
            Update.Compendium.Browser.close model

        CompendiumSearchChanged text ->
            Update.Compendium.Browser.searchChanged text model

        CompendiumKindToggled kind ->
            Update.Compendium.Browser.kindToggled kind model

        CompendiumSortChanged sort ->
            Update.Compendium.Browser.sortChanged sort model

        CompendiumTagFilterChanged wire ->
            Update.Compendium.Browser.tagFilterChanged wire model

        CompendiumSelect id ->
            Update.Compendium.Browser.select id model

        CompendiumAddedToggle ->
            Update.Compendium.Browser.addedToggle model

        CompendiumAddToQueue creatureId ->
            Update.Compendium.Add.addToQueue creatureId model

        CompendiumInitiativeRolled creatureId rolls ->
            Update.Compendium.Add.initiativeRolled creatureId rolls model

        CompendiumAddSelectedToQueue ->
            Update.Compendium.Add.addSelectedToQueue model

        CompendiumAddSelectedRolled triples ->
            Update.Compendium.Add.addSelectedRolled triples model

        CompendiumGroupsToggle ->
            ( Update.Compendium.Browser.withCompendium
                (\ui -> { ui | showGroups = not ui.showGroups })
                model
            , Cmd.none
            )

        CompendiumGroupCreate ->
            Update.Compendium.Group.open model

        CompendiumGroupCreateFromSelected ->
            Update.Compendium.Group.openFromSelected model

        CompendiumGroupExpandToggle groupId ->
            Update.Compendium.Group.expandToggle groupId model

        CompendiumGroupSelect groupId ->
            Update.Compendium.Group.select groupId model

        CompendiumGroupDelete groupId ->
            Update.Compendium.Group.delete groupId model

        CompendiumGroupEditOpenExisting groupId ->
            Update.Compendium.Group.openExisting groupId model

        CompendiumGroupAdd groupId ->
            Update.Compendium.AddGroup.addGroup groupId model

        CompendiumGroupAddMaterialise spawns rolls ->
            Update.Compendium.AddGroup.materialise spawns rolls model

        GroupEditClose ->
            Update.Compendium.Group.close model

        GroupEditNameChanged raw ->
            Update.Compendium.Group.nameChanged raw model

        GroupEditInitiativeModeSet key ->
            Update.Compendium.Group.initiativeModeSet key model

        GroupEditManualInitiativeChanged raw ->
            Update.Compendium.Group.manualInitiativeChanged raw model

        GroupEditEntryAdd ->
            Update.Compendium.Group.entryAdd model

        GroupEditEntryRemove idx ->
            Update.Compendium.Group.entryRemove idx model

        GroupEditEntryCreatureChanged idx cid ->
            Update.Compendium.Group.entryCreatureChanged idx cid model

        GroupEditEntryCountChanged idx raw ->
            Update.Compendium.Group.entryCountChanged idx raw model

        GroupEditEntryMinionTypeSet idx key ->
            Update.Compendium.Group.entryMinionTypeSet idx key model

        GroupEditSubmit ->
            Update.Compendium.Group.submit model

        CompendiumGroupsLoaded result ->
            Update.Compendium.Group.groupsLoaded result model

        CompendiumGroupCreated result ->
            Update.Compendium.Group.created result model

        CompendiumGroupUpdated result ->
            Update.Compendium.Group.updated result model

        CompendiumGroupDeleted groupId result ->
            Update.Compendium.Group.deleteResponse groupId result model

        CardEditorOpen ->
            Update.CardEditor.open model

        CustomCardLayoutToggle ->
            ( { model | useCustomCardLayout = not model.useCustomCardLayout }
            , Cmd.none
            )

        CrCalculatorOpen ->
            Update.CrCalculator.open model

        CrCalculatorClose ->
            Update.CrCalculator.close model

        CrCalculatorScopeSet scope ->
            Update.CrCalculator.scopeSet scope model

        CrCalculatorPartyAdd ->
            Update.CrCalculator.partyMemberAdd model

        CrCalculatorPartyRemove memberId ->
            Update.CrCalculator.partyMemberRemove memberId model

        CrCalculatorPartyLevelSet memberId raw ->
            Update.CrCalculator.partyMemberLevelSet memberId raw model

        CardEditorClose ->
            Update.CardEditor.close model

        CardEditorSave ->
            Update.CardEditor.save model

        CardEditorReset ->
            Update.CardEditor.reset model

        CardEditorFocusRow idx ->
            Update.CardEditor.focusRow idx model

        CardEditorRowAdd ->
            Update.CardEditor.rowAdd model

        CardEditorRowRemove idx ->
            Update.CardEditor.rowRemove idx model

        CardEditorRowMoveUp idx ->
            Update.CardEditor.rowMoveUp idx model

        CardEditorRowMoveDown idx ->
            Update.CardEditor.rowMoveDown idx model

        CardEditorRowAlignmentSet idx key ->
            Update.CardEditor.rowAlignmentSet idx key model

        CardEditorWidgetAdd idx key ->
            Update.CardEditor.widgetAdd idx key model

        CardEditorWidgetRemove rowIdx widgetIdx ->
            Update.CardEditor.widgetRemove rowIdx widgetIdx model

        CardEditorQueueViewSet key ->
            Update.CardEditor.queueViewSet key model

        CardEditorLayoutNameChanged raw ->
            Update.CardEditor.saveNameChanged raw model

        CardEditorSaveAs ->
            Update.CardEditor.saveAs model

        CardEditorOverwriteConfirm ->
            Update.CardEditor.overwriteConfirm model

        CardEditorOverwriteCancel ->
            Update.CardEditor.overwriteCancel model

        CardEditorLoad name ->
            Update.CardEditor.load name model

        CardEditorDelete name ->
            Update.CardEditor.delete name model

        CardEditorLayoutsLoaded result ->
            Update.CardEditor.layoutsLoaded result model

        CardEditorLayoutFetched result ->
            Update.CardEditor.layoutFetched result model

        CardEditorLayoutSaved result ->
            Update.CardEditor.layoutSaved result model

        CardEditorLayoutDeleted name result ->
            Update.CardEditor.layoutDeleted name result model

        CompendiumEditNew ->
            Update.Compendium.Edit.new model

        CompendiumEditExisting ->
            Update.Compendium.Edit.existing model

        CompendiumEditDuplicate ->
            Update.Compendium.Edit.duplicate model

        CompendiumEditCancel ->
            Update.Compendium.Edit.cancel model

        CompendiumEditFieldChanged field text ->
            Update.Compendium.Edit.fieldChanged field text model

        CompendiumEditKindSet kind ->
            Update.Compendium.Edit.kindSet kind model

        CompendiumEditSizeSet size ->
            Update.Compendium.Edit.sizeSet size model

        CompendiumEditSpeedHoverToggle ->
            Update.Compendium.Edit.speedHoverToggle model

        CompendiumEditSavingThrowAdd ->
            Update.Compendium.Edit.savingThrowAdd model

        CompendiumEditSavingThrowRemove idx ->
            Update.Compendium.Edit.savingThrowRemove idx model

        CompendiumEditSavingThrowAbilitySet idx ability ->
            Update.Compendium.Edit.savingThrowAbilitySet idx ability model

        CompendiumEditSavingThrowBonusChanged idx text ->
            Update.Compendium.Edit.savingThrowBonusChanged idx text model

        CompendiumEditSkillAdd ->
            Update.Compendium.Edit.skillAdd model

        CompendiumEditSkillRemove idx ->
            Update.Compendium.Edit.skillRemove idx model

        CompendiumEditSkillNameChanged idx text ->
            Update.Compendium.Edit.skillNameChanged idx text model

        CompendiumEditSkillBonusChanged idx text ->
            Update.Compendium.Edit.skillBonusChanged idx text model

        CompendiumEditFeatureAdd group ->
            Update.Compendium.Edit.featureAdd group model

        CompendiumEditFeatureRemove group idx ->
            Update.Compendium.Edit.featureRemove group idx model

        CompendiumEditFeatureNameChanged group idx text ->
            Update.Compendium.Edit.featureNameChanged group idx text model

        CompendiumEditFeatureDescriptionChanged group idx text ->
            Update.Compendium.Edit.featureDescriptionChanged group idx text model

        CompendiumEditFeatureUsageKindSet group idx kind ->
            Update.Compendium.Edit.featureUsageKindSet group idx kind model

        CompendiumEditFeatureUsageRechargeLowChanged group idx text ->
            Update.Compendium.Edit.featureUsageRechargeLowChanged group idx text model

        CompendiumEditFeatureUsageRechargeHighChanged group idx text ->
            Update.Compendium.Edit.featureUsageRechargeHighChanged group idx text model

        CompendiumEditFeatureUsageUsesChanged group idx text ->
            Update.Compendium.Edit.featureUsageUsesChanged group idx text model

        CompendiumEditCustomSectionAdd ->
            Update.Compendium.Edit.customSectionAdd model

        CompendiumEditCustomSectionRemove idx ->
            Update.Compendium.Edit.customSectionRemove idx model

        CompendiumEditCustomSectionNameChanged idx text ->
            Update.Compendium.Edit.customSectionNameChanged idx text model

        CompendiumEditCustomSectionBodyChanged idx text ->
            Update.Compendium.Edit.customSectionBodyChanged idx text model

        CompendiumEditDamageToggle picker name ->
            Update.Compendium.Edit.damageToggle picker name model

        CompendiumEditConditionToggle name ->
            Update.Compendium.Edit.conditionToggle name model

        CompendiumEditHabitatToggle h ->
            Update.Compendium.Edit.habitatToggle h model

        CompendiumEditTreasureToggle t ->
            Update.Compendium.Edit.treasureToggle t model

        CompendiumEditTagAdd ->
            Update.Compendium.Edit.tagAdd model

        CompendiumEditTagRemove idx ->
            Update.Compendium.Edit.tagRemove idx model

        CompendiumEditTagChanged idx text ->
            Update.Compendium.Edit.tagChanged idx text model

        CompendiumEditLegendaryAdd ->
            Update.Compendium.Edit.legendaryAdd model

        CompendiumEditLegendaryRemove ->
            Update.Compendium.Edit.legendaryRemove model

        CompendiumEditLegendaryDescriptionChanged text ->
            Update.Compendium.Edit.legendaryDescriptionChanged text model

        CompendiumEditLegendaryUsesChanged text ->
            Update.Compendium.Edit.legendaryUsesChanged text model

        CompendiumEditLegendaryUsesInLairChanged text ->
            Update.Compendium.Edit.legendaryUsesInLairChanged text model

        CompendiumEditLegendaryOptionAdd ->
            Update.Compendium.Edit.legendaryOptionAdd model

        CompendiumEditLegendaryOptionRemove idx ->
            Update.Compendium.Edit.legendaryOptionRemove idx model

        CompendiumEditLegendaryOptionNameChanged idx text ->
            Update.Compendium.Edit.legendaryOptionNameChanged idx text model

        CompendiumEditLegendaryOptionDescriptionChanged idx text ->
            Update.Compendium.Edit.legendaryOptionDescriptionChanged idx text model

        CompendiumEditLairAdd ->
            Update.Compendium.Edit.lairAdd model

        CompendiumEditLairRemove ->
            Update.Compendium.Edit.lairRemove model

        CompendiumEditLairInitiativeChanged text ->
            Update.Compendium.Edit.lairInitiativeChanged text model

        CompendiumEditLairDescriptionChanged text ->
            Update.Compendium.Edit.lairDescriptionChanged text model

        CompendiumEditLairOptionAdd ->
            Update.Compendium.Edit.lairOptionAdd model

        CompendiumEditLairOptionRemove idx ->
            Update.Compendium.Edit.lairOptionRemove idx model

        CompendiumEditLairOptionNameChanged idx text ->
            Update.Compendium.Edit.lairOptionNameChanged idx text model

        CompendiumEditLairOptionDescriptionChanged idx text ->
            Update.Compendium.Edit.lairOptionDescriptionChanged idx text model

        CompendiumEditRegionalAdd ->
            Update.Compendium.Edit.regionalAdd model

        CompendiumEditRegionalRemove ->
            Update.Compendium.Edit.regionalRemove model

        CompendiumEditRegionalDescriptionChanged text ->
            Update.Compendium.Edit.regionalDescriptionChanged text model

        CompendiumEditRegionalFadeAfterChanged text ->
            Update.Compendium.Edit.regionalFadeAfterChanged text model

        CompendiumEditRegionalEffectAdd ->
            Update.Compendium.Edit.regionalEffectAdd model

        CompendiumEditRegionalEffectRemove idx ->
            Update.Compendium.Edit.regionalEffectRemove idx model

        CompendiumEditRegionalEffectNameChanged idx text ->
            Update.Compendium.Edit.regionalEffectNameChanged idx text model

        CompendiumEditRegionalEffectDescriptionChanged idx text ->
            Update.Compendium.Edit.regionalEffectDescriptionChanged idx text model

        CompendiumEditSpellcastingAdd ->
            Update.Compendium.Edit.spellcastingAdd model

        CompendiumEditSpellcastingRemove ->
            Update.Compendium.Edit.spellcastingRemove model

        CompendiumEditSpellcastingDescriptionChanged text ->
            Update.Compendium.Edit.spellcastingDescriptionChanged text model

        CompendiumEditSpellcastingAbilitySet ability ->
            Update.Compendium.Edit.spellcastingAbilitySet ability model

        CompendiumEditSpellcastingSaveDcChanged text ->
            Update.Compendium.Edit.spellcastingSaveDcChanged text model

        CompendiumEditSpellcastingAttackBonusChanged text ->
            Update.Compendium.Edit.spellcastingAttackBonusChanged text model

        CompendiumEditSpellcastingAtWillChanged text ->
            Update.Compendium.Edit.spellcastingAtWillChanged text model

        CompendiumEditSpellcastingSlotAdd ->
            Update.Compendium.Edit.spellcastingSlotAdd model

        CompendiumEditSpellcastingSlotRemove idx ->
            Update.Compendium.Edit.spellcastingSlotRemove idx model

        CompendiumEditSpellcastingSlotLevelChanged idx text ->
            Update.Compendium.Edit.spellcastingSlotLevelChanged idx text model

        CompendiumEditSpellcastingSlotCountChanged idx text ->
            Update.Compendium.Edit.spellcastingSlotCountChanged idx text model

        CompendiumEditSpellcastingSlotSpellsChanged idx text ->
            Update.Compendium.Edit.spellcastingSlotSpellsChanged idx text model

        CompendiumEditSpellcastingInnateAdd ->
            Update.Compendium.Edit.spellcastingInnateAdd model

        CompendiumEditSpellcastingInnateRemove idx ->
            Update.Compendium.Edit.spellcastingInnateRemove idx model

        CompendiumEditSpellcastingInnateUsesChanged idx text ->
            Update.Compendium.Edit.spellcastingInnateUsesChanged idx text model

        CompendiumEditSpellcastingInnateSpellsChanged idx text ->
            Update.Compendium.Edit.spellcastingInnateSpellsChanged idx text model

        CompendiumEditSubmit ->
            Update.Compendium.Edit.submit model

        CompendiumEditSubmitResponse result ->
            Update.Compendium.Edit.submitResponse result model

        CompendiumEditDelete ->
            Update.Compendium.Edit.delete model

        CompendiumEditDeleteResponse id result ->
            Update.Compendium.Edit.deleteResponse id result model

        CompendiumPasteOpen ->
            Update.Compendium.Paste.open model

        CompendiumPasteCancel ->
            Update.Compendium.Paste.cancel model

        CompendiumPasteTextChanged text ->
            Update.Compendium.Paste.textChanged text model

        CompendiumPasteApply ->
            Update.Compendium.Paste.apply model

        PanelShowCreature creatureId creatureName ->
            Update.Compendium.Browser.panelShowCreature creatureId creatureName model

        ToggleLegendaryActionPip name idx ->
            Update.LegendaryPip.toggleAction name idx model

        ToggleLegendaryResistancePip name idx ->
            Update.LegendaryPip.toggleResistance name idx model

        EncounterLoaded result ->
            Update.Shell.encounterLoaded result model

        EncounterPersisted result ->
            Update.Shell.encounterPersisted result model

        SaveOpen destination ->
            Update.Save.open destination model

        SaveClose ->
            Update.Save.close model

        SaveDestinationSet dest ->
            Update.Save.destinationSet dest model

        SaveFilenameChanged text ->
            Update.Save.filenameChanged text model

        SaveSubmit ->
            Update.Save.submit model

        SaveListLoaded result ->
            Update.Save.listLoaded result model

        SavePersistResponse name result ->
            Update.Save.persistResponse name result model

        SaveOverwriteRequested name ->
            Update.Save.overwriteRequested name model

        SaveDeleteRequested name ->
            Update.Save.deleteRequested name model

        SaveConfirmCancel ->
            Update.Save.confirmCancel model

        SaveConfirmConfirm ->
            Update.Save.confirmConfirm model

        SaveDeleteResponse name result ->
            Update.Save.deleteResponse name result model

        SaveRenameStart name ->
            Update.Save.renameStart name model

        SaveRenameChange text ->
            Update.Save.renameChange text model

        SaveRenameSubmit ->
            Update.Save.renameSubmit model

        SaveRenameCancel ->
            Update.Save.renameCancel model

        SaveRenameResponse names result ->
            Update.Save.renameResponse names result model

        LoadOpen ->
            Update.Load.open model

        LoadClose ->
            Update.Load.close model

        LoadFromServerRequested name ->
            Update.Load.fromServerRequested name model

        LoadConfirmCancel ->
            Update.Load.confirmCancel model

        LoadConfirmConfirm ->
            Update.Load.confirmConfirm model

        LoadServerResponse name result ->
            Update.Load.serverResponse name result model

        LoadDeleteRequested name ->
            Update.Load.deleteRequested name model

        LoadDeleteResponse name result ->
            Update.Load.deleteResponse name result model

        LoadRenameStart name ->
            Update.Load.renameStart name model

        LoadRenameChange text ->
            Update.Load.renameChange text model

        LoadRenameSubmit ->
            Update.Load.renameSubmit model

        LoadRenameCancel ->
            Update.Load.renameCancel model

        LoadRenameResponse names result ->
            Update.Load.renameResponse names result model

        LoadListLoaded result ->
            Update.Load.listLoaded result model

        LoadFromDeviceClick ->
            Update.Load.fromDeviceClick model

        LoadFromDeviceFileChosen file ->
            Update.Load.fromDeviceFileChosen file model

        LoadFromDeviceFileRead raw ->
            Update.Load.fromDeviceFileRead raw model

        SaveCompendiumOpen destination ->
            Update.SaveCompendium.open destination model

        SaveCompendiumClose ->
            Update.SaveCompendium.close model

        SaveCompendiumDestinationSet dest ->
            Update.SaveCompendium.destinationSet dest model

        SaveCompendiumFilenameChanged text ->
            Update.SaveCompendium.filenameChanged text model

        SaveCompendiumSubmit ->
            Update.SaveCompendium.submit model

        SaveCompendiumListLoaded result ->
            Update.SaveCompendium.listLoaded result model

        SaveCompendiumPersistResponse name result ->
            Update.SaveCompendium.persistResponse name result model

        SaveCompendiumOverwriteRequested name ->
            Update.SaveCompendium.overwriteRequested name model

        SaveCompendiumConfirmCancel ->
            Update.SaveCompendium.confirmCancel model

        SaveCompendiumConfirmConfirm ->
            Update.SaveCompendium.confirmConfirm model

        LoadCompendiumOpen ->
            Update.LoadCompendium.open model

        LoadCompendiumClose ->
            Update.LoadCompendium.close model

        LoadCompendiumListLoaded result ->
            Update.LoadCompendium.listLoaded result model

        LoadCompendiumFromServerRequested name ->
            Update.LoadCompendium.fromServerRequested name model

        LoadCompendiumConfirmCancel ->
            Update.LoadCompendium.confirmCancel model

        LoadCompendiumConfirmConfirm ->
            Update.LoadCompendium.confirmConfirm model

        LoadCompendiumServerResponse name result ->
            Update.LoadCompendium.serverResponse name result model

        EncounterReset ->
            Update.Encounter.requestReset model

        EncounterClear ->
            Update.Encounter.requestClear model

        EncounterControlConfirm ->
            Update.Encounter.controlConfirm model

        EncounterControlCancel ->
            Update.Encounter.controlCancel model

        EncounterRun ->
            Update.Encounter.run model

        XpScopeSet scope ->
            ( { model | xpScope = scope, xpFilterOpen = False }, Cmd.none )

        XpFilterToggle ->
            ( { model | xpFilterOpen = not model.xpFilterOpen }, Cmd.none )

        XpFilterClose ->
            ( { model | xpFilterOpen = False }, Cmd.none )

        QuickAddOpen ->
            Update.QuickAdd.open model

        QuickAddClose ->
            Update.QuickAdd.close model

        QuickAddSortToggle ->
            Update.QuickAdd.sortToggle model

        QuickAddSearchChanged text ->
            Update.QuickAdd.searchChanged text model

        QuickAddPick id ->
            Update.QuickAdd.pick id model

        AbilitySaveOpen creatureName ability bonus x y ->
            Update.AbilitySave.open creatureName ability bonus x y model

        AbilitySaveClose ->
            Update.AbilitySave.close model

        AbilitySaveRoll mode ->
            Update.AbilitySave.roll mode model

        AbilitySaveLanded x y roll ->
            Update.AbilitySave.landed x y roll model

        CompendiumImportClick ->
            Update.Compendium.Bulk.importClick model

        CompendiumImportFileChosen file ->
            Update.Compendium.Bulk.importFileChosen file model

        CompendiumImportFileRead raw ->
            Update.Compendium.Bulk.importFileRead raw model

        CompendiumResetClick ->
            Update.Compendium.Bulk.resetClick model

        CompendiumDeleteFromBrowser id displayName ->
            Update.Compendium.Bulk.deleteFromBrowser id displayName model

        CompendiumPendingCancel ->
            Update.Compendium.Bulk.pendingCancel model

        CompendiumPendingConfirm ->
            Update.Compendium.Bulk.pendingConfirm model

        CompendiumImportResponse result ->
            Update.Compendium.Bulk.importResponse result model

        CompendiumResetResponse result ->
            Update.Compendium.Bulk.resetResponse result model

        CompendiumClearResponse result ->
            Update.Compendium.Bulk.clearResponse result model

        CompendiumRowToggle id shift ->
            Update.Compendium.Browser.rowToggle id shift model

        CompendiumBulkMenuToggle which ->
            Update.Compendium.Browser.bulkMenuToggle which model

        CompendiumBulkMenuClose ->
            Update.Compendium.Browser.bulkMenuClose model

        CompendiumClearAll ->
            Update.Compendium.Bulk.clearAll model

        CompendiumClearSelected ->
            Update.Compendium.Bulk.clearSelected model

        CompendiumDeleteSelected ->
            Update.Compendium.Bulk.deleteSelected model

        CompendiumExportClick ->
            Update.Compendium.Browser.exportClick model

        ToastDismiss id ->
            Update.Toast.dismiss id model

        PreferencesThemeSet theme ->
            Update.Preferences.themeSet theme model

        SettingsToggle ->
            Update.Shell.settingsToggle model

        SettingsClose ->
            Update.Shell.settingsClose model

        ControlMenuToggle which ->
            Update.Shell.controlMenuToggle which model

        ControlMenuClose ->
            Update.Shell.controlMenuClose model

        CompendiumFocusSearch ->
            Update.Compendium.Browser.focusSearch model

        AuthMeReceived result ->
            Update.Auth.meReceived result model

        AuthLoginEmailChanged value ->
            Update.Auth.emailChanged value model

        AuthLoginPasswordChanged value ->
            Update.Auth.passwordChanged value model

        AuthLoginDisplayNameChanged value ->
            Update.Auth.displayNameChanged value model

        AuthLoginModeChanged mode ->
            Update.Auth.modeChanged mode model

        AuthLoginSubmit ->
            Update.Auth.submit model

        AuthLoginResponse result ->
            Update.Auth.response result model

        AuthLogout ->
            Update.Auth.logout model

        AuthLogoutDone result ->
            Update.Auth.logoutDone result model

        NavigateToLogin ->
            ( model, Nav.pushUrl model.key "/login" )

        AccountDisplayNameChanged raw ->
            Update.Account.displayNameChanged raw model

        AccountProfileSubmit ->
            Update.Account.submitProfile model

        AccountProfileSaved result ->
            Update.Account.profileSaved result model

        AccountCurrentPasswordChanged raw ->
            Update.Account.currentPasswordChanged raw model

        AccountNewPasswordChanged raw ->
            Update.Account.newPasswordChanged raw model

        AccountConfirmPasswordChanged raw ->
            Update.Account.confirmPasswordChanged raw model

        AccountPasswordSubmit ->
            Update.Account.submitPassword model

        AccountPasswordChanged result ->
            Update.Account.passwordChanged result model

        NoOp ->
            Update.Shell.noOp model



-- VIEW


{-| Browser tab title. Defaults to the app name but switches to
the creature's display name on the standalone single-creature
page (`/compendium/creatures/:id`) so GMs who park multiple
stat-block tabs can tell them apart at a glance. Falls back to
the app name when the compendium hasn't loaded yet or the id
doesn't match any creature.
-}
documentTitle : Model -> String
documentTitle model =
    let
        default =
            "eZpZ-dndZ"
    in
    case model.route of
        CompendiumCreaturePage id ->
            case model.compendium.db of
                CompendiumDbLoaded db ->
                    Compendium.find id db
                        |> Maybe.map .name
                        |> Maybe.withDefault default

                _ ->
                    default

        _ ->
            default


view : Model -> Browser.Document Msg
view model =
    { title = documentTitle model
    , body =
        [ div
            [ class "app-shell"
            , attribute "data-theme" (themeAttr model.preferences.theme)
            ]
            (case model.auth of
                Auth.AuthLoading ->
                    [ div [ class "auth-login" ]
                        [ div [ class "auth-login__panel" ]
                            [ p [ class "auth-login__tagline" ]
                                [ text "Loading…" ]
                            ]
                        ]
                    ]

                Auth.AuthAnonymous ->
                    appShell Nothing model

                Auth.AuthAuthenticated user ->
                    appShell (Just user) model
            )
        ]
    }


{-| Common rendered shell shared by anonymous and authenticated
sessions. AppBar takes a `Maybe Auth.User` so it can swap the
identity link for "Sign in" when the session is local-only; the
rest of the chrome (modals, toasts, ringer) is the same either
way — anonymous users get the full app, they just persist to
`localStorage` instead of the server.
-}
appShell : Maybe Auth.User -> Model -> List (Html Msg)
appShell maybeUser model =
    [ View.AppBar.view model.settingsOpen model.preferences.theme maybeUser model.useCustomCardLayout
    , viewPage model
    , View.Modal.Dice.view model.dice
    , View.Modal.HpChange.view model
    , View.Modal.Initiative.view model
    , View.Modal.Note.view model
    , View.Modal.Condition.view model
    , View.Modal.Memo.view model
    , View.Modal.Timer.view model
    , View.Modal.Compendium.view model.auth
        model.compendium
        (List.filterMap .creatureId model.encounter.creatures)
    , View.Modal.CompendiumEdit.view model
    , View.Modal.CompendiumPaste.view model
    , View.Modal.Save.view model
    , View.Modal.Load.view model
    , View.Modal.SaveCompendium.view model
    , View.Modal.LoadCompendium.view model
    , View.Modal.AbilitySave.view model
    , View.Modal.QuickAdd.view model
    , View.Modal.Duplicate.view model
    , View.Modal.GroupEdit.view model
    , View.Modal.CardEditor.view model
    , View.Modal.CrCalculator.view model
    , View.Toast.list model.toasts
    , View.RollPopup.list model.rollPopups
    , View.Audio.ringer model
    , View.Footer.view
    ]


viewPage : Model -> Html Msg
viewPage model =
    case model.route of
        Home ->
            View.Workspace.view model

        Login ->
            View.Login.view model.loginUi

        Me ->
            View.Account.view model

        Donate ->
            div [ class "workspace" ]
                [ section [ class "panel panel--main" ]
                    [ div [ class "panel__header" ]
                        [ div [ class "panel__title" ] [ text "Donate" ] ]
                    , div [ class "panel__body" ]
                        [ p [ class "empty" ]
                            [ text "This page is under construction. Thanks for thinking about supporting the project!" ]
                        ]
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
                            View.StatBlock.view RollFromStatBlock AbilitySaveOpen View.StatBlock.TagBadges creature

                        Nothing ->
                            p [ class "empty" ]
                                [ text "Creature not found in the compendium." ]
    in
    div [ class "workspace workspace--standalone" ]
        [ section [ class "panel panel--standalone" ]
            [ div [ class "panel__body" ] [ body ] ]
        ]
