module View.Modal.SaveCompendium exposing (view)

{-| Save-compendium modal.

Mirrors `View.Modal.Save` but for the creature library: the
top half picks destination + filename; the bottom half lists
existing server-side snapshots so the user can pick one to
overwrite.

The MVP omits rename / delete row affordances — re-saving under
an existing name fires the overwrite confirm prompt, which
covers the common workflow.

-}

import Compendium.Wire exposing (SavedCompendiumMeta)
import Html exposing (Html, button, div, input, label, li, p, span, text, ul)
import Html.Attributes
    exposing
        ( attribute
        , autofocus
        , checked
        , class
        , disabled
        , id
        , maxlength
        , name
        , placeholder
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..), SaveDestination(..))
import Ui.SaveCompendium as SaveCompendiumUi
    exposing
        ( ConfirmAction(..)
        , SaveCompendiumUi
        , SaveListState(..)
        )
import Util.Keyboard
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalSaveCompendium ui) ->
            View.Modal.view
                { close = SaveCompendiumClose
                , noOp = NoOp
                , title = "Save Compendium"
                , extraClass = "modal--save"
                , body =
                    [ destinationSection ui
                    , filenameSection ui
                    , confirmBanner ui
                    , errorBanner ui
                    , savesSection ui
                    , submitRow ui
                    ]
                }

        _ ->
            text ""


destinationSection : SaveCompendiumUi -> Html Msg
destinationSection ui =
    div [ class "save-modal__row save-modal__row--destination" ]
        [ label [ class "save-modal__label" ] [ text "Save to" ]
        , div [ class "save-modal__radio-group", attribute "role" "radiogroup" ]
            [ destinationRadio ui SaveDestinationServer "Server" "save-cmp-dest-server"
            , destinationRadio ui SaveDestinationDevice "Download" "save-cmp-dest-device"
            ]
        ]


destinationRadio : SaveCompendiumUi -> SaveDestination -> String -> String -> Html Msg
destinationRadio ui dest label_ idAttr =
    Html.label [ class "save-modal__radio" ]
        [ input
            [ type_ "radio"
            , id idAttr
            , name "save-compendium-destination"
            , checked (ui.destination == dest)
            , onClick (SaveCompendiumDestinationSet dest)
            ]
            []
        , span [] [ text label_ ]
        ]


filenameSection : SaveCompendiumUi -> Html Msg
filenameSection ui =
    div [ class "save-modal__row" ]
        [ label
            [ class "save-modal__label"
            , Html.Attributes.for "save-compendium-filename"
            ]
            [ text
                (case ui.destination of
                    SaveDestinationServer ->
                        "Save name"

                    SaveDestinationDevice ->
                        "Filename"
                )
            ]
        , input
            [ id "save-compendium-filename"
            , class "save-modal__input"
            , type_ "text"
            , value ui.filename
            , maxlength SaveCompendiumUi.maxNameLength
            , placeholder "e.g. Curse of Strahd Bestiary"
            , autofocus True
            , onInput SaveCompendiumFilenameChanged
            , Html.Events.on "keydown" (Util.Keyboard.enterKey SaveCompendiumSubmit)
            ]
            []
        ]


confirmBanner : SaveCompendiumUi -> Html Msg
confirmBanner ui =
    case ui.confirm of
        Just (ConfirmOverwrite name) ->
            confirmRow
                ("Overwrite \"" ++ name ++ "\" with the current compendium?")
                "Overwrite"

        Just (ConfirmDelete _) ->
            text ""

        Nothing ->
            text ""


confirmRow : String -> String -> Html Msg
confirmRow message confirmLabel =
    div [ class "save-modal__confirm" ]
        [ p [ class "save-modal__confirm-msg" ] [ text message ]
        , div [ class "save-modal__confirm-actions" ]
            [ button
                [ class "action-btn action-btn--red"
                , onClick SaveCompendiumConfirmConfirm
                ]
                [ text confirmLabel ]
            , button
                [ class "action-btn"
                , onClick SaveCompendiumConfirmCancel
                ]
                [ text "Cancel" ]
            ]
        ]


errorBanner : SaveCompendiumUi -> Html Msg
errorBanner ui =
    case ui.error of
        Just err ->
            p [ class "save-modal__error" ] [ text err ]

        Nothing ->
            text ""


savesSection : SaveCompendiumUi -> Html Msg
savesSection ui =
    case ui.saves of
        SavesLoading ->
            div [ class "save-modal__list-empty" ]
                [ text "Loading saved compendiums…" ]

        SavesFailed err ->
            div [ class "save-modal__list-empty" ]
                [ text ("Couldn't load saves: " ++ err) ]

        SavesLoaded [] ->
            div [ class "save-modal__list-empty" ]
                [ text "No saved compendiums yet." ]

        SavesLoaded metas ->
            div [ class "save-modal__list-wrap" ]
                [ p [ class "save-modal__list-title" ]
                    [ text "Existing snapshots" ]
                , ul [ class "save-modal__list" ]
                    (List.map saveRow metas)
                ]


saveRow : SavedCompendiumMeta -> Html Msg
saveRow meta =
    li [ class "save-modal__row-item" ]
        [ span [ class "save-modal__row-name" ] [ text meta.name ]
        , div [ class "save-modal__row-actions" ]
            [ button
                [ class "icon-btn"
                , attribute "aria-label" "Overwrite"
                , onClick (SaveCompendiumOverwriteRequested meta.name)
                ]
                [ text "💾" ]
            ]
        ]


submitRow : SaveCompendiumUi -> Html Msg
submitRow ui =
    div [ class "save-modal__buttons" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick SaveCompendiumSubmit
            , disabled ui.busy
            ]
            [ text
                (case ui.destination of
                    SaveDestinationServer ->
                        "Save"

                    SaveDestinationDevice ->
                        "Download"
                )
            ]
        , button
            [ class "action-btn"
            , onClick SaveCompendiumClose
            ]
            [ text "Close" ]
        ]
