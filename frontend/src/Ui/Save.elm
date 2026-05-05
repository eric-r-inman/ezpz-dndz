module Ui.Save exposing
    ( SaveUi, SaveListState(..), ConfirmAction(..)
    , RenameDraft, fresh
    , maxNameLength
    )

{-| Save-encounter modal state.

The modal lets the user save the current encounter either to the
server (under their account) or as a download to their local
machine. It also lists all server-side saves so the user can
rename, delete, or pick one to overwrite.

The `confirm` field is the modal's tiny inline confirmation
banner — overwriting or deleting always goes through it so a
mis-click can't drop a save. Only one confirmation is in flight
at a time; that's why it's a `Maybe ConfirmAction` rather than a
list.

@docs SaveUi, SaveListState, ConfirmAction
@docs RenameDraft, fresh
@docs maxNameLength

-}

import Encounter.Wire exposing (SavedEncounterMeta)
import Msg exposing (SaveDestination(..))


{-| Loading state for the server-side save listing. The modal
opens with `SavesLoading` and transitions on the response.
-}
type SaveListState
    = SavesLoading
    | SavesLoaded (List SavedEncounterMeta)
    | SavesFailed String


{-| One pending two-step action: either an overwrite of an
existing server-side save, or a delete of one. Both prompt the
user via the modal's inline confirmation banner before firing
the wire call.
-}
type ConfirmAction
    = ConfirmOverwrite String
    | ConfirmDelete String


{-| Inline rename row state. `original` is the existing save
name; `draft` is what the user has typed so far. The modal
hides the draft field for everyone except the row currently
being renamed, so we don't need a per-row record on the list.
-}
type alias RenameDraft =
    { original : String
    , draft : String
    }


{-| Save-modal state.

  - `destination` — server vs. device.
  - `filename` — user-provided save name (server) or download
    filename stem (device). Initial value is whatever the
    encounter was last saved as, so re-saving doesn't make the
    user retype.
  - `saves` — server-side listing.
  - `busy` — submit / delete / rename inflight; disables the
    submit button to prevent double-fires.
  - `error` — last failure message, cleared on the next user
    interaction.
  - `confirm` — pending overwrite / delete prompt.
  - `renaming` — inline rename row state.

-}
type alias SaveUi =
    { destination : SaveDestination
    , filename : String
    , saves : SaveListState
    , busy : Bool
    , error : Maybe String
    , confirm : Maybe ConfirmAction
    , renaming : Maybe RenameDraft
    }


{-| Build the initial modal state. The caller passes the
encounter's last-known save name (if any) so the filename input
opens pre-filled.
-}
fresh : Maybe String -> SaveUi
fresh suggestedName =
    { destination = SaveDestinationServer
    , filename = Maybe.withDefault "" suggestedName
    , saves = SavesLoading
    , busy = False
    , error = Nothing
    , confirm = Nothing
    , renaming = Nothing
    }


{-| Hard cap on save names. Mirrors the server-side validation
(120 chars) so the input's `maxlength` enforces it client-side
without a round trip.
-}
maxNameLength : Int
maxNameLength =
    120
