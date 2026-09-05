module View.Panel.Save exposing (view)

{-| Save-encounter panel.

Top: destination toggle (Server / Device), filename input,
submit button.

Bottom: scrollable list of existing server-side saves, each row
offering rename / overwrite / delete affordances. Inline
confirmation banner appears for destructive actions; inline
rename row appears when the user clicks ✎.

Renders nothing when the panel isn't open.

-}

import Auth
import Encounter.Wire exposing (SavedEncounterMeta)
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
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..), SaveDestination(..))
import Ui.Save as SaveUi
    exposing
        ( ConfirmAction(..)
        , SaveListState(..)
        , SaveUi
        )
import Util.Keyboard
import View.Panel
import View.Tooltips as Tooltips


view : View.Panel.Header -> Model -> Html Msg
view collapse model =
    case Model.drawerGet Model.saveLens model of
        Just ui ->
            View.Panel.view
                { close = SaveClose
                , title = "Save Encounter"
                , titleTrail = Nothing
                , subtitle = Nothing
                , collapse = collapse
                , extraClass = "panel-drawer--save"
                , body =
                    [ destinationSection model.auth ui
                    , filenameSection ui
                    , confirmBanner ui
                    , errorBanner ui
                    , savesSection ui
                    , submitRow ui
                    ]
                }

        _ ->
            text ""


{-| Server-destination label adapts to auth: authenticated users
see "Server" (the canonical server path), anonymous users see
"Browser" because their save lands in `localStorage` instead.
Same `SaveDestinationServer` value either way — the submit
handler in `Update.Save` picks the right backend.
-}
destinationSection : Auth.AuthState -> SaveUi -> Html Msg
destinationSection auth ui =
    let
        serverLabel =
            if Auth.isAuthenticated auth then
                "Server"

            else
                "Browser"
    in
    div [ class "save-modal__row save-modal__row--destination" ]
        [ label [ class "save-modal__label" ] [ text "Save to" ]
        , div [ class "save-modal__radio-group", attribute "role" "radiogroup" ]
            [ destinationRadio ui SaveDestinationServer serverLabel "save-dest-server"
            , destinationRadio ui SaveDestinationDevice "Device" "save-dest-device"
            ]
        ]


destinationRadio : SaveUi -> SaveDestination -> String -> String -> Html Msg
destinationRadio ui dest label_ idAttr =
    Html.label [ class "save-modal__radio" ]
        [ input
            [ type_ "radio"
            , id idAttr
            , name "save-destination"
            , checked (ui.destination == dest)
            , onClick (SaveDestinationSet dest)
            ]
            []
        , span [] [ text label_ ]
        ]


filenameSection : SaveUi -> Html Msg
filenameSection ui =
    div [ class "save-modal__row" ]
        [ label
            [ class "save-modal__label", Html.Attributes.for "save-filename" ]
            [ text
                (case ui.destination of
                    SaveDestinationServer ->
                        "Save name"

                    SaveDestinationDevice ->
                        "Filename"
                )
            ]
        , input
            [ id "save-filename"
            , class "save-modal__input"
            , type_ "text"
            , value ui.filename
            , maxlength SaveUi.maxNameLength
            , placeholder "e.g. Goblin Ambush — Round 2"
            , autofocus True
            , onInput SaveFilenameChanged
            , Html.Events.on "keydown" (Util.Keyboard.enterKey SaveSubmit)
            ]
            []
        ]


confirmBanner : SaveUi -> Html Msg
confirmBanner ui =
    case ui.confirm of
        Just (ConfirmOverwrite name) ->
            confirmRow
                ("Overwrite \"" ++ name ++ "\" with the current encounter?")
                "Overwrite"

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
                , onClick SaveConfirmConfirm
                ]
                [ text confirmLabel ]
            , button
                [ class "action-btn"
                , onClick SaveConfirmCancel
                ]
                [ text "Cancel" ]
            ]
        ]


errorBanner : SaveUi -> Html Msg
errorBanner ui =
    case ui.error of
        Just err ->
            p [ class "save-modal__error" ] [ text err ]

        Nothing ->
            text ""


savesSection : SaveUi -> Html Msg
savesSection ui =
    case ui.saves of
        SavesLoading ->
            div [ class "save-modal__list-empty" ] [ text "Loading saved encounters…" ]

        SavesFailed _ ->
            -- Per user request: never surface "Couldn't load saves:
            -- ..." text.  A genuine network failure reads as
            -- empty-state — the close-and-retry path is more useful
            -- than a raw error string.
            div [ class "save-modal__list-empty" ]
                [ text "No saved encounters yet." ]

        SavesLoaded [] ->
            div [ class "save-modal__list-empty" ]
                [ text "No saved encounters yet." ]

        SavesLoaded metas ->
            div [ class "save-modal__list-wrap" ]
                [ p [ class "save-modal__list-title" ] [ text "Existing saves" ]
                , ul [ class "save-modal__list" ]
                    (List.map (saveRow ui) metas)
                ]


saveRow : SaveUi -> SavedEncounterMeta -> Html Msg
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
            renameRow ui meta

         else
            displayRow meta
        )


displayRow : SavedEncounterMeta -> List (Html Msg)
displayRow meta =
    [ span [ class "save-modal__row-name" ] [ text meta.name ]
    , div [ class "save-modal__row-actions" ]
        [ button
            [ class "icon-btn"
            , Tooltips.attr Tooltips.saveRowOverwrite
            , attribute "aria-label" "Overwrite"
            , onClick (SaveOverwriteRequested meta.name)
            ]
            [ text "💾" ]
        , button
            [ class "icon-btn"
            , Tooltips.attr Tooltips.saveRowRename
            , attribute "aria-label" "Rename"
            , onClick (SaveRenameStart meta.name)
            ]
            [ text "✎" ]
        , button
            [ class "icon-btn icon-btn--danger"
            , Tooltips.attr Tooltips.saveRowDelete
            , attribute "aria-label" "Delete"
            , onClick (SaveDeleteRequested meta.name)
            ]
            [ text "🗑" ]
        ]
    ]


renameRow : SaveUi -> SavedEncounterMeta -> List (Html Msg)
renameRow ui _ =
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
        , maxlength SaveUi.maxNameLength
        , autofocus True
        , onInput SaveRenameChange
        , Html.Events.on "keydown" (Util.Keyboard.enterKey SaveRenameSubmit)
        ]
        []
    , div [ class "save-modal__row-actions" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick SaveRenameSubmit
            ]
            [ text "Save" ]
        , button
            [ class "action-btn"
            , onClick SaveRenameCancel
            ]
            [ text "Cancel" ]
        ]
    ]


submitRow : SaveUi -> Html Msg
submitRow ui =
    div [ class "save-modal__buttons" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick SaveSubmit
            , disabled ui.busy
            ]
            -- Single "Save" label across both destinations
            -- matches the Compendium modal pattern and reads
            -- consistently with the Actions column's "Save"
            -- button that opened this panel.
            [ text "Save" ]
        , button
            [ class "action-btn"
            , onClick SaveClose
            ]
            [ text "Close" ]
        ]
