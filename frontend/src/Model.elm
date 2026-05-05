module Model exposing
    ( Modal(..), Model
    , PanelPin, PendingControl(..)
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
import Msg exposing (MeStatus)
import Preferences exposing (Preferences)
import Route exposing (Route)
import Ui.AbilitySave exposing (AbilitySaveUi)
import Ui.Compendium exposing (CompendiumEditUi, CompendiumPasteUi, CompendiumUi)
import Ui.Condition exposing (ConditionUi)
import Ui.Dice exposing (DiceUi)
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi, HpEdit)
import Ui.Initiative exposing (InitiativeUi)
import Ui.Load exposing (LoadUi)
import Ui.Memo exposing (MemoEditUi)
import Ui.Note exposing (NoteEditUi)
import Ui.Save exposing (SaveUi)
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
    | ModalAbilitySave AbilitySaveUi


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
    , toasts : List Toast
    , nextToastId : Int
    , preferences : Preferences
    }
