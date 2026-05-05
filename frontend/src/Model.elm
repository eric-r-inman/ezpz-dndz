module Model exposing (Modal(..), Model)

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

@docs Modal, Model

-}

import Browser.Navigation as Nav
import Encounter exposing (Encounter)
import Msg exposing (MeStatus)
import Preferences exposing (Preferences)
import Route exposing (Route)
import Ui.Compendium exposing (CompendiumEditUi, CompendiumPasteUi, CompendiumUi)
import Ui.Condition exposing (ConditionUi)
import Ui.Dice exposing (DiceUi)
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi, HpEdit)
import Ui.Initiative exposing (InitiativeUi)
import Ui.Memo exposing (MemoEditUi)
import Ui.Note exposing (NoteEditUi)
import Ui.Timer exposing (TimerSetupUi)
import Ui.Toast exposing (Toast)
import Url exposing (Url)


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


type alias Model =
    { key : Nav.Key
    , url : Url
    , route : Route
    , me : MeStatus
    , encounter : Encounter
    , dice : DiceUi
    , hpChangeLog : List HpChangeEntry
    , hpEdit : Maybe HpEdit
    , compendium : CompendiumUi
    , modal : Maybe Modal
    , panelCreatureId : Maybe String
    , toasts : List Toast
    , nextToastId : Int
    , preferences : Preferences
    }
