module Model exposing
    ( Modal(..), Model
    , ModalLens, PanelPin, PendingControl(..), RollPopup, cardEditorLens, compendiumEditLens, conditionLens, crCalculatorLens, duplicateLens, groupEditLens, hpChangeLens, initiativeLens, loadCompendiumLens, loadLens, mapModal, memoLens, noteLens, quickAddLens, saveCompendiumLens, saveLens, timerLens
    )

{-| The single source of truth for the running app.

`encounter` holds all D&D-specific state (queue, active
creature, round). Everything else is presentation, auth, or
modal-state plumbing. The discipline mirrors the larger
layering rule: domain state goes through `Encounter`,
everything else stays here.

The `modal` field is a `Maybe Modal` ADT — the constructor
identifies which modal is open and carries its UI state.
`Nothing` means no modal is open. This shape replaces the
older "one `Maybe XxxUi` field per modal" scheme and bakes
the "only one modal open at a time" invariant into the type
system rather than leaving it as a convention.

The exceptions — `dice` and `compendium` — sit outside the
ADT because their substate has to survive a modal close
(dice history, compendium browser cache + filter selection).
Their `open : Bool` field on the substate signals whether the
modal is showing.

`savedSnapshot` is the last-known persisted state of the
encounter — the result of the user's most recent Save (or
Load) action. It backs the Reset button: clicking Reset
copies the snapshot back into `encounter` and forces the round
counter to 1. `savedAs` parallels it, recording the name the
encounter was last saved under so re-saving doesn't make the
user retype the filename.

@docs Modal, Model

-}

import Auth exposing (AuthState)
import Browser.Navigation as Nav
import Card.Layout exposing (CardLayout, QueueView)
import Card.Wire as CardWire
import Encounter exposing (Encounter)
import Encounter.Difficulty as Difficulty
import Encounter.Xp exposing (XpScope)
import Json.Decode as Decode
import Msg exposing (ControlMenu, MeStatus)
import Preferences exposing (Preferences)
import Route exposing (Route)
import Ui.AbilitySave exposing (AbilitySaveUi)
import Ui.Account exposing (AccountUi)
import Ui.CardEditor exposing (CardEditorUi)
import Ui.Compendium exposing (CompendiumEditUi, CompendiumPasteUi, CompendiumUi)
import Ui.Condition exposing (ConditionUi)
import Ui.CrCalculator exposing (CrCalculatorUi)
import Ui.Dice exposing (DiceUi)
import Ui.Duplicate exposing (DuplicateUi)
import Ui.GroupEdit exposing (GroupEditUi)
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi, HpEdit)
import Ui.Initiative exposing (InitiativeUi)
import Ui.Load exposing (LoadUi)
import Ui.LoadCompendium exposing (LoadCompendiumUi)
import Ui.Login exposing (LoginUi)
import Ui.Memo exposing (MemoEditUi)
import Ui.Note exposing (NoteEditUi)
import Ui.QuickAdd exposing (QuickAddUi)
import Ui.Save exposing (SaveUi)
import Ui.SaveCompendium exposing (SaveCompendiumUi)
import Ui.Timer exposing (TimerSetupUi)
import Ui.Toast exposing (Toast)
import Url exposing (Url)


{-| The right-side Compendium pane's pinned creature. Carries
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


{-| Two-step confirmation state for the destructive Encounter
Controls actions (Reset and Clear). When `Just`, the control
panel renders an inline confirmation banner in place of the
button grid so a mis-click can't drop combat state. Cleared by
the user picking Confirm or Cancel.
-}
type PendingControl
    = PendingReset
    | PendingClear


{-| One constructor per modal kind, each carrying its UI state.

The "only one modal open at a time" invariant is type-enforced:
opening modal X assigns `Just (ModalX uiX)` to `model.modal`,
which by construction wipes out whatever was open before.

-}
type Modal
    = ModalHpChange HpChangeUi
    | ModalInitiative InitiativeUi
    | ModalNoteEdit NoteEditUi
    | ModalCondition ConditionUi
    | ModalMemoEdit MemoEditUi
    | ModalTimerSetup TimerSetupUi
    | ModalCompendiumEdit CompendiumEditUi
    | ModalCompendiumPaste CompendiumPasteUi
    | ModalSave SaveUi
    | ModalLoad LoadUi
    | ModalSaveCompendium SaveCompendiumUi
    | ModalLoadCompendium LoadCompendiumUi
    | ModalAbilitySave AbilitySaveUi
    | ModalQuickAdd QuickAddUi
    | ModalDuplicate DuplicateUi
    | ModalGroupEdit GroupEditUi
    | ModalCardEditor CardEditorUi
    | ModalCrCalculator CrCalculatorUi


{-| Pair of `extract` / `wrap` functions identifying one variant
of the `Modal` ADT. Lets `mapModal` be a single generic helper
shared by every Update module instead of each rolling its own
`withFooUi`. See `mapModal` and the per-variant `*Lens` values.
-}
type alias ModalLens a =
    { extract : Modal -> Maybe a
    , wrap : a -> Modal
    }


{-| Apply `fn` to the modal's UI substate, but only if the modal
matching `lens` is currently open. No-op when `model.modal` is
`Nothing` or holds a different variant.

Replaces the per-Update-module `with*Ui` helpers.

-}
mapModal : ModalLens a -> (a -> a) -> Model -> Model
mapModal lens fn model =
    case Maybe.andThen lens.extract model.modal of
        Just ui ->
            { model | modal = Just (lens.wrap (fn ui)) }

        Nothing ->
            model


compendiumEditLens : ModalLens CompendiumEditUi
compendiumEditLens =
    { extract =
        \m ->
            case m of
                ModalCompendiumEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalCompendiumEdit
    }


duplicateLens : ModalLens DuplicateUi
duplicateLens =
    { extract =
        \m ->
            case m of
                ModalDuplicate ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalDuplicate
    }


groupEditLens : ModalLens GroupEditUi
groupEditLens =
    { extract =
        \m ->
            case m of
                ModalGroupEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalGroupEdit
    }


cardEditorLens : ModalLens CardEditorUi
cardEditorLens =
    { extract =
        \m ->
            case m of
                ModalCardEditor ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalCardEditor
    }


crCalculatorLens : ModalLens CrCalculatorUi
crCalculatorLens =
    { extract =
        \m ->
            case m of
                ModalCrCalculator ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalCrCalculator
    }


conditionLens : ModalLens ConditionUi
conditionLens =
    { extract =
        \m ->
            case m of
                ModalCondition ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalCondition
    }


hpChangeLens : ModalLens HpChangeUi
hpChangeLens =
    { extract =
        \m ->
            case m of
                ModalHpChange ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalHpChange
    }


initiativeLens : ModalLens InitiativeUi
initiativeLens =
    { extract =
        \m ->
            case m of
                ModalInitiative ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalInitiative
    }


loadLens : ModalLens LoadUi
loadLens =
    { extract =
        \m ->
            case m of
                ModalLoad ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalLoad
    }


memoLens : ModalLens MemoEditUi
memoLens =
    { extract =
        \m ->
            case m of
                ModalMemoEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalMemoEdit
    }


noteLens : ModalLens NoteEditUi
noteLens =
    { extract =
        \m ->
            case m of
                ModalNoteEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalNoteEdit
    }


quickAddLens : ModalLens QuickAddUi
quickAddLens =
    { extract =
        \m ->
            case m of
                ModalQuickAdd ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalQuickAdd
    }


saveLens : ModalLens SaveUi
saveLens =
    { extract =
        \m ->
            case m of
                ModalSave ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalSave
    }


timerLens : ModalLens TimerSetupUi
timerLens =
    { extract =
        \m ->
            case m of
                ModalTimerSetup ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalTimerSetup
    }


saveCompendiumLens : ModalLens SaveCompendiumUi
saveCompendiumLens =
    { extract =
        \m ->
            case m of
                ModalSaveCompendium ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalSaveCompendium
    }


loadCompendiumLens : ModalLens LoadCompendiumUi
loadCompendiumLens =
    { extract =
        \m ->
            case m of
                ModalLoadCompendium ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = ModalLoadCompendium
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
    , hpEdit : Maybe HpEdit
    , compendium : CompendiumUi
    , modal : Maybe Modal
    , panelCreaturePin : Maybe PanelPin
    , pendingControl : Maybe PendingControl
    , xpScope : XpScope
    , xpFilterOpen : Bool
    , settingsOpen : Bool
    , controlMenu : Maybe ControlMenu
    , toasts : List Toast
    , nextToastId : Int
    , rollPopups : List RollPopup
    , nextRollPopupId : Int
    , preferences : Preferences

    -- Live creature-card layout + queue arrangement.  Bootstraps
    -- from the bundled default; the boot fetch of `/api/card-layouts`
    -- populates [`savedCardLayouts`](#Model) but doesn't pick one —
    -- the user picks which saved layout to load from the editor.
    , cardLayout : CardLayout
    , queueView : QueueView

    -- Metadata for the user's server-side saved card layouts,
    -- fetched on boot via `Card.Wire.fetchList`.  Used by
    -- the card-editor modal's "Saved layouts" panel.
    , savedCardLayouts : List CardWire.SavedLayoutMeta

    -- When True, the encounter panel renders cards through
    -- `View.Card.Custom` (layout-driven).  When False (the
    -- default), the classic `View.Card` renderer is used so
    -- inline click-to-edit features keep working.  Toggled by
    -- the AppBar's "Use custom card layout" button.
    , useCustomCardLayout : Bool

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

    -- Same one-shot bootstrap stash for the anonymous card-layout
    -- snapshot (cardLayout + queueView + useCustomCardLayout).
    -- Decoded and applied by `Update.Auth.meReceived` on the
    -- anonymous branch; discarded on the authenticated branch.
    , localCardLayoutRaw : Maybe Decode.Value

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
