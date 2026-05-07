module View.Modal.Load exposing (view)

{-| Load-encounter modal.

Top: source selector — pick a server save (the list below) or
upload one from the user's device.

Middle: scrollable list of server-side saves with rename /
delete affordances mirroring the Save modal. Clicking a row
prompts for confirmation since loading replaces the current
encounter.

Renders nothing when the modal isn't open.

-}

import Encounter.Wire exposing (SavedEncounterMeta)
import Html exposing (Html, button, div, input, li, p, text, ul)
import Html.Attributes
    exposing
        ( attribute
        , autofocus
        , class
        , disabled
        , maxlength
        , title
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Load as LoadUi
    exposing
        ( ConfirmAction(..)
        , LoadListState(..)
        , LoadUi
        )
import Util.Keyboard
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalLoad ui) ->
            View.Modal.view
                { close = LoadClose
                , noOp = NoOp
                , title = "Load Encounter"
                , extraClass = "modal--load"
                , body =
                    [ deviceRow
                    , confirmBanner ui
                    , errorBanner ui
                    , savesSection ui
                    , closeRow
                    ]
                }

        _ ->
            text ""


deviceRow : Html Msg
deviceRow =
    div [ class "load-modal__device" ]
        [ p [ class "load-modal__device-text" ]
            [ text "Have a save on your computer?" ]
        , button
            [ class "action-btn action-btn--blue"
            , onClick LoadFromDeviceClick
            ]
            [ text "📁 Choose file…" ]
        ]


confirmBanner : LoadUi -> Html Msg
confirmBanner ui =
    case ui.confirm of
        Just (ConfirmLoad name) ->
            confirmRow
                ("Load \"" ++ name ++ "\"? This replaces the current encounter.")
                "Load"

        Just (ConfirmDelete name) ->
            confirmRow
                ("Delete saved encounter \"" ++ name ++ "\"? This cannot be undone.")
                "Delete"

        Nothing ->
            text ""


confirmRow : String -> String -> Html Msg
confirmRow message confirmLabel =
    div [ class "save-modal__confirm" ]
        [ p [ class "save-modal__confirm-msg" ] [ text message ]
        , div [ class "save-modal__confirm-actions" ]
            [ button
                [ class "action-btn action-btn--red"
                , onClick LoadConfirmConfirm
                ]
                [ text confirmLabel ]
            , button
                [ class "action-btn"
                , onClick LoadConfirmCancel
                ]
                [ text "Cancel" ]
            ]
        ]


errorBanner : LoadUi -> Html Msg
errorBanner ui =
    case ui.error of
        Just err ->
            p [ class "save-modal__error" ] [ text err ]

        Nothing ->
            text ""


savesSection : LoadUi -> Html Msg
savesSection ui =
    case ui.saves of
        LoadsLoading ->
            div [ class "save-modal__list-empty" ] [ text "Loading saved encounters…" ]

        LoadsFailed err ->
            div [ class "save-modal__list-empty" ]
                [ text ("Couldn't load saves: " ++ err) ]

        LoadsLoaded [] ->
            div [ class "save-modal__list-empty" ]
                [ text "No saved encounters on the server." ]

        LoadsLoaded metas ->
            div [ class "save-modal__list-wrap" ]
                [ p [ class "save-modal__list-title" ] [ text "Server saves" ]
                , ul [ class "save-modal__list" ]
                    (List.map (saveRow ui) metas)
                ]


saveRow : LoadUi -> SavedEncounterMeta -> Html Msg
saveRow ui meta =
    let
        isRenaming =
            case ui.renaming of
                Just r ->
                    r.original == meta.name

                Nothing ->
                    False
    in
    li [ class "save-modal__row-item" ]
        (if isRenaming then
            renameRow ui

         else
            displayRow meta ui.busy
        )


displayRow : SavedEncounterMeta -> Bool -> List (Html Msg)
displayRow meta isBusy =
    [ button
        [ class "save-modal__row-name save-modal__row-name--clickable"
        , title Tooltips.loadRowEncounter
        , disabled isBusy
        , onClick (LoadFromServerRequested meta.name)
        ]
        [ text meta.name ]
    , div [ class "save-modal__row-actions" ]
        [ button
            [ class "icon-btn"
            , title Tooltips.saveRowRename
            , attribute "aria-label" "Rename"
            , onClick (LoadRenameStart meta.name)
            ]
            [ text "✎" ]
        , button
            [ class "icon-btn icon-btn--danger"
            , title Tooltips.saveRowDelete
            , attribute "aria-label" "Delete"
            , onClick (LoadDeleteRequested meta.name)
            ]
            [ text "🗑" ]
        ]
    ]


renameRow : LoadUi -> List (Html Msg)
renameRow ui =
    let
        draft =
            ui.renaming
                |> Maybe.map .draft
                |> Maybe.withDefault ""
    in
    [ input
        [ class "save-modal__rename-input"
        , type_ "text"
        , value draft
        , maxlength LoadUi.maxNameLength
        , autofocus True
        , onInput LoadRenameChange
        , Html.Events.on "keydown" (Util.Keyboard.enterKey LoadRenameSubmit)
        ]
        []
    , div [ class "save-modal__row-actions" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick LoadRenameSubmit
            ]
            [ text "Save" ]
        , button
            [ class "action-btn"
            , onClick LoadRenameCancel
            ]
            [ text "Cancel" ]
        ]
    ]


closeRow : Html Msg
closeRow =
    div [ class "save-modal__buttons" ]
        [ button
            [ class "action-btn"
            , onClick LoadClose
            ]
            [ text "Close" ]
        ]
