module Ui.PlaceholderRename exposing (PlaceholderRenameState, fresh, isPlaceholderName, maxNameLength)

{-| Inline rename state for the queue's placeholder cards.

A `Placeholder N` creature card replaces its name span with an
`<input>` whenever the card's name matches `state.target`. Only
one rename is in flight at a time, so this is a single
`Maybe PlaceholderRenameState` on `Model` rather than a per-card
field.

@docs PlaceholderRenameState, fresh, isPlaceholderName, maxNameLength

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


{-| Does this creature name match the queue-bottom Placeholder
series? Used by `View.Card` to gate the click-to-rename
affordance — only `Placeholder N` cards get the clickable name.
Once renamed away from the pattern the affordance vanishes; the
user can still delete + re-add a fresh placeholder if needed.
-}
isPlaceholderName : String -> Bool
isPlaceholderName name =
    case String.split " " name of
        "Placeholder" :: rest ->
            case rest of
                [ tail ] ->
                    case String.toInt tail of
                        Just _ ->
                            True

                        Nothing ->
                            False

                _ ->
                    False

        _ ->
            False


{-| Soft cap on rename length so the card layout doesn't tear
when a user pastes a wall of text. Matches `Ui.Note.maxNoteLength`
range for consistency.
-}
maxNameLength : Int
maxNameLength =
    40
