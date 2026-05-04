module Ui.Note exposing (NoteEditUi, maxNoteLength, fresh)

{-| Per-creature note-edit modal state. Triggered by the row 1
pencil button. `target` identifies the creature; `text` mirrors
the `<input>` value so re-renders don't clobber transient
typing. The input is hard-capped at `maxNoteLength` so we never
have to truncate on commit.

@docs NoteEditUi, maxNoteLength, fresh

-}


{-| Modal state.
-}
type alias NoteEditUi =
    { target : String
    , text : String
    }


{-| Hard cap on creature notes. Twenty characters keeps the
inline display next to the name from blowing out the card width
— anything longer belongs in a real journal entry, not a card
sticky.
-}
maxNoteLength : Int
maxNoteLength =
    20


{-| Build the initial state for opening the note editor against a
specific creature, pre-filled with the creature's current note.
-}
fresh : String -> String -> NoteEditUi
fresh target current =
    { target = target
    , text = current
    }
