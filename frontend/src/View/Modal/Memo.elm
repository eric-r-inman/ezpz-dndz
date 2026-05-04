module View.Modal.Memo exposing (view)

{-| Card row 3 memo edit modal. Single text input capped at
`Ui.Memo.maxMemoLength` with Save / Cancel buttons. Same chrome
as the row 1 note-edit modal but writes to a different field on
`Creature` (`memo` vs `note`) so they can coexist on the same card.
-}

import Html exposing (Html, button, div, input, text)
import Html.Attributes exposing (autofocus, class, for, id, maxlength, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui.Memo as MemoUi
import Util.Keyboard
import View.Modal


view : Model -> Html Msg
view model =
    case model.memoEdit of
        Nothing ->
            text ""

        Just ui ->
            View.Modal.view
                { close = MemoCancel
                , noOp = NoOp
                , title = "Memo — " ++ ui.target
                , extraClass = "modal--note-edit"
                , body =
                    [ Html.label [ for "memo-edit-input" ]
                        [ text ("Short memo (max " ++ String.fromInt MemoUi.maxMemoLength ++ " chars)") ]
                    , input
                        [ id "memo-edit-input"
                        , class "note-edit__input"
                        , type_ "text"
                        , value ui.text
                        , maxlength MemoUi.maxMemoLength
                        , placeholder "e.g. legendary res used"
                        , autofocus True
                        , onInput MemoChange
                        , Html.Events.on "keydown" (Util.Keyboard.enterKey MemoCommit)
                        ]
                        []
                    , div [ class "note-edit__buttons" ]
                        [ button
                            [ class "action-btn action-btn--green"
                            , onClick MemoCommit
                            ]
                            [ text "Save" ]
                        , button
                            [ class "action-btn"
                            , onClick MemoCancel
                            ]
                            [ text "Cancel" ]
                        ]
                    ]
                }
