module Ui.PlaceholderRename exposing (PlaceholderRenameState, fresh, maxNameLength)

{-| Inline rename state for the queue's placeholder cards.

A placeholder card (any creature with `isPlaceholder = True`)
replaces its name span with an `<input>` whenever the card's
name matches `state.target`. Only one rename is in flight at a
time, so this is a single `Maybe PlaceholderRenameState` on
`Model` rather than a per-card field.

@docs PlaceholderRenameState, fresh, maxNameLength

-}


{-| In-progress rename. `target` is the current creature name in
the queue (the lookup key); `draft` is what the user has typed
so far. The commit handler swaps the name in the encounter when
the input loses focus or the user hits Enter.
-}
type alias PlaceholderRenameState =
    { target : String
    , draft : String
    }


{-| Open a fresh rename, seeding the draft with the current
display name so the user can edit-in-place rather than start
from a blank input.
-}
fresh : String -> PlaceholderRenameState
fresh name =
    { target = name, draft = name }


{-| Soft cap on rename length so the card layout doesn't tear
when a user pastes a wall of text. Matches `Ui.Note.maxNoteLength`
range for consistency.
-}
maxNameLength : Int
maxNameLength =
    40
