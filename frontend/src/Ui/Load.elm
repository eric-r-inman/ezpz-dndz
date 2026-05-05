module Ui.Load exposing
    ( LoadUi, LoadListState(..), ConfirmAction(..)
    , RenameDraft, fresh
    , maxNameLength
    )

{-| Load-encounter modal state.

Mirrors `Ui.Save` but for the load flow: list server-side saves,
let the user pick one (which replaces the current encounter), or
import a save from a local file. Rename / delete affordances on
each row are identical to the Save modal's because the underlying
operations are the same.

@docs LoadUi, LoadListState, ConfirmAction
@docs RenameDraft, fresh
@docs maxNameLength

-}

import Encounter.Wire exposing (SavedEncounterMeta)


{-| Loading state for the server-side save listing.
-}
type LoadListState
    = LoadsLoading
    | LoadsLoaded (List SavedEncounterMeta)
    | LoadsFailed String


{-| Pending two-step action — load with confirmation (replacing
the current encounter is destructive) or delete.
-}
type ConfirmAction
    = ConfirmLoad String
    | ConfirmDelete String


{-| Inline rename row state. Same shape as Save's.
-}
type alias RenameDraft =
    { original : String
    , draft : String
    }


{-| Load-modal state. See `SaveUi` for field semantics — the
two are deliberately parallel.
-}
type alias LoadUi =
    { saves : LoadListState
    , busy : Bool
    , error : Maybe String
    , confirm : Maybe ConfirmAction
    , renaming : Maybe RenameDraft
    }


fresh : LoadUi
fresh =
    { saves = LoadsLoading
    , busy = False
    , error = Nothing
    , confirm = Nothing
    , renaming = Nothing
    }


{-| Mirror of `Ui.Save.maxNameLength`.
-}
maxNameLength : Int
maxNameLength =
    120
