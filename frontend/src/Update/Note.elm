module Update.Note exposing (cancel, change, commit, open)

{-| Update branches for the per-creature note-edit modal (the
single-line annotation that renders next to the creature name).
Empty strings are valid: that's how the user clears a note without
a separate "delete" action.
-}

import Encounter
import Model exposing (Model, Surface(..))
import Msg exposing (Msg)
import Ui.Note as NoteUi exposing (NoteEditUi)


withNoteEdit : (NoteEditUi -> NoteEditUi) -> Model -> Model
withNoteEdit =
    Model.mapSurface Model.noteLens


{-| Opening is a toggle: clicking the note affordance while its
own in-place input is already showing closes it (a cancel).
-}
open : String -> String -> Model -> ( Model, Cmd Msg )
open name current model =
    ( case model.surface of
        Just (SurfaceNoteEdit ui) ->
            if ui.target == name then
                { model | surface = Nothing }

            else
                { model | surface = Just (SurfaceNoteEdit (NoteUi.fresh name current)) }

        _ ->
            { model | surface = Just (SurfaceNoteEdit (NoteUi.fresh name current)) }
    , Cmd.none
    )


{-| Cap the text at `NoteUi.maxNoteLength` here so the model never
holds an over-long note even if a paste sneaks past the input's
`maxlength` attribute.
-}
change : String -> Model -> ( Model, Cmd Msg )
change text model =
    ( withNoteEdit (\u -> { u | text = String.left NoteUi.maxNoteLength text }) model
    , Cmd.none
    )


{-| Trim trailing whitespace before stamping. Empty strings are
valid (clears the note) — that's how the user removes a note
without a separate "delete" action.
-}
commit : Model -> ( Model, Cmd Msg )
commit model =
    case model.surface of
        Just (SurfaceNoteEdit ui) ->
            let
                trimmed =
                    String.trim ui.text
            in
            ( { model
                | encounter =
                    Encounter.mapCreature ui.target
                        (\c -> { c | note = trimmed })
                        model.encounter
                , surface = Nothing
              }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


cancel : Model -> ( Model, Cmd Msg )
cancel model =
    ( { model | surface = Nothing }, Cmd.none )
