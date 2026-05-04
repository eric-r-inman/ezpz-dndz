module Model exposing (Model)

{-| The single source of truth for the running app.

`encounter` holds all D&D-specific state (queue, active
creature, round). Everything else is presentation, auth, or
modal-state plumbing. The discipline mirrors the larger
layering rule: domain state goes through `Encounter`,
everything else stays here.

Each modal-shaped field is `Maybe` (open ↔ closed lives in the
record itself, not as a flag inside the Ui state) so an
`Encounter.mapCreature` that deletes the targeted creature
can't leave a stale modal pointing at something that no
longer exists. The exceptions — `dice` and `compendium` — are
always present because they wrap state that survives modal
close (dice history, compendium browser cache).

This module exposes only the `Model` type. Forthcoming
`Update/*` modules import it as a type-level surface; they
shouldn't need anything else from here, since modal state
constructors live in their respective `Ui/*` modules and the
`Model` itself is only ever assembled by `Main.init`.

@docs Model

-}

import Browser.Navigation as Nav
import Encounter exposing (Encounter)
import Msg exposing (MeStatus)
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


type alias Model =
    { key : Nav.Key
    , url : Url
    , route : Route
    , me : MeStatus
    , encounter : Encounter
    , dice : DiceUi
    , hpChange : Maybe HpChangeUi
    , hpChangeLog : List HpChangeEntry
    , hpEdit : Maybe HpEdit
    , initiative : Maybe InitiativeUi
    , noteEdit : Maybe NoteEditUi
    , conditionUi : Maybe ConditionUi
    , memoEdit : Maybe MemoEditUi
    , timerSetup : Maybe TimerSetupUi
    , compendium : CompendiumUi
    , compendiumEdit : Maybe CompendiumEditUi
    , compendiumPaste : Maybe CompendiumPasteUi
    , panelCreatureId : Maybe String
    , toasts : List Toast
    , nextToastId : Int
    }
