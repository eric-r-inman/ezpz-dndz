module View.Modal.Note exposing (view)

{-| Card row 1 note edit modal. Single-line text input capped at
`Ui.Note.maxNoteLength` with Save / Cancel buttons. Renders nothing
when the modal is closed.
-}

import Html exposing (Html, button, div, input, text)
import Html.Attributes exposing (autofocus, class, for, id, maxlength, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Note as NoteUi
import Util.Keyboard
import View.Modal


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalNoteEdit ui) ->
            View.Modal.view
                { close = NoteEditCancel
                , noOp = NoOp
                , title = "Note — " ++ ui.target
                , extraClass = "modal--note-edit"
                , chrome = model.modalChrome
                , body =
                    [ Html.label [ for "note-edit-input" ]
                        [ text ("Short label (max " ++ String.fromInt NoteUi.maxNoteLength ++ " chars)") ]
                    , input
                        [ id "note-edit-input"
                        , class "note-edit__input"
                        , type_ "text"
                        , value ui.text
                        , maxlength NoteUi.maxNoteLength
                        , placeholder "e.g. boss, summoned, ally"
                        , autofocus True
                        , onInput NoteEditChange
                        , Html.Events.on "keydown" (Util.Keyboard.enterKey NoteEditCommit)
                        ]
                        []
                    , div [ class "note-edit__buttons" ]
                        [ button
                            [ class "action-btn action-btn--green"
                            , onClick NoteEditCommit
                            ]
                            [ text "Save" ]
                        , button
                            [ class "action-btn"
                            , onClick NoteEditCancel
                            ]
                            [ text "Cancel" ]
                        ]
                    ]
                }

        _ ->
            text ""
