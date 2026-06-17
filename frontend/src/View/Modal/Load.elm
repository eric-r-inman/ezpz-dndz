module View.Modal.Load exposing (view)

{-| Load-encounter modal.

Mirrors the Save modal's shape — a Server / Device source radio
at top, then a body that depends on the picked source:

  - **Server** (authenticated) → list of server-side saves with
    rename / delete affordances; pick a row to load it (replaces
    the current encounter, gated by a confirm banner).
  - **Browser** (anonymous) → same list, but the rows come from
    `localStorage.encounterSaves`. Same wire shape so the row
    affordances are identical.
  - **Device** → a file-picker button that reuses the existing
    `LoadFromDeviceClick` flow.

Renders nothing when the modal isn't open.

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
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg exposing (LoadSource(..), Msg(..))
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
                , chrome = model.modalChrome
                , body =
                    [ overwriteWarning
                    , sourceSection model.auth ui
                    , confirmBanner ui
                    , errorBanner ui
                    , bodyForSource ui
                    , closeRow
                    ]
                }

        _ ->
            text ""


overwriteWarning : Html Msg
overwriteWarning =
    p [ class "random-encounter__blurb" ]
        [ text "This will overwrite your current encounter.  If you want to keep your current encounter, save it first." ]


sourceSection : Auth.AuthState -> LoadUi -> Html Msg
sourceSection auth ui =
    let
        serverLabel =
            if Auth.isAuthenticated auth then
                "Server"

            else
                "Browser"
    in
    div [ class "save-modal__row save-modal__row--destination" ]
        [ label [ class "save-modal__label" ] [ text "Load from" ]
        , div [ class "save-modal__radio-group", attribute "role" "radiogroup" ]
            [ sourceRadio ui LoadSourceServer serverLabel "load-src-server"
            , sourceRadio ui LoadSourceDevice "Device" "load-src-device"
            ]
        ]


sourceRadio : LoadUi -> LoadSource -> String -> String -> Html Msg
sourceRadio ui source label_ idAttr =
    Html.label [ class "save-modal__radio" ]
        [ input
            [ type_ "radio"
            , id idAttr
            , name "load-source"
            , checked (ui.source == source)
            , onClick (LoadSourceSet source)
            ]
            []
        , span [] [ text label_ ]
        ]


bodyForSource : LoadUi -> Html Msg
bodyForSource ui =
    case ui.source of
        LoadSourceServer ->
            savesSection ui

        LoadSourceDevice ->
            deviceRow


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

        LoadsFailed _ ->
            -- Per user request: never surface "Couldn't load
            -- saves: ..." text.  Treat as empty-state.
            div [ class "save-modal__list-empty" ]
                [ text "No saved encounters yet." ]

        LoadsLoaded [] ->
            div [ class "save-modal__list-empty" ]
                [ text "No saved encounters yet." ]

        LoadsLoaded metas ->
            div [ class "save-modal__list-wrap" ]
                [ p [ class "save-modal__list-title" ] [ text "Existing saves" ]
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
        , Tooltips.attr Tooltips.loadRowEncounter
        , disabled isBusy
        , onClick (LoadFromServerRequested meta.name)
        ]
        [ text meta.name ]
    , div [ class "save-modal__row-actions" ]
        [ button
            [ class "icon-btn"
            , Tooltips.attr Tooltips.saveRowRename
            , attribute "aria-label" "Rename"
            , onClick (LoadRenameStart meta.name)
            ]
            [ text "✎" ]
        , button
            [ class "icon-btn icon-btn--danger"
            , Tooltips.attr Tooltips.saveRowDelete
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
