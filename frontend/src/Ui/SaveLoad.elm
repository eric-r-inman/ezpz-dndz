module Ui.SaveLoad exposing
    ( SaveLoadUi, ListState(..), ConfirmAction(..)
    , RenameDraft, fresh
    , maxNameLength
    )

{-| Encounter save/load panel state.

@docs SaveLoadUi, ListState, ConfirmAction
@docs RenameDraft, fresh
@docs maxNameLength

-}

import Encounter.Wire exposing (SavedEncounterMeta)
import Msg exposing (SaveStorage(..))


{-| Loading state for the save listing. The panel wears
`ListLoading` until expanding it asks for the saves.
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


{-| Save/load panel state.

  - `storage` — server for a signed-in GM, browser storage for
    an anonymous one; or a file on their machine.
  - `filename` — what the save will be called; `primeList`
    fills it in from the encounter's last save name.
  - `busy` — a wire call is in flight; disables the actions that
    would double-fire.

-}
type alias SaveLoadUi =
    { storage : SaveStorage
    , filename : String
    , saves : ListState
    , busy : Bool
    , error : Maybe String
    , confirm : Maybe ConfirmAction
    , renaming : Maybe RenameDraft
    }


fresh : SaveLoadUi
fresh =
    { storage = StorageServer
    , filename = ""
    , saves = ListLoading
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
