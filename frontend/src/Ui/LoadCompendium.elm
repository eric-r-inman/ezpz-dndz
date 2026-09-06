module Ui.LoadCompendium exposing
    ( LoadCompendiumUi, LoadListState(..), ConfirmAction(..)
    , RenameDraft, fresh
    , maxNameLength
    )

{-| Load-compendium modal state.

Mirrors `Ui.SaveLoad` for the compendium snapshot flow: list
server-side snapshots, let the user pick one (which replaces the
current creature library, hence the load-confirm prompt) or
import a snapshot from a local file.

@docs LoadCompendiumUi, LoadListState, ConfirmAction
@docs RenameDraft, fresh
@docs maxNameLength

-}

import Compendium.Wire exposing (SavedCompendiumMeta)
import Msg exposing (SaveStorage(..))


type LoadListState
    = LoadsLoading
    | LoadsLoaded (List SavedCompendiumMeta)
    | LoadsFailed String


type ConfirmAction
    = ConfirmLoad String
    | ConfirmDelete String


type alias RenameDraft =
    { original : String
    , draft : String
    }


type alias LoadCompendiumUi =
    { source : SaveStorage
    , saves : LoadListState
    , busy : Bool
    , error : Maybe String
    , confirm : Maybe ConfirmAction
    , renaming : Maybe RenameDraft
    }


{-| Default the source to Server to mirror the Save Compendium
modal — anonymous users see the sign-in hint immediately and
can flip to Device with one click, same flow either way.
-}
fresh : LoadCompendiumUi
fresh =
    { source = StorageServer
    , saves = LoadsLoading
    , busy = False
    , error = Nothing
    , confirm = Nothing
    , renaming = Nothing
    }


maxNameLength : Int
maxNameLength =
    120
