module Ui.SaveLoad exposing
    ( SaveLoadUi, ListState(..), ConfirmAction(..), Purpose(..)
    , RenameDraft, fresh
    , maxNameLength
    )

{-| Encounter save/load state, shared by the two modals the
Encounter menu opens.

@docs SaveLoadUi, ListState, ConfirmAction, Purpose
@docs RenameDraft, fresh
@docs maxNameLength

-}

import Encounter.Wire exposing (SavedEncounterMeta)
import Msg exposing (SaveStorage(..))


{-| Which of the two modals this state is driving.
-}
type Purpose
    = ForSave
    | ForLoad


{-| Loading state for the save listing. The modal wears
`ListLoading` until the fetch lands.
-}
type ListState
    = ListLoading
    | ListLoaded (List SavedEncounterMeta)
    | ListFailed String


{-| One pending two-step action. Overwrite and delete risk a
save; load risks the encounter on screen. All three ask first.
-}
type ConfirmAction
    = ConfirmOverwrite String
    | ConfirmDelete String
    | ConfirmLoad String


{-| Inline rename row state. `original` is the existing save
name; `draft` is what the GM has typed so far. Only the row
being renamed shows a draft field, so this doesn't need to be
per-row.
-}
type alias RenameDraft =
    { original : String
    , draft : String
    }


{-| Save/load modal state.

  - `storage` — the account's saves on the server, or a file on
    the GM's machine.
  - `filename` — what the save will be called; `primeList`
    fills it in from the encounter's last save name.
  - `selected` — the save the list's actions work on. A name the
    listing no longer holds counts as nothing picked.
  - `busy` — a wire call is in flight; disables the actions that
    would double-fire.

-}
type alias SaveLoadUi =
    { purpose : Purpose
    , storage : SaveStorage
    , filename : String
    , saves : ListState
    , selected : Maybe String
    , busy : Bool
    , error : Maybe String
    , confirm : Maybe ConfirmAction
    , renaming : Maybe RenameDraft
    }


fresh : Purpose -> SaveLoadUi
fresh purpose =
    { purpose = purpose
    , storage = StorageServer
    , filename = ""
    , saves = ListLoading
    , selected = Nothing
    , busy = False
    , error = Nothing
    , confirm = Nothing
    , renaming = Nothing
    }


{-| Hard cap on save names. Mirrors the server-side validation
so the input's `maxlength` enforces it without a round trip.
-}
maxNameLength : Int
maxNameLength =
    120
