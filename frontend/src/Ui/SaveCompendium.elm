module Ui.SaveCompendium exposing
    ( SaveCompendiumUi, SaveListState(..), ConfirmAction(..)
    , RenameDraft, fresh
    , maxNameLength
    )

{-| Save-compendium modal state.

Mirrors `Ui.Save` (the encounter save modal) for the compendium
snapshot flow. The modal lets the GM save the current creature
library to the server under a name, or trigger a JSON download
to their local machine. Existing server-side snapshots are
listed so the user can rename, delete, or pick one to overwrite.

@docs SaveCompendiumUi, SaveListState, ConfirmAction
@docs RenameDraft, fresh
@docs maxNameLength

-}

import Compendium.Wire exposing (SavedCompendiumMeta)
import Msg exposing (SaveDestination(..))


{-| Loading state for the server-side snapshot listing.
-}
type SaveListState
    = SavesLoading
    | SavesLoaded (List SavedCompendiumMeta)
    | SavesFailed String


{-| One pending two-step action: overwrite an existing snapshot,
or delete one.
-}
type ConfirmAction
    = ConfirmOverwrite String
    | ConfirmDelete String


{-| Inline rename row state.
-}
type alias RenameDraft =
    { original : String
    , draft : String
    }


{-| See `Ui.Save.SaveUi` for field semantics — these are
deliberately parallel.
-}
type alias SaveCompendiumUi =
    { destination : SaveDestination
    , filename : String
    , saves : SaveListState
    , busy : Bool
    , error : Maybe String
    , confirm : Maybe ConfirmAction
    , renaming : Maybe RenameDraft
    }


fresh : SaveDestination -> Maybe String -> SaveCompendiumUi
fresh destination suggestedName =
    { destination = destination
    , filename = Maybe.withDefault "" suggestedName
    , saves = SavesLoading
    , busy = False
    , error = Nothing
    , confirm = Nothing
    , renaming = Nothing
    }


{-| Hard cap on snapshot names. Mirrors the server-side 120-char
limit so the input's `maxlength` enforces it client-side without
a round trip.
-}
maxNameLength : Int
maxNameLength =
    120
