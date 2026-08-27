module Main exposing (Flags, main)

import Auth
import Browser
import Browser.Dom
import Browser.Events
import Browser.Navigation as Nav
import Compendium
import Compendium.GroupWire
import Compendium.Wire
import Dict
import Effects
import Encounter
    exposing
        ( Cover(..)
        , Creature
        , Encounter
        )
import Encounter.Difficulty as Difficulty
import Encounter.RandomEncounter.Lore.Wire
import Encounter.Roster
import Encounter.SaveChain.Bundled
import Encounter.SaveChain.Wire
import Encounter.Treasure.ProfileWire
import Encounter.Treasure.TableWire
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
import Model exposing (Model, Surface(..))
import Msg
    exposing
        ( CompendiumField(..)
        , CompendiumSort(..)
        , ControlMenu(..)
        , DurationKind(..)
        , FeatureGroup(..)
        , HpField(..)
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
import Ui.AbilitySave
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
import Ui.Condition.Bundled
import Ui.Condition.Wire
import Ui.Dice as DiceUi exposing (DiceUi)
import Ui.HpChange as HpChangeUi exposing (HpChangeEntry, HpChangeUi, HpEdit)
import Ui.Initiative as InitiativeUi exposing (InitiativeUi)
import Ui.Login as LoginUi
import Ui.ModalChrome
import Ui.Timer.Wire
import Ui.Toast
import Update.AbilitySave
import Update.Account
import Update.Auth
import Update.Compendium.Add
import Update.Compendium.AddGroup
import Update.Compendium.Browser
import Update.Compendium.Bulk
import Update.Compendium.Edit
import Update.Compendium.Group
import Update.Compendium.Lore
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
import Update.LoreEdit
import Update.Memo
import Update.ModalChrome
import Update.Note
import Update.PlaceholderRename
import Update.Preferences
import Update.QuickAdd
import Update.RandomEncounter
import Update.Save
import Update.SaveChain
import Update.SaveCompendium
import Update.Shell
import Update.SpellList
import Update.Tabs
import Update.Timer
import Update.Toast
import Update.Treasure
import Update.TreasureTable
import Update.UserSync
import Url exposing (Url)
import Util.Keyboard
import View.About
import View.Account
import View.AnonymousBanner
import View.AppBar
import View.Audio
import View.Card
import View.Footer
import View.Login
import View.Modal
import View.Modal.AbilitySave
import View.Modal.Compendium
import View.Modal.CompendiumEdit
import View.Modal.CompendiumPaste
import View.Modal.CrCalculator
import View.Modal.Dice
import View.Modal.Duplicate
import View.Modal.GroupEdit
import View.Modal.Initiative
import View.Modal.Load
import View.Modal.LoadCompendium
import View.Modal.LoreEdit
import View.Modal.QuickAdd
import View.Modal.RandomEncounter
import View.Modal.Save
import View.Modal.SaveCompendium
import View.Modal.SpellList
import View.Modal.Treasure
import View.Modal.TreasureTable
import View.Page.Compendium
import View.Page.CompendiumStandalone
import View.Page.Donate
import View.Page.Loading
import View.Page.NotFound
import View.Page.QuickList
import View.RollPopup
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

        conditionPresetLoadMenuSubs =
            case model.surface of
                Just (SurfaceCondition ui) ->
                    if ui.loadMenuOpen then
                        [ Browser.Events.onKeyDown (escKey ConditionPresetLoadMenuClose)
                        , Browser.Events.onMouseDown (Decode.succeed ConditionPresetLoadMenuClose)
                        ]

                    else
                        []

                _ ->
                    []

        timerPresetLoadMenuSubs =
            case model.surface of
                Just (SurfaceTimerSetup ui) ->
                    if ui.loadMenuOpen then
                        [ Browser.Events.onKeyDown (escKey TimerPresetLoadMenuClose)
                        , Browser.Events.onMouseDown (Decode.succeed TimerPresetLoadMenuClose)
                        ]

                    else
                        []

                _ ->
                    []

        -- Esc on the Login route cancels back to the encounter
        -- page.  Scoped to the route so it doesn't intercept Esc
        -- on the main app (where the existing modal handlers want
        -- it for their own dismissal).
        loginEscSubs =
            if model.route == Login then
                [ Browser.Events.onKeyDown (escKey LoginCancel) ]

            else
                []

        -- Surface chrome drag / resize subscriptions.  Only active
        -- while a gesture is in flight — the rest of the time
        -- mousemove / mouseup go through the browser's default
        -- handling.
        chromeSubs =
            case ( model.modalChrome.drag, model.modalChrome.resize ) of
                ( Just _, _ ) ->
                    [ Browser.Events.onMouseMove (mouseMoveDecoder ModalChromeDragMove)
                    , Browser.Events.onMouseUp (Decode.succeed ModalChromeDragEnd)
                    ]

                ( _, Just _ ) ->
                    [ Browser.Events.onMouseMove (mouseMoveDecoder ModalChromeResizeMove)
                    , Browser.Events.onMouseUp (Decode.succeed ModalChromeResizeEnd)
                    ]

                ( Nothing, Nothing ) ->
                    []

        primary =
            if model.dice.open then
                Browser.Events.onKeyDown (escKey CloseDice)

            else
                case model.surface of
                    Just (SurfaceCompendiumPaste _) ->
                        Browser.Events.onKeyDown (escKey CompendiumPasteCancel)

                    Just (SurfaceCompendiumEdit _) ->
                        Browser.Events.onKeyDown (escKey CompendiumEditCancel)

                    Just (SurfaceNoteEdit _) ->
                        Browser.Events.onKeyDown (escKey NoteEditCancel)

                    Just (SurfaceHpChange _) ->
                        Browser.Events.onKeyDown (escKey HpChangeClose)

                    Just (SurfaceMemoEdit _) ->
                        Browser.Events.onKeyDown (escKey MemoCancel)

                    Just (SurfaceCondition ui) ->
                        -- While the preset Load menu is open, Esc
                        -- belongs to `conditionPresetLoadMenuSubs`
                        -- (closing just the menu); claiming it here
                        -- too would collapse the whole editor on
                        -- the same keypress.
                        if ui.loadMenuOpen then
                            Sub.none

                        else
                            Browser.Events.onKeyDown (escKey ConditionClose)

                    Just (SurfaceTimerSetup ui) ->
                        -- Same menu-first Esc split as the condition
                        -- editor above.
                        if ui.loadMenuOpen then
                            Sub.none

                        else
                            Browser.Events.onKeyDown (escKey TimerSetupCancel)

                    Just (SurfaceSaveChain _) ->
                        Browser.Events.onKeyDown (escKey SaveChainClose)

                    Just (SurfaceSave _) ->
                        Browser.Events.onKeyDown (escKey SaveClose)

                    Just (SurfaceLoad _) ->
                        Browser.Events.onKeyDown (escKey LoadClose)

                    Just (SurfaceSaveCompendium _) ->
                        Browser.Events.onKeyDown (escKey SaveCompendiumClose)

                    Just (SurfaceLoadCompendium _) ->
                        Browser.Events.onKeyDown (escKey LoadCompendiumClose)

                    Just (SurfaceAbilitySave _) ->
                        Browser.Events.onKeyDown (escKey AbilitySaveClose)

                    Just (SurfaceQuickAdd _) ->
                        Browser.Events.onKeyDown (escKey QuickAddClose)

                    Just (SurfaceDuplicate _) ->
                        Browser.Events.onKeyDown (escKey DuplicateClose)

                    _ ->
                        if model.compendium.open then
                            Browser.Events.onKeyDown compendiumKeyDecoder

                        else
                            Sub.none
    in
    Sub.batch
        (primary
            :: Ports.incomingDiceRoll DiceRollFromOtherTab
            :: Ports.incomingEncounter EncounterFromOtherTab
            :: Ports.incomingPanelShow Update.Tabs.panelShowFromOtherTab
            :: Ports.compendiumTabMissing (\_ -> CompendiumTabMissing)
            :: xpFilterSubs
            ++ settingsSubs
            ++ clearMenuSubs
            ++ controlMenuSubs
            ++ conditionPresetLoadMenuSubs
            ++ timerPresetLoadMenuSubs
            ++ loginEscSubs
            ++ chromeSubs
        )


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


{-| Decode a MouseEvent into a `Msg` carrying `clientX, clientY`.
Used by the modal-chrome drag and resize subscriptions to
translate native mousemove events into update branches.
-}
mouseMoveDecoder : (Int -> Int -> Msg) -> Decode.Decoder Msg
mouseMoveDecoder toMsg =
    Decode.map2 toMsg
        (Decode.field "clientX" Decode.int)
        (Decode.field "clientY" Decode.int)


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
unrecognized value falls back to `Modern`, matching the JS-side
default in `index.html`. Legacy keys (`light` from before the
Light → Modern rename, `auto` from before the OS-follow theme
was removed) get quietly promoted to `Modern`; the next
preference write replaces them in localStorage.
-}
themeFromFlag : String -> Theme
themeFromFlag raw =
    case raw of
        "modern" ->
            Modern

        "dark" ->
            Dark

        "accessible" ->
            Accessible

        _ ->
            Modern


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
  - `migrationDateLabel` — short formatted date string from JS
    (`Date.now()` localized to the user's browser) used as the
    suffix on the named save slot when an anonymous encounter
    is migrated into the server on login (e.g.
    `Local — May 26, 2026`). JS computes it so we don't have
    to pull in elm/time + a calendar formatter.
  - `localDiceHistory` — one-shot snapshot of the anonymous
    session's roll history (mirrors the `/api/dice/history`
    response shape). Adopted on anonymous boot, discarded on
    authenticated boot.
  - `localCompendium` — one-shot snapshot of the anonymous
    compendium (creatures + groups + next-local-id counter).
    When present the anonymous boot branch decodes and adopts
    it in place of fetching the bundled JSON.
  - `localEncounterSaves` — anonymous named-encounter-saves
    dict (`{ name → { encounter, created_at, updated_at } }`)
    that the Save / Load modals consult instead of `/api/encounter/saves`.
  - `bootMs` — `Date.now()` at boot, used as the timestamp on
    every anonymous named-save write done this session.

-}
type alias Flags =
    { theme : String
    , localEncounter : Maybe Decode.Value
    , migrationDateLabel : String
    , localDiceHistory : Maybe Decode.Value
    , localCompendium : Maybe Decode.Value
    , localEncounterSaves : Maybe Decode.Value
    , localConditionPresets : Maybe Decode.Value
    , localTimerPresets : Maybe Decode.Value
    , localSaveChainPresets : Maybe Decode.Value
    , localParty : Maybe Decode.Value
    , localUserLoreGroups : Maybe Decode.Value
    , localUserTreasureTable : Maybe Decode.Value
    , bootMs : Int
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

        partyFromFlags =
            flags.localParty
                |> Maybe.andThen
                    (Decode.decodeValue Difficulty.decodePartyState
                        >> Result.toMaybe
                    )
                |> Maybe.withDefault { members = [], nextId = 1 }
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
      , saveChainLog = []
      , hpEdit = Nothing
      , compendium = CompendiumUi.emptyCompendium
      , surface = Nothing
      , hpChangeDraft = Nothing
      , conditionDraft = Nothing
      , saveChainDraft = Nothing
      , conditionLog = []
      , modalChrome = Ui.ModalChrome.fresh
      , placeholderRename = Nothing
      , panelCreaturePin = Nothing
      , pendingControl = Nothing
      , xpScope = ScopeXpEnemiesAndNpcs
      , xpFilterOpen = False
      , settingsOpen = False
      , anonymousBannerDismissed = False
      , controlMenu = Nothing
      , toasts = []
      , nextToastId = 0
      , rollPopups = []
      , nextRollPopupId = 0
      , preferences = prefs
      , accountUi = Ui.Account.empty
      , party = partyFromFlags.members
      , nextPartyMemberId = partyFromFlags.nextId
      , localEncounterRaw = flags.localEncounter
      , migrationDateLabel = flags.migrationDateLabel
      , localDiceHistoryRaw = flags.localDiceHistory
      , localCompendiumRaw = flags.localCompendium
      , pendingBundleMerge = False
      , nextLocalCreatureId = 1
      , localEncounterSaves =
            flags.localEncounterSaves
                |> Maybe.andThen
                    (Decode.decodeValue Encounter.Wire.decodeLocalEncounterSaves
                        >> Result.toMaybe
                    )
                |> Maybe.withDefault Dict.empty
      , conditionPresets =
            case flags.localConditionPresets of
                Just raw ->
                    -- localStorage.conditionPresets exists (even
                    -- as `{}`).  Decode what's there; don't
                    -- re-seed.  A GM who deleted every bundled
                    -- default doesn't want them silently re-added.
                    Decode.decodeValue Ui.Condition.Wire.decodePresets raw
                        |> Result.withDefault Dict.empty

                Nothing ->
                    -- First boot: no localStorage key yet.  Seed
                    -- the dict with the bundled SRD 5.2.1 default
                    -- presets so the four collapsible categories
                    -- in the Load menu are populated out of the
                    -- box.
                    Ui.Condition.Bundled.defaults
      , timerPresets =
            flags.localTimerPresets
                |> Maybe.andThen
                    (Decode.decodeValue Ui.Timer.Wire.decodePresets
                        >> Result.toMaybe
                    )
                |> Maybe.withDefault Dict.empty
      , saveChainPresets =
            flags.localSaveChainPresets
                |> Maybe.andThen
                    (Decode.decodeValue Encounter.SaveChain.Wire.decodePresets
                        >> Result.toMaybe
                    )
                |> Maybe.withDefault Encounter.SaveChain.Bundled.defaults
      , userLoreGroups =
            flags.localUserLoreGroups
                |> Maybe.andThen
                    (Decode.decodeValue Encounter.RandomEncounter.Lore.Wire.decodeGroups
                        >> Result.toMaybe
                    )
                |> Maybe.withDefault []
      , userTreasureTable =
            flags.localUserTreasureTable
                |> Maybe.andThen
                    (Decode.decodeValue Encounter.Treasure.TableWire.decodeTable
                        >> Result.toMaybe
                    )
      , userTreasureProfiles = Dict.empty
      , userTreasureProfileNameDraft = ""
      , bootMs = flags.bootMs
      }
      -- The auth-dependent data fetches (encounter, compendium,
      -- groups, dice history) all live in
      -- `Update.Auth.meReceived` because each one's destination —
      -- server route vs. public bundle vs. localStorage — depends
      -- on the cookie probe's result.
    , Cmd.batch
        [ Effects.fetchAuthMe
        , Effects.cmdForRoute route
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

        encounterCmd =
            if Effects.shouldPersistAfter msg && next.encounter /= model.encounter then
                Effects.persistEncounterFor next.auth next.encounter

            else
                Cmd.none

        -- Cross-tab broadcast: every encounter mutation that
        -- isn't itself a received broadcast gets posted to the
        -- BroadcastChannel so a quick-list tab (or a second
        -- main tab) picks the change up live.  Same diff guard
        -- as `encounterCmd` — broadcast only when the encounter
        -- actually changed.  The QuickList tab is read-only so
        -- it never triggers this branch anyway.
        encounterBroadcastCmd =
            if Effects.shouldBroadcastAfter msg && next.encounter /= model.encounter then
                Ports.broadcastEncounter (Encounter.Wire.encodeEncounter next.encounter)

            else
                Cmd.none

        diceHistoryCmd =
            if
                Effects.shouldPersistAfter msg
                    && model.dice.history.entries
                    /= next.dice.history.entries
            then
                Effects.persistDiceHistoryFor next

            else
                Cmd.none

        compendiumCmd =
            if Effects.shouldPersistAfter msg && Effects.compendiumChanged model next then
                Effects.persistCompendiumFor next

            else
                Cmd.none

        encounterSavesCmd =
            if Effects.shouldPersistAfter msg && model.localEncounterSaves /= next.localEncounterSaves then
                Effects.persistEncounterSavesFor next

            else
                Cmd.none

        conditionPresetsCmd =
            if Effects.shouldPersistAfter msg && model.conditionPresets /= next.conditionPresets then
                case next.auth of
                    Auth.AuthAuthenticated _ ->
                        Effects.putConditionPresets next.conditionPresets

                    _ ->
                        Ports.persistLocalConditionPresets
                            (Ui.Condition.Wire.encodePresets next.conditionPresets)

            else
                Cmd.none

        saveChainPresetsCmd =
            if Effects.shouldPersistAfter msg && model.saveChainPresets /= next.saveChainPresets then
                case next.auth of
                    Auth.AuthAuthenticated _ ->
                        Effects.putSaveChainPresets next.saveChainPresets

                    _ ->
                        Ports.persistLocalSaveChainPresets
                            (Encounter.SaveChain.Wire.encodePresets next.saveChainPresets)

            else
                Cmd.none

        timerPresetsCmd =
            if Effects.shouldPersistAfter msg && model.timerPresets /= next.timerPresets then
                Ports.persistLocalTimerPresets
                    (Ui.Timer.Wire.encodePresets next.timerPresets)

            else
                Cmd.none

        partyCmd =
            if
                Effects.shouldPersistAfter msg
                    && (model.party /= next.party || model.nextPartyMemberId /= next.nextPartyMemberId)
            then
                Ports.persistLocalParty
                    (Difficulty.encodePartyState next.party next.nextPartyMemberId)

            else
                Cmd.none

        userLoreGroupsCmd =
            if Effects.shouldPersistAfter msg && model.userLoreGroups /= next.userLoreGroups then
                case next.auth of
                    Auth.AuthAuthenticated _ ->
                        Effects.putLoreGroups next.userLoreGroups

                    _ ->
                        Ports.persistLocalUserLoreGroups
                            (Encounter.RandomEncounter.Lore.Wire.encodeGroups next.userLoreGroups)

            else
                Cmd.none

        userTreasureTableCmd =
            if Effects.shouldPersistAfter msg && model.userTreasureTable /= next.userTreasureTable then
                case ( next.auth, next.userTreasureTable ) of
                    ( Auth.AuthAuthenticated _, Just table ) ->
                        Effects.putTreasureTable table

                    ( _, Just table ) ->
                        Ports.persistLocalUserTreasureTable
                            (Encounter.Treasure.TableWire.encodeTable table)

                    ( _, Nothing ) ->
                        Cmd.none

            else
                Cmd.none

        userTreasureProfilesCmd =
            if Effects.shouldPersistAfter msg && model.userTreasureProfiles /= next.userTreasureProfiles then
                case next.auth of
                    Auth.AuthAuthenticated _ ->
                        Effects.putTreasureProfiles
                            (Encounter.Treasure.ProfileWire.encodeProfiles
                                next.userTreasureProfiles
                            )

                    _ ->
                        Cmd.none

            else
                Cmd.none

        -- Surface-open focus management.  When the active modal
        -- transitions from `Nothing` to `Just _` (any modal
        -- opened by any path), fire `View.Modal.focusInitial`
        -- so keyboard / SR users land on the modal close button
        -- the moment the dialog appears.  Lives at the top-level
        -- update wrapper instead of in each modal's open handler
        -- so we don't have to plumb the focus Cmd through ~20
        -- modal Update modules.
        modalFocusCmd =
            if model.surface == Nothing && next.surface /= Nothing then
                View.Modal.focusInitial (\_ -> NoOp)

            else
                Cmd.none

        -- Reset modal chrome (drag offset + resized dimensions)
        -- to defaults on every modal-open transition so each
        -- freshly opened modal starts centered and at its CSS
        -- default size.  Without this, a user who drags or
        -- resizes one modal would inherit that geometry for the
        -- next modal they open.  Three modal-open surfaces are
        -- covered: the unified `model.surface` ADT, plus the Dice
        -- Roller and Compendium Browser which carry their own
        -- `open : Bool` flags outside the ADT.
        anyModalOpen m =
            m.surface /= Nothing || m.dice.open || m.compendium.open

        nextWithChromeReset =
            if not (anyModalOpen model) && anyModalOpen next then
                Update.ModalChrome.reset next

            else
                next
    in
    ( nextWithChromeReset
    , Cmd.batch
        [ innerCmd
        , encounterCmd
        , encounterBroadcastCmd
        , diceHistoryCmd
        , compendiumCmd
        , encounterSavesCmd
        , conditionPresetsCmd
        , saveChainPresetsCmd
        , timerPresetsCmd
        , partyCmd
        , userLoreGroupsCmd
        , userTreasureTableCmd
        , userTreasureProfilesCmd
        , modalFocusCmd
        ]
    )


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

        DeathSavesBegin name ->
            Update.DeathSave.begin name model

        MarkCreatureDead name ->
            Update.DeathSave.markDead name model

        RevertCreatureToDown name ->
            Update.DeathSave.revertToDown name model

        ToggleReadied name ->
            Update.Encounter.toggleReadied name model

        ToggleReaction name ->
            Update.Encounter.toggleReaction name model

        ToggleRechargeAbility creatureName abilityName ->
            Update.Encounter.toggleRechargeAbility creatureName abilityName model

        RollRechargeNow creatureName abilityName ->
            Update.Encounter.rollRechargeNow creatureName abilityName model

        RechargeRollLanded creatureName abilityName roll ->
            Update.Encounter.rechargeRollLanded creatureName abilityName roll model

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

        DiceRerunMenuToggle idx ->
            Update.Dice.rerunMenuToggle idx model

        DiceRerunMenuClose ->
            Update.Dice.rerunMenuClose model

        DiceRerunNoModifier roll ->
            Update.Dice.rerunNoModifier roll model

        DiceClearHistory ->
            Update.Dice.clearHistory model

        DiceRollLanded roll ->
            Update.Dice.rollLanded roll model

        DiceRollFromOtherTab raw ->
            Update.Dice.rollFromOtherTab raw model

        EncounterFromOtherTab raw ->
            Update.Tabs.encounterFromOtherTab raw model

        DiceHistoryLoaded result ->
            Update.Dice.historyLoaded result model

        DicePersistResponse result ->
            Update.Dice.persistResponse result model

        DiceClearResponse result ->
            Update.Dice.clearResponse result model

        LoreGroupsLoaded result ->
            Update.UserSync.loreGroupsLoaded result model

        LoreGroupsPersisted result ->
            Update.UserSync.loreGroupsPersisted result model

        ConditionPresetsLoaded result ->
            Update.UserSync.conditionPresetsLoaded result model

        ConditionPresetsPersisted result ->
            Update.UserSync.conditionPresetsPersisted result model

        SaveChainPresetsLoaded result ->
            Update.UserSync.saveChainPresetsLoaded result model

        SaveChainPresetsPersisted result ->
            Update.UserSync.saveChainPresetsPersisted result model

        RollFromStatBlock creatureName expr x y ->
            Update.Dice.rollFromStatBlock creatureName expr x y model

        StatBlockRollLanded x y roll ->
            Update.Dice.statBlockRollLanded x y roll model

        RollPopupExpired id ->
            Update.Dice.rollPopupExpired id model

        DiceLastTotalFlashCleared ->
            Update.Dice.lastTotalFlashCleared model

        -- HP change modal lifecycle
        HpChangeOpen target ->
            Update.HpChange.open target model

        HpChangeClose ->
            Update.HpChange.close model

        HpChangeAmountChanged text ->
            Update.HpChange.amountChanged text model

        HpChangeIgnoreTempToggle ->
            Update.HpChange.ignoreTempToggle model

        HpChangeApplyToSelectedToggle ->
            Update.HpChange.applyToSelectedToggle model

        HpChangeApplyAs kind ->
            Update.HpChange.applyAs kind model

        HpChangeRollLanded roll ->
            Update.HpChange.rollLanded roll model

        HpChangeFreshRollToggle ->
            Update.HpChange.freshRollToggle model

        HpChangeFreshRollLanded kind ignoreTemp target roll ->
            Update.HpChange.freshRollLanded kind ignoreTemp target roll model

        HpChangeUndoLatest ->
            Update.HpChange.undoLatest model

        -- Save Chain modal
        SaveChainOpen target ->
            Update.SaveChain.open target model

        SaveChainClose ->
            Update.SaveChain.close model

        SaveChainNameChanged text ->
            Update.SaveChain.nameChanged text model

        SaveChainAbilitySet ability ->
            Update.SaveChain.abilitySet ability model

        SaveChainDcChanged text ->
            Update.SaveChain.dcChanged text model

        SaveChainDcOverrideChanged text ->
            Update.SaveChain.dcOverrideChanged text model

        SaveChainApplyToSelectedToggle ->
            Update.SaveChain.applyToSelectedToggle model

        SaveChainOutcomeHpKindSet side kind ->
            Update.SaveChain.outcomeHpKindSet side kind model

        SaveChainOutcomeHpAmountChanged side text ->
            Update.SaveChain.outcomeHpAmountChanged side text model

        SaveChainOutcomeEffectAdd side ->
            Update.SaveChain.outcomeEffectAdd side model

        SaveChainOutcomeEffectRemove side idx ->
            Update.SaveChain.outcomeEffectRemove side idx model

        SaveChainOutcomeEffectNameChanged side idx text ->
            Update.SaveChain.outcomeEffectNameChanged side idx text model

        SaveChainOutcomeEffectNoteChanged side idx text ->
            Update.SaveChain.outcomeEffectNoteChanged side idx text model

        SaveChainOutcomeEffectSaveToEndToggle side idx ->
            Update.SaveChain.outcomeEffectSaveToEndToggle side idx model

        SaveChainOutcomeEffectAutoRollSet side idx mode ->
            Update.SaveChain.outcomeEffectAutoRollSet side idx mode model

        SaveChainPresetPickerChanged text ->
            Update.SaveChain.presetPickerChanged text model

        SaveChainPresetLoad ->
            Update.SaveChain.presetLoad model

        SaveChainPresetSave ->
            Update.SaveChain.presetSave model

        SaveChainPresetDelete ->
            Update.SaveChain.presetDelete model

        SaveChainReset ->
            Update.SaveChain.reset model

        SaveChainRestoreBundled ->
            Update.SaveChain.restoreBundled model

        SaveChainExportBundled ->
            Update.SaveChain.exportBundled model

        SaveChainApplyFail ->
            Update.SaveChain.applyFail model

        SaveChainApplyPass ->
            Update.SaveChain.applyPass model

        SaveChainApplyRollLanded side roll ->
            Update.SaveChain.applyRollLanded side roll model

        SaveChainRollSaves mode ->
            Update.SaveChain.rollSaves mode model

        SaveChainSavesRolled results ->
            Update.SaveChain.savesRolled results model

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

        InitiativeAutoRollSurprised scope ->
            Update.Initiative.autoRollSurprised scope model

        InitiativeApplyTargetSurprised ->
            Update.Initiative.applyTargetSurprised model

        InitiativeApplySelectedSurprised ->
            Update.Initiative.applySelectedSurprised model

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

        ConditionDurationOneMinute ->
            Update.Condition.durationOneMinute model

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

        ConditionPresetSaveStart ->
            Update.Condition.presetSaveStart model

        ConditionPresetSaveNameChanged text ->
            Update.Condition.presetSaveNameChanged text model

        ConditionPresetSaveCategoryChanged category ->
            Update.Condition.presetSaveCategoryChanged category model

        ConditionPresetSaveCancel ->
            Update.Condition.presetSaveCancel model

        ConditionPresetSaveSubmit ->
            Update.Condition.presetSaveSubmit model

        ConditionPresetLoadMenuToggle ->
            Update.Condition.presetLoadMenuToggle model

        ConditionPresetLoadMenuClose ->
            Update.Condition.presetLoadMenuClose model

        ConditionPresetLoad name ->
            Update.Condition.presetLoad name model

        ConditionPresetDelete name ->
            Update.Condition.presetDelete name model

        ConditionPresetCategoryToggle category ->
            Update.Condition.presetCategoryToggle category model

        ConditionRemoveChip name id ->
            Update.Condition.removeChip name id model

        ConditionRollSave name id ->
            Update.Condition.rollSave name id model

        ConditionSaveLanded name id dc wasAutoRoll roll ->
            Update.Condition.saveLanded name id dc wasAutoRoll roll model

        ConditionUndoLatest ->
            Update.Condition.undoLatest model

        SaveNoticeDismiss name id ->
            Update.Condition.saveNoticeDismiss name id model

        ActiveCardScrollChecked _ ->
            -- Result of the scroll-into-view Task. Either the scroll
            -- worked or the element wasn't found (defensive); either
            -- way, nothing further to do.
            ( model, Cmd.none )

        ScrollCardIntoView name ->
            ( model, Effects.scrollActiveIntoView name )

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

        TimerPresetSaveStart ->
            Update.Timer.presetSaveStart model

        TimerPresetSaveNameChanged text ->
            Update.Timer.presetSaveNameChanged text model

        TimerPresetSaveCancel ->
            Update.Timer.presetSaveCancel model

        TimerPresetSaveSubmit ->
            Update.Timer.presetSaveSubmit model

        TimerPresetLoadMenuToggle ->
            Update.Timer.presetLoadMenuToggle model

        TimerPresetLoadMenuClose ->
            Update.Timer.presetLoadMenuClose model

        TimerPresetLoad name ->
            Update.Timer.presetLoad name model

        TimerPresetDelete name ->
            Update.Timer.presetDelete name model

        CompendiumLoaded result ->
            Update.Compendium.Browser.loaded result model

        CompendiumOpen ->
            -- If the standalone /compendium tab is open, focus
            -- it; otherwise JS calls back via
            -- `compendiumTabMissing` and the modal opens.
            ( model, Ports.tryFocusCompendiumTab () )

        CompendiumTabMissing ->
            Update.Compendium.Browser.open model

        CompendiumOpenInTab ->
            Update.Compendium.Browser.openInTab model

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

        CompendiumAddSelectedToQueue ->
            Update.Compendium.Add.addSelectedToQueue model

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

        CompendiumLoreSectionToggle ->
            Update.Compendium.Lore.sectionToggle model

        CompendiumLoreExpandToggle id ->
            Update.Compendium.Lore.expandToggle id model

        CompendiumLoreSelect id ->
            Update.Compendium.Lore.select id model

        CompendiumLoreDelete id ->
            Update.Compendium.Lore.delete id model

        CompendiumLoreAdd id ->
            Update.Compendium.Lore.add id model

        CompendiumLoreAddMaterialise groupName pairs ->
            Update.Compendium.Lore.addMaterialise groupName pairs model

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

        GroupEditLoreUserExpandToggle ->
            Update.Compendium.Group.loreUserExpandToggle model

        GroupEditLoreBundledExpandToggle ->
            Update.Compendium.Group.loreBundledExpandToggle model

        GroupEditLoreGroupExpandToggle id ->
            Update.Compendium.Group.loreGroupExpandToggle id model

        GroupEditLoreNew ->
            Update.Compendium.Group.loreNew model

        GroupEditLoreEdit id ->
            Update.Compendium.Group.loreEdit id model

        GroupEditLoreDeleteRequest id ->
            Update.Compendium.Group.loreDeleteRequest id model

        GroupEditLoreDeleteConfirm ->
            Update.Compendium.Group.loreDeleteConfirm model

        GroupEditLoreDeleteCancel ->
            Update.Compendium.Group.loreDeleteCancel model

        GroupEditLoreDraftCancel ->
            Update.Compendium.Group.loreDraftCancel model

        GroupEditLoreDraftSubmit ->
            Update.Compendium.Group.loreDraftSubmit model

        GroupEditLoreDraftTest ->
            Update.Compendium.Group.loreDraftTest model

        LoreEditOpenNew ->
            Update.LoreEdit.openNew model

        LoreEditOpenExisting groupId ->
            Update.LoreEdit.openExisting groupId model

        LoreEditClose ->
            Update.LoreEdit.close model

        LoreEditSave ->
            Update.LoreEdit.save model

        LoreEditNameChanged raw ->
            Update.LoreEdit.nameChanged raw model

        LoreEditDescriptionChanged raw ->
            Update.LoreEdit.descriptionChanged raw model

        LoreEditWeightChanged raw ->
            Update.LoreEdit.weightChanged raw model

        LoreEditAddSearchChanged raw ->
            Update.LoreEdit.addSearchChanged raw model

        LoreEditMemberAdd creatureName ->
            Update.LoreEdit.memberAdd creatureName model

        LoreEditMemberRemove idx ->
            Update.LoreEdit.memberRemove idx model

        LoreEditMemberRoleSet idx role ->
            Update.LoreEdit.memberRoleSet idx role model

        LoreEditMemberCountMinChanged idx raw ->
            Update.LoreEdit.memberCountMinChanged idx raw model

        LoreEditMemberCountMaxChanged idx raw ->
            Update.LoreEdit.memberCountMaxChanged idx raw model

        LoreEditTest ->
            Update.LoreEdit.test model

        GroupEditLoreDraftNameChanged raw ->
            Update.Compendium.Group.loreDraftNameChanged raw model

        GroupEditLoreDraftWeightChanged raw ->
            Update.Compendium.Group.loreDraftWeightChanged raw model

        GroupEditLoreDraftMemberAdd cname ->
            Update.Compendium.Group.loreDraftMemberAdd cname model

        GroupEditLoreDraftMemberRemove idx ->
            Update.Compendium.Group.loreDraftMemberRemove idx model

        GroupEditLoreDraftMemberRoleSet idx raw ->
            Update.Compendium.Group.loreDraftMemberRoleSet idx raw model

        GroupEditLoreDraftMemberCountMinChanged idx raw ->
            Update.Compendium.Group.loreDraftMemberCountMinChanged idx raw model

        GroupEditLoreDraftMemberCountMaxChanged idx raw ->
            Update.Compendium.Group.loreDraftMemberCountMaxChanged idx raw model

        GroupEditLoreAddSearchChanged raw ->
            Update.Compendium.Group.loreAddSearchChanged raw model

        CompendiumGroupsLoaded result ->
            Update.Compendium.Group.groupsLoaded result model

        CompendiumGroupCreated result ->
            Update.Compendium.Group.created result model

        CompendiumGroupUpdated result ->
            Update.Compendium.Group.updated result model

        CompendiumGroupDeleted groupId result ->
            Update.Compendium.Group.deleteResponse groupId result model

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

        RandomEncounterOpen ->
            Update.RandomEncounter.open model

        RandomEncounterClose ->
            Update.RandomEncounter.close model

        RandomEncounterDifficultySet raw ->
            Update.RandomEncounter.difficultySet raw model

        RandomEncounterScaleSet raw ->
            Update.RandomEncounter.scaleSet raw model

        RandomEncounterHabitatSet raw ->
            Update.RandomEncounter.habitatSet raw model

        RandomEncounterCreatureTypeAt index raw ->
            Update.RandomEncounter.creatureTypeAt index raw model

        RandomEncounterMinionsToggle ->
            Update.RandomEncounter.minionsToggle model

        RandomEncounterLoreToggle ->
            Update.RandomEncounter.loreToggle model

        RandomEncounterPinPickerToggle ->
            Update.RandomEncounter.pinPickerToggle model

        RandomEncounterPinSearchChanged raw ->
            Update.RandomEncounter.pinSearchChanged raw model

        RandomEncounterPinAdd id ->
            Update.RandomEncounter.pinAdd id model

        RandomEncounterPinDecrement id ->
            Update.RandomEncounter.pinDecrement id model

        RandomEncounterPinRemove id ->
            Update.RandomEncounter.pinRemove id model

        RandomEncounterExcludePickerToggle ->
            Update.RandomEncounter.excludePickerToggle model

        RandomEncounterExcludeSearchChanged raw ->
            Update.RandomEncounter.excludeSearchChanged raw model

        RandomEncounterExcludeAdd id ->
            Update.RandomEncounter.excludeAdd id model

        RandomEncounterExcludeRemove id ->
            Update.RandomEncounter.excludeRemove id model

        RandomEncounterGenerate ->
            Update.RandomEncounter.generate model

        RandomEncounterRolled groups minionIds ->
            Update.RandomEncounter.rolled groups minionIds model

        RandomEncounterAddToEncounter ->
            Update.RandomEncounter.addToEncounter model

        TreasureOpen ->
            Update.Treasure.open model

        TreasureClose ->
            Update.Treasure.close model

        SpellListOpen ->
            Update.SpellList.open model

        SpellListClose ->
            Update.SpellList.close model

        TreasureKindSet raw ->
            Update.Treasure.kindSet raw model

        TreasureRoll ->
            Update.Treasure.roll model

        TreasureRolled treasureRoll ->
            Update.Treasure.rolled treasureRoll model

        TreasureRerollCategory category ->
            Update.Treasure.rerollCategory category model

        TreasureCategoryRolled category fresh ->
            Update.Treasure.categoryRolled category fresh model

        TreasureContributionsToggle ->
            Update.Treasure.contributionsToggle model

        TreasureSettingsToggle ->
            Update.Treasure.settingsToggle model

        TreasureSettingsCountSet itemClass value ->
            Update.Treasure.settingsCountSet itemClass value model

        TreasureSettingsValueSet itemClass value ->
            Update.Treasure.settingsValueSet itemClass value model

        TreasureSettingsNoneSet kind itemClass none ->
            Update.Treasure.settingsNoneSet kind itemClass none model

        TreasureSettingsScrollChanceSet raw ->
            Update.Treasure.settingsScrollChanceSet raw model

        TreasureSettingsPresetApply preset ->
            Update.Treasure.settingsPresetApply preset model

        TreasureSettingsReset ->
            Update.Treasure.settingsReset model

        TreasureCoinRemove denomination ->
            Update.Treasure.coinRemove denomination model

        TreasureGemRemove idx ->
            Update.Treasure.gemRemove idx model

        TreasureArtRemove idx ->
            Update.Treasure.artRemove idx model

        TreasureMagicRemove idx ->
            Update.Treasure.magicRemove idx model

        TreasureMundaneRemove idx ->
            Update.Treasure.mundaneRemove idx model

        TreasureWeaponsRemove idx ->
            Update.Treasure.weaponsRemove idx model

        TreasureArmorRemove idx ->
            Update.Treasure.armorRemove idx model

        TreasureTableLoaded result ->
            Update.UserSync.treasureTableLoaded result model

        TreasureTablePersisted result ->
            Update.UserSync.treasureTablePersisted result model

        TreasureProfilesLoaded result ->
            Update.UserSync.treasureProfilesLoaded result model

        TreasureProfilesPersisted result ->
            Update.UserSync.treasureProfilesPersisted result model

        TreasureProfileNameChanged raw ->
            Update.Treasure.profileNameChanged raw model

        TreasureProfileSave ->
            Update.Treasure.profileSave model

        TreasureProfileLoad name ->
            Update.Treasure.profileLoad name model

        TreasureProfileDelete name ->
            Update.Treasure.profileDelete name model

        TreasureTableOpen ->
            Update.TreasureTable.open model

        TreasureTableClose ->
            Update.TreasureTable.close model

        TreasureTableToggleSection kind key ->
            Update.TreasureTable.toggleSection kind key model

        TreasureTableGemAdd key ->
            Update.TreasureTable.gemAdd key model

        TreasureTableGemEdit key idx value ->
            Update.TreasureTable.gemEdit key idx value model

        TreasureTableGemRemoveItem key idx ->
            Update.TreasureTable.gemRemove key idx model

        TreasureTableArtAdd key ->
            Update.TreasureTable.artAdd key model

        TreasureTableArtEdit key idx value ->
            Update.TreasureTable.artEdit key idx value model

        TreasureTableArtRemoveItem key idx ->
            Update.TreasureTable.artRemove key idx model

        TreasureTableMagicAdd key ->
            Update.TreasureTable.magicAdd key model

        TreasureTableMagicEdit key idx value ->
            Update.TreasureTable.magicEdit key idx value model

        TreasureTableMagicRemoveItem key idx ->
            Update.TreasureTable.magicRemove key idx model

        TreasureTableRowAdd kind key ->
            Update.TreasureTable.rowAdd kind key model

        TreasureTableRowRemove kind key idx ->
            Update.TreasureTable.rowRemove kind key idx model

        TreasureTableWeightSet kind key idx raw ->
            Update.TreasureTable.weightSet kind key idx raw model

        TreasureTableCoinAdd kind key idx coin ->
            Update.TreasureTable.coinAdd kind key idx coin model

        TreasureTableCoinRemove kind key idx coin ->
            Update.TreasureTable.coinRemove kind key idx coin model

        TreasureTableCoinSet kind key idx coin field raw ->
            Update.TreasureTable.coinSet kind key idx coin field raw model

        TreasureTableSubAdd key idx sub ->
            Update.TreasureTable.subAdd key idx sub model

        TreasureTableSubRemove key idx sub ->
            Update.TreasureTable.subRemove key idx sub model

        TreasureTableSubCountSet key idx sub raw ->
            Update.TreasureTable.subCountSet key idx sub raw model

        TreasureTableSubFacesSet key idx sub raw ->
            Update.TreasureTable.subFacesSet key idx sub raw model

        TreasureTableSubTierSet key idx sub raw ->
            Update.TreasureTable.subTierSet key idx sub raw model

        TreasureTableFlatAdd cat ->
            Update.TreasureTable.flatAdd cat model

        TreasureTableFlatNameSet cat idx raw ->
            Update.TreasureTable.flatNameSet cat idx raw model

        TreasureTableFlatValueSet cat idx raw ->
            Update.TreasureTable.flatValueSet cat idx raw model

        TreasureTableFlatRemove cat idx ->
            Update.TreasureTable.flatRemove cat idx model

        TreasureTableScrollAdd levelKey ->
            Update.TreasureTable.scrollAdd levelKey model

        TreasureTableScrollEdit levelKey idx raw ->
            Update.TreasureTable.scrollEdit levelKey idx raw model

        TreasureTableScrollRemove levelKey idx ->
            Update.TreasureTable.scrollRemove levelKey idx model

        TreasureTableSave ->
            Update.TreasureTable.save model

        TreasureTableResetToBundled ->
            Update.TreasureTable.resetToBundled model

        TreasureTableRevertRequest ->
            Update.TreasureTable.revertRequest model

        TreasureTableRevertCancel ->
            Update.TreasureTable.revertCancel model

        TreasureTableRevertConfirm ->
            Update.TreasureTable.revertConfirm model

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

        CompendiumEditLootAdd ->
            Update.Compendium.Edit.lootAdd model

        CompendiumEditLootRemove idx ->
            Update.Compendium.Edit.lootRemove idx model

        CompendiumEditLootChanged idx text ->
            Update.Compendium.Edit.lootChanged idx text model

        CompendiumEditSpecialReactionsToggle ->
            Update.Compendium.Edit.specialReactionsToggle model

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

        QuickListRowClick creatureId creatureName ->
            -- Fires from the QuickList tab.  Broadcast the
            -- (id, name) so the main tab pins the stat block +
            -- scrolls its card into view, and let the JS side
            -- of the port also try `window.opener.focus()` so
            -- the main tab comes to front.  This tab itself
            -- doesn't need to update — the GM is done with it.
            ( model
            , Ports.broadcastPanelShow
                (Encode.object
                    [ ( "id", Encode.string creatureId )
                    , ( "name", Encode.string creatureName )
                    ]
                )
            )

        IncomingPanelShow creatureId creatureName ->
            Update.Tabs.incomingPanelShow creatureId creatureName model

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

        LoadSourceSet source ->
            Update.Load.sourceSet source model

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

        LoadCompendiumSourceSet source ->
            Update.LoadCompendium.sourceSet source model

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

        EncounterAddPlaceholder ->
            Update.Encounter.addPlaceholder model

        PlaceholderRenameOpen name ->
            Update.PlaceholderRename.open name model

        PlaceholderRenameChange text ->
            Update.PlaceholderRename.change text model

        PlaceholderRenameCommit ->
            Update.PlaceholderRename.commit model

        PlaceholderRenameCancel ->
            Update.PlaceholderRename.cancel model

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

        QuickAddOpenForReplace oldName ->
            Update.QuickAdd.openForReplace oldName model

        QuickAddClose ->
            Update.QuickAdd.close model

        QuickAddSortToggle ->
            Update.QuickAdd.sortToggle model

        QuickAddSearchChanged text ->
            Update.QuickAdd.searchChanged text model

        QuickAddPick id ->
            Update.QuickAdd.pick id model

        QuickAddPickPlaceholder ->
            Update.QuickAdd.pickPlaceholder model

        AbilityCheckOpen creatureName ability bonus x y ->
            Update.AbilitySave.open Ui.AbilitySave.AbilityCheck creatureName ability bonus x y model

        AbilitySaveOpen creatureName ability bonus x y ->
            Update.AbilitySave.open Ui.AbilitySave.SavingThrow creatureName ability bonus x y model

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

        AnonymousBannerDismiss ->
            Update.Shell.anonymousBannerDismiss model

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

        LoginCancel ->
            ( model, Nav.pushUrl model.key "/" )

        LocalEncounterMigrated name result ->
            Update.Auth.localEncounterMigrated name result model

        LocalCompendiumMigrated count result ->
            Update.Auth.localCompendiumMigrated count result model

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

        ModalChromeDragStart x y ->
            Update.ModalChrome.dragStart x y model

        ModalChromeDragMove x y ->
            Update.ModalChrome.dragMove x y model

        ModalChromeDragEnd ->
            Update.ModalChrome.dragEnd model

        ModalChromeResizeStart edge x y w h ->
            Update.ModalChrome.resizeStart edge x y w h model

        ModalChromeResizeMove x y ->
            Update.ModalChrome.resizeMove x y model

        ModalChromeResizeEnd ->
            Update.ModalChrome.resizeEnd model

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

        QuickList ->
            -- Standalone quick-view tab (opened via ↗ from the
            -- encounter title bar).  Distinct title so a GM
            -- parking multiple tabs (main workspace + several
            -- stat-block tabs) can pick this one out at a
            -- glance without reading the URL.
            "eZpZ Quick View"

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
                    [ View.Page.Loading.view ]

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
    [ -- AppBar is suppressed on the standalone Quick-List
      -- and Compendium pages — those tabs are meant to be
      -- parked on a second monitor, where the nav row would
      -- only compete for vertical space with the page body.
      if model.route == QuickList || model.route == Compendium then
        text ""

      else
        View.AppBar.view
            { settingsOpen = model.settingsOpen
            , theme = model.preferences.theme
            , user = maybeUser
            , route = model.route
            }
    , -- Suppressed on the second-monitor tabs for the same reason
      -- the AppBar is — the banner is a navigation-adjacent
      -- affordance that doesn't belong on a parked reference view.
      if model.route == QuickList || model.route == Compendium then
        text ""

      else
        View.AnonymousBanner.view
            { auth = model.auth
            , dismissed = model.anonymousBannerDismissed
            }
    , viewPage model
    , View.Modal.Dice.view model.modalChrome model.hpChangeLog model.dice
    , View.Modal.Initiative.view model
    , View.Modal.Compendium.view model.modalChrome
        model.auth
        model.compendium
        model.userLoreGroups
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
    , View.Modal.LoreEdit.view model
    , View.Modal.CrCalculator.view model
    , View.Modal.RandomEncounter.view model
    , View.Modal.Treasure.view model.modalChrome model
    , View.Modal.TreasureTable.view model
    , View.Modal.SpellList.view model
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
            View.Page.Donate.view

        About ->
            View.About.view

        CompendiumCreaturePage id ->
            View.Page.CompendiumStandalone.view model.compendium.db id

        QuickList ->
            View.Page.QuickList.view model.encounter model.savedAs model.compendium.db

        Compendium ->
            View.Page.Compendium.view model.auth
                model.compendium
                model.userLoreGroups
                (List.filterMap .creatureId model.encounter.creatures)

        NotFound ->
            View.Page.NotFound.view
