module Model exposing
    ( Modal(..), Model
    , ModalLens, PanelPin, PendingControl(..), RollPopup, compendiumEditLens, conditionLens, duplicateLens, hpChangeLens, initiativeLens, loadCompendiumLens, loadLens, mapModal, memoLens, noteLens, quickAddLens, saveCompendiumLens, saveLens, timerLens
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

import Browser.Navigation as Nav
import Encounter exposing (Encounter)
import Encounter.Xp exposing (XpScope)
import Msg exposing (ControlMenu, MeStatus)
import Preferences exposing (Preferences)
import Route exposing (Route)
import Ui.AbilitySave exposing (AbilitySaveUi)
import Ui.Compendium exposing (CompendiumEditUi, CompendiumPasteUi, CompendiumUi)
import Ui.Condition exposing (ConditionUi)
import Ui.Dice exposing (DiceUi)
import Ui.Duplicate exposing (DuplicateUi)
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi, HpEdit)
import Ui.Initiative exposing (InitiativeUi)
import Ui.Load exposing (LoadUi)
import Ui.LoadCompendium exposing (LoadCompendiumUi)
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
