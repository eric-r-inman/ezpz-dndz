module Model exposing
    ( Surface(..), Model
    , DrawerPanel, PanelPin, PendingControl(..), RollPopup, SurfaceLens, closeDrawer, compendiumEditLens, conditionLens, crCalculatorLens, diceLens, drawerGet, drawerHas, drawerIndexOf, duplicateLens, groupEditLens, hpChangeLens, initiativeLens, loadCompendiumLens, loadLens, loreEditLens, mapDrawer, mapSurface, memoLens, noteLens, openDrawer, quickAddLens, randomEncounterLens, replaceLens, roundSetLens, saveChainLens, saveCompendiumLens, saveLens, statBlockLens, statusLens, timerLens, toggleCollapsedAt, toggleDrawer, treasureLens, treasureTableLens, xpLens
    )

{-| The single source of truth for the running app.

`encounter` holds all D&D-specific state (queue, active
creature, round). Everything else is presentation, auth, or
modal-state plumbing. The discipline mirrors the larger
layering rule: domain state goes through `Encounter`,
everything else stays here.

The `surface` field is a `Maybe Surface` ADT — the constructor
identifies which modal is open and carries its UI state.
`Nothing` means no modal is open. This shape replaces the
older "one `Maybe XxxUi` field per modal" scheme and bakes
the "only one modal open at a time" invariant into the type
system rather than leaving it as a convention.

The exceptions — `dice` and `compendium` — sit outside the
ADT because their substate has to survive a close (dice
history, compendium cache + filter selection). The dice
substate carries its own `open : Bool`; the compendium browser
renders as the standalone /compendium tab, so it has no open
flag at all. The `*Draft` fields are the same exception
in another form: they hold the settings of editors that are
CLOSED, which by definition cannot live inside the ADT that
models what is open.

`savedSnapshot` is the last-known persisted state of the
encounter — the result of the user's most recent Save (or
Load) action. It backs the Save button's dirty indicator,
which lights when the live roster differs from it. `savedAs`
parallels it, recording the name the encounter was last saved
under so re-saving doesn't make the user retype the filename.

@docs Surface, Model

-}

import Auth exposing (AuthState)
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Encounter exposing (Encounter)
import Encounter.Difficulty as Difficulty
import Encounter.RandomEncounter.Lore as Lore
import Encounter.SaveChain exposing (SaveChain)
import Encounter.Treasure
import Encounter.Wire as EncounterWire
import Encounter.Xp exposing (XpScope)
import Json.Decode as Decode
import Msg exposing (MeStatus)
import Preferences exposing (Preferences)
import Route exposing (Route)
import Ui.AbilitySave exposing (AbilitySaveUi)
import Ui.Account exposing (AccountUi)
import Ui.ActionGroups exposing (ActionGroups)
import Ui.Compendium exposing (CompendiumEditUi, CompendiumPasteUi, CompendiumUi)
import Ui.Condition as UiCondition exposing (ConditionUi)
import Ui.CrCalculator exposing (CrCalculatorUi)
import Ui.Dice exposing (DiceUi)
import Ui.Duplicate exposing (DuplicateUi)
import Ui.GroupEdit exposing (GroupEditUi)
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi, HpEdit)
import Ui.Initiative exposing (InitiativeUi)
import Ui.Load exposing (LoadUi)
import Ui.LoadCompendium exposing (LoadCompendiumUi)
import Ui.Login exposing (LoginUi)
import Ui.LoreEdit exposing (LoreEditUi)
import Ui.Memo exposing (MemoEditUi)
import Ui.ModalChrome exposing (ModalChrome)
import Ui.Note exposing (NoteEditUi)
import Ui.PlaceholderRename exposing (PlaceholderRenameState)
import Ui.QueuePanels exposing (QueuePanels)
import Ui.QuickAdd exposing (QuickAddUi)
import Ui.RandomEncounter exposing (RandomEncounterUi)
import Ui.Replace exposing (ReplaceUi)
import Ui.RoundSet exposing (RoundSetUi)
import Ui.Save exposing (SaveUi)
import Ui.SaveChain exposing (SaveChainUi)
import Ui.SaveCompendium exposing (SaveCompendiumUi)
import Ui.Status exposing (StatusUi)
import Ui.Timer as UiTimer exposing (TimerSetupUi)
import Ui.Toast exposing (Toast)
import Ui.Treasure exposing (TreasureUi)
import Ui.TreasureTable exposing (TreasureTableUi)
import Url exposing (Url)


{-| The creature pinned in the drawer's stat-block panel
(`SurfaceStatBlock`). Carries
both the compendium `id` (for the canonical UUID lookup) and
the encounter creature's display `name` (so we can fall back to
a name match when an old saved encounter's `creatureId` no
longer matches anything in the current bundled compendium —
otherwise the panel would silently revert to the placeholder
mock).
-}
type alias PanelPin =
    { id : String
    , name : String
    }


{-| Which destructive action the confirmation modal
(`SurfaceConfirm`) is staging, so a mis-click on Reset or Clear
can't drop combat state. Cleared by the user picking Confirm or
Cancel.
-}
type PendingControl
    = PendingReset
    | PendingClear


{-| One constructor per surface, each carrying its UI state.

A surface lives in one of two homes. Modal and card-inline
variants occupy `model.surface`, where "only one open at a
time" is type-enforced: opening surface X assigns
`Just (SurfaceX uiX)`, which by construction wipes out whatever
was open before. Drawer variants live in the `model.drawer`
stack instead, where coexisting is the point.

-}
type Surface
    = SurfaceHpChange HpChangeUi
    | SurfaceInitiative InitiativeUi
    | SurfaceNoteEdit NoteEditUi
    | SurfaceCondition ConditionUi
    | SurfaceMemoEdit MemoEditUi
    | SurfaceTimerSetup TimerSetupUi
    | SurfaceCompendiumEdit CompendiumEditUi
    | SurfaceCompendiumPaste CompendiumPasteUi
    | SurfaceSave SaveUi
    | SurfaceLoad LoadUi
    | SurfaceSaveCompendium SaveCompendiumUi
    | SurfaceLoadCompendium LoadCompendiumUi
    | SurfaceAbilitySave AbilitySaveUi
    | SurfaceQuickAdd QuickAddUi
    | SurfaceDuplicate DuplicateUi
    | SurfaceReplace ReplaceUi
    | SurfaceStatus StatusUi
    | SurfaceGroupEdit GroupEditUi
    | SurfaceLoreEdit LoreEditUi
    | SurfaceCrCalculator CrCalculatorUi
    | SurfaceRandomEncounter RandomEncounterUi
    | SurfaceTreasure TreasureUi
    | SurfaceTreasureTable TreasureTableUi
      -- Save Chain editor: reusable "creature makes a save;
      -- something happens" recipe.  Opened from each card's
      -- Save Chain button; loads / edits / saves named presets
      -- from `model.saveChainPresets` and applies fail/success
      -- outcomes to the target (or the selection).
    | SurfaceSaveChain SaveChainUi
      -- The dice roller.  A marker: the roller's substate has to
      -- outlive a close (history, unread flag), so it stays on
      -- `model.dice` and this variant only records openness and
      -- stack position.
    | SurfaceDice
      -- The XP-scope picker.  Also a marker — the scope itself
      -- is read by the column's trigger whether or not the
      -- panel is open, so it lives on `model.xpScope`.
    | SurfaceXp
      -- The pinned creature's stat block.
    | SurfaceStatBlock PanelPin
      -- The Reset / Clear confirmation.  A modal, not a drawer
      -- panel.
    | SurfaceConfirm PendingControl
      -- Round-setter: correct the round counter directly.
    | SurfaceRoundSet RoundSetUi


{-| One panel in the drawer stack. `collapsed` rides the panel
rather than a separate keyed set, so folding state can't outlive
the panel it describes.
-}
type alias DrawerPanel =
    { surface : Surface
    , collapsed : Bool
    }


{-| Where the panel matching `lens` sits in the stack, if it is
open. Position is the drawer's own identifier for a panel, so
this is what addresses one for scrolling.
-}
drawerIndexOf : SurfaceLens a -> Model -> Maybe Int
drawerIndexOf lens model =
    model.drawer
        |> List.indexedMap
            (\i panel -> Maybe.map (\_ -> i) (lens.extract panel.surface))
        |> List.filterMap identity
        |> List.head


{-| The open drawer panel matching `lens`, if any.
-}
drawerGet : SurfaceLens a -> Model -> Maybe a
drawerGet lens model =
    model.drawer
        |> List.filterMap (.surface >> lens.extract)
        |> List.head


drawerHas : SurfaceLens a -> Model -> Bool
drawerHas lens model =
    drawerGet lens model /= Nothing


{-| Apply `fn` to the matching drawer panel's substate, leaving
its stack position alone. No-op when that panel isn't open.
-}
mapDrawer : SurfaceLens a -> (a -> a) -> Model -> Model
mapDrawer lens fn model =
    { model
        | drawer =
            List.map
                (\panel ->
                    lens.extract panel.surface
                        |> Maybe.map
                            (\ui -> { panel | surface = lens.wrap (fn ui) })
                        |> Maybe.withDefault panel
                )
                model.drawer
    }


{-| Open a drawer panel with the given substate. A panel already
open keeps its stack position and takes the new substate (the
re-aim case); otherwise the panel joins the bottom of the stack.
-}
openDrawer : SurfaceLens a -> a -> Model -> Model
openDrawer lens ui model =
    if drawerHas lens model then
        mapDrawer lens (\_ -> ui) model

    else
        { model
            | drawer =
                model.drawer ++ [ { surface = lens.wrap ui, collapsed = False } ]
        }


closeDrawer : SurfaceLens a -> Model -> Model
closeDrawer lens model =
    { model
        | drawer =
            List.filter
                (\panel -> lens.extract panel.surface == Nothing)
                model.drawer
    }


{-| Fold the panel at `index` away, or unfold it. The index is
the panel's position in the rendered stack, which is what the
click that produced it was aimed at.
-}
toggleCollapsedAt : Int -> Model -> Model
toggleCollapsedAt index model =
    { model
        | drawer =
            List.indexedMap
                (\i panel ->
                    if i == index then
                        { panel | collapsed = not panel.collapsed }

                    else
                        panel
                )
                model.drawer
    }


{-| The column-trigger gesture: close the panel if it is open,
open it with the given substate if not.
-}
toggleDrawer : SurfaceLens a -> a -> Model -> Model
toggleDrawer lens ui model =
    if drawerHas lens model then
        closeDrawer lens model

    else
        openDrawer lens ui model


{-| Pair of `extract` / `wrap` functions identifying one variant
of the `Surface` ADT. Lets `mapSurface` be a single generic helper
shared by every Update module instead of each rolling its own
`withFooUi`. See `mapSurface` and the per-variant `*Lens` values.
-}
type alias SurfaceLens a =
    { extract : Surface -> Maybe a
    , wrap : a -> Surface
    }


{-| Apply `fn` to the matching surface's substate wherever it
lives — the `model.surface` slot or the drawer stack. No-op when
neither holds it.

Replaces the per-Update-module `with*Ui` helpers.

-}
mapSurface : SurfaceLens a -> (a -> a) -> Model -> Model
mapSurface lens fn model =
    case Maybe.andThen lens.extract model.surface of
        Just ui ->
            { model | surface = Just (lens.wrap (fn ui)) }

        Nothing ->
            mapDrawer lens fn model


compendiumEditLens : SurfaceLens CompendiumEditUi
compendiumEditLens =
    { extract =
        \m ->
            case m of
                SurfaceCompendiumEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceCompendiumEdit
    }


roundSetLens : SurfaceLens RoundSetUi
roundSetLens =
    { extract =
        \m ->
            case m of
                SurfaceRoundSet ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceRoundSet
    }


statusLens : SurfaceLens StatusUi
statusLens =
    { extract =
        \m ->
            case m of
                SurfaceStatus ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceStatus
    }


saveChainLens : SurfaceLens SaveChainUi
saveChainLens =
    { extract =
        \m ->
            case m of
                SurfaceSaveChain ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceSaveChain
    }


replaceLens : SurfaceLens ReplaceUi
replaceLens =
    { extract =
        \m ->
            case m of
                SurfaceReplace ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceReplace
    }


diceLens : SurfaceLens ()
diceLens =
    { extract =
        \m ->
            case m of
                SurfaceDice ->
                    Just ()

                _ ->
                    Nothing
    , wrap = \() -> SurfaceDice
    }


xpLens : SurfaceLens ()
xpLens =
    { extract =
        \m ->
            case m of
                SurfaceXp ->
                    Just ()

                _ ->
                    Nothing
    , wrap = \() -> SurfaceXp
    }


statBlockLens : SurfaceLens PanelPin
statBlockLens =
    { extract =
        \m ->
            case m of
                SurfaceStatBlock pin ->
                    Just pin

                _ ->
                    Nothing
    , wrap = SurfaceStatBlock
    }


duplicateLens : SurfaceLens DuplicateUi
duplicateLens =
    { extract =
        \m ->
            case m of
                SurfaceDuplicate ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceDuplicate
    }


groupEditLens : SurfaceLens GroupEditUi
groupEditLens =
    { extract =
        \m ->
            case m of
                SurfaceGroupEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceGroupEdit
    }


loreEditLens : SurfaceLens LoreEditUi
loreEditLens =
    { extract =
        \m ->
            case m of
                SurfaceLoreEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceLoreEdit
    }


crCalculatorLens : SurfaceLens CrCalculatorUi
crCalculatorLens =
    { extract =
        \m ->
            case m of
                SurfaceCrCalculator ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceCrCalculator
    }


randomEncounterLens : SurfaceLens RandomEncounterUi
randomEncounterLens =
    { extract =
        \m ->
            case m of
                SurfaceRandomEncounter ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceRandomEncounter
    }


treasureLens : SurfaceLens TreasureUi
treasureLens =
    { extract =
        \m ->
            case m of
                SurfaceTreasure ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceTreasure
    }


treasureTableLens : SurfaceLens TreasureTableUi
treasureTableLens =
    { extract =
        \m ->
            case m of
                SurfaceTreasureTable ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceTreasureTable
    }


conditionLens : SurfaceLens ConditionUi
conditionLens =
    { extract =
        \m ->
            case m of
                SurfaceCondition ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceCondition
    }


hpChangeLens : SurfaceLens HpChangeUi
hpChangeLens =
    { extract =
        \m ->
            case m of
                SurfaceHpChange ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceHpChange
    }


initiativeLens : SurfaceLens InitiativeUi
initiativeLens =
    { extract =
        \m ->
            case m of
                SurfaceInitiative ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceInitiative
    }


loadLens : SurfaceLens LoadUi
loadLens =
    { extract =
        \m ->
            case m of
                SurfaceLoad ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceLoad
    }


memoLens : SurfaceLens MemoEditUi
memoLens =
    { extract =
        \m ->
            case m of
                SurfaceMemoEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceMemoEdit
    }


noteLens : SurfaceLens NoteEditUi
noteLens =
    { extract =
        \m ->
            case m of
                SurfaceNoteEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceNoteEdit
    }


quickAddLens : SurfaceLens QuickAddUi
quickAddLens =
    { extract =
        \m ->
            case m of
                SurfaceQuickAdd ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceQuickAdd
    }


saveLens : SurfaceLens SaveUi
saveLens =
    { extract =
        \m ->
            case m of
                SurfaceSave ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceSave
    }


timerLens : SurfaceLens TimerSetupUi
timerLens =
    { extract =
        \m ->
            case m of
                SurfaceTimerSetup ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceTimerSetup
    }


saveCompendiumLens : SurfaceLens SaveCompendiumUi
saveCompendiumLens =
    { extract =
        \m ->
            case m of
                SurfaceSaveCompendium ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceSaveCompendium
    }


loadCompendiumLens : SurfaceLens LoadCompendiumUi
loadCompendiumLens =
    { extract =
        \m ->
            case m of
                SurfaceLoadCompendium ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceLoadCompendium
    }


type alias Model =
    { key : Nav.Key
    , url : Url
    , route : Route
    , me : MeStatus
    , auth : AuthState
    , loginUi : LoginUi
    , encounter : Encounter
    , savedSnapshot : Maybe Encounter
    , savedAs : Maybe String
    , dice : DiceUi
    , hpChangeLog : List HpChangeEntry

    -- Twin of `hpChangeLog` for the Save Chain modal.  The
    -- three apply paths (Fail button, Pass button, 🎲 Roll
    -- saves button) each prepend one entry per target so the
    -- GM can scan back a few rounds of resolutions without
    -- flipping between modals.  Capped at
    -- `Ui.SaveChain.maxSaveChainLogEntries`.
    , saveChainLog : List Ui.SaveChain.SaveChainLogEntry
    , hpEdit : Maybe HpEdit
    , compendium : CompendiumUi
    , surface : Maybe Surface

    -- Remembered editor settings, restored on the next open of
    -- the matching surface.  Stashed when an editor closes with
    -- un-applied settings; cleared when it closes after applying
    -- (see each Update module's close).
    , hpChangeDraft : Maybe HpChangeUi
    , conditionDraft : Maybe ConditionUi
    , saveChainDraft : Maybe SaveChainUi

    -- Recent condition applications, newest first — the
    -- condition editor's counterpart to `hpChangeLog`, carrying
    -- the created condition ids so undo can remove exactly the
    -- instances one application added.
    , conditionLog : List UiCondition.ConditionLogEntry

    -- Same pattern for the Duplicate and Replace editors:
    -- newest first, capped in their Update modules.
    , duplicateLog : List Ui.Duplicate.DuplicateLogEntry
    , replaceLog : List Ui.Replace.ReplaceLogEntry
    , modalChrome : ModalChrome
    , placeholderRename : Maybe PlaceholderRenameState
    , xpScope : XpScope
    , settingsOpen : Bool

    -- The Actions column's drawer: every open panel, oldest
    -- first, rendered top to bottom.  A stack rather than a
    -- single slot — drawer panels deliberately coexist, so the
    -- one-at-a-time invariant `surface` enforces stops at the
    -- drawer's edge.  Only drawer-eligible variants belong here;
    -- their Update modules are the only writers.
    , drawer : List DrawerPanel

    -- Read-only drop-downs under the queue's reminder strips.
    -- Independent of `surface`: several can be open at once.
    , queuePanels : QueuePanels

    -- Which of the Actions column's trigger groups are folded
    -- away.  Independent of `surface` for the same reason.
    , actionGroups : ActionGroups

    -- Dismissed-the-anonymous-banner flag.  When `True`, the
    -- "you're browsing as a guest" strip at the top of the
    -- workspace stays hidden for the rest of the session.
    -- Session-only — reappears on every page reload by design,
    -- because forgetting that anonymous data is local-only is
    -- exactly the failure mode the banner exists to prevent.
    , anonymousBannerDismissed : Bool
    , toasts : List Toast
    , nextToastId : Int
    , rollPopups : List RollPopup
    , nextRollPopupId : Int
    , preferences : Preferences

    -- Account page (`/me`) form state.  Independent of the auth
    -- ADT — `auth` holds *who's signed in*; `accountUi` holds
    -- *what the GM has typed into the profile / password forms
    -- on the Account page*.
    , accountUi : AccountUi

    -- Player party — used by the CR Calculator modal to compute
    -- the per-tier XP budgets the encounter is measured against.
    -- Lives on Model (rather than only inside the calculator's
    -- modal state) so edits persist across modal opens within a
    -- session.  Backend persistence is a follow-up; the in-memory
    -- shape will round-trip cleanly when added.
    , party : List Difficulty.PartyMember
    , nextPartyMemberId : Int

    -- Anonymous-mode bootstrap: the raw localStorage encounter
    -- snapshot from boot flags.  Held verbatim until the auth probe
    -- resolves — if the user is anonymous we decode and adopt it;
    -- if authenticated we discard it (the server is the source of
    -- truth, the migration prompt lives in a later phase).
    , localEncounterRaw : Maybe Decode.Value

    -- Pre-formatted "today" string from the JS host (e.g.
    -- "May 26, 2026"), used to label the named server save slot
    -- when an anonymous encounter is migrated into a freshly-
    -- authenticated session.  Held until the migration fires;
    -- otherwise inert.
    , migrationDateLabel : String

    -- One-shot stash for the anonymous dice-history snapshot from
    -- localStorage.  Adopted on the anonymous boot branch and
    -- discarded on the authenticated branch (server history wins).
    , localDiceHistoryRaw : Maybe Decode.Value

    -- One-shot stash for the anonymous compendium snapshot.  If
    -- present, the anonymous boot branch decodes it and uses it
    -- in place of the bundled-creatures fetch; if absent we fall
    -- back to `/bundled-creatures.json`.
    , localCompendiumRaw : Maybe Decode.Value

    -- Set on the anonymous boot branch when the local snapshot was
    -- written under an older `bundledVersion` than the running
    -- build.  We adopt the snapshot as initial state AND fire a
    -- `/bundled-creatures.json` fetch; when the fetch lands the
    -- `CompendiumLoaded` handler replaces bundled-id creatures
    -- with the fresh data while preserving user-created ones
    -- (id not in the bundle).  Cleared once the merge runs so
    -- subsequent in-session fetches (post sign-in, etc.) keep
    -- the standard replace-everything behaviour.
    , pendingBundleMerge : Bool

    -- Monotonic counter handing out ids for anonymously-created
    -- creatures.  Persisted to localStorage as part of the
    -- compendium snapshot so reloads don't reuse ids.  Server
    -- creatures use full UUIDs; anonymous use `"local-N"`.
    , nextLocalCreatureId : Int

    -- Anonymous named encounter saves keyed by name.  Authed
    -- sessions use the server's `/api/encounter/saves` endpoints;
    -- anonymous sessions mutate this dict and the update-loop
    -- wrapper persists it to `localStorage.encounterSaves`.
    , localEncounterSaves : Dict String EncounterWire.LocalEncounterSave

    -- User-named presets for the Add-Condition modal, keyed by
    -- the name the GM gave each save.  Mirrors the pattern of
    -- the other localStorage-backed dicts: the modal's Save and
    -- Load buttons mutate this dict; the update-loop wrapper
    -- persists it under `localStorage.conditionPresets`.  Anonymous
    -- and authenticated sessions both use this same client-side
    -- dict for now — there's no server endpoint yet because the
    -- preset shape is small and per-device defaults are reasonable.
    , conditionPresets : Dict String UiCondition.ConditionPreset

    -- Twin of `conditionPresets` for the Timer-setup modal.
    -- Persisted under `localStorage.timerPresets`.
    , timerPresets : Dict String UiTimer.TimerPreset

    -- Save Chain presets — reusable "creature makes a save;
    -- something happens" recipes.  Persisted under
    -- `localStorage.saveChainPresets`.
    , saveChainPresets : Dict String SaveChain

    -- User-authored Lore groupings for the Random Encounter
    -- generator's _Lore-leaning_ toggle.  Bundled groups
    -- live in `Encounter.RandomEncounter.Lore.bundled`;
    -- these are the player's additions, edited in the
    -- Create/Edit Group modal and persisted under
    -- `localStorage.userLoreGroups`.
    , userLoreGroups : List Lore.Group

    -- Singular per-user treasure table.  `Nothing` means the
    -- user has nothing saved yet — the generator falls back to
    -- `Encounter.Treasure.bundledTable` in that case.  Edited
    -- in the Treasure Table modal and persisted to
    -- `/api/treasure-table` (or `localStorage.userTreasureTable`
    -- for anonymous sessions).
    , userTreasureTable : Maybe Encounter.Treasure.TreasureTable

    -- Per-user named profiles of "Tune your rolls" settings.
    -- Empty dict means the user hasn't saved any yet.  Loaded
    -- from `/api/treasure-profiles` on authed boot; saved back
    -- via the standard persistence hook in `Main.update`.
    , userTreasureProfiles : Dict.Dict String Encounter.Treasure.TreasureSettings

    -- Draft text for the "Save current as profile…" input.
    , userTreasureProfileNameDraft : String

    -- JS `Date.now()` captured at boot, used as the timestamp for
    -- all anonymous named-save writes done in this session.  All
    -- saves in one session share this timestamp (cosmetic-only;
    -- the migration uploads to the server which assigns its own).
    , bootMs : Int
    }


{-| Floating "+N" popup spawned at the cursor when an inline
dice-link in a creature stat block is clicked. Animated up + out
via CSS; expired by a `Process.sleep` Msg matched on `id`.

`x` / `y` are captured at click time from the DOM event's
`clientX` / `clientY`, so the popup anchors to where the user
clicked even if they've moved the mouse since.

-}
type alias RollPopup =
    { id : Int
    , x : Int
    , y : Int
    , total : Int
    }
