module View.Panel.SaveLoad exposing (view)

{-| Encounter save/load panel; the chrome comes from
`View.Panel`.
-}

import Auth
import Encounter.Wire exposing (SavedEncounterMeta)
import Html exposing (Html, button, div, h3, input, li, p, span, text, ul)
import Html.Attributes
    exposing
        ( attribute
        , autofocus
        , class
        , disabled
        , id
        , maxlength
        , placeholder
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Model)
import Msg exposing (Msg(..), SaveStorage(..))
import Ui.SaveLoad as SaveLoadUi
    exposing
        ( ConfirmAction(..)
        , ListState(..)
        , SaveLoadUi
        )
import Util.Keyboard
import View.Panel
import View.Tooltips as Tooltips


view : View.Panel.Header -> Model -> Html Msg
view collapse model =
    case Model.drawerGet Model.saveLoadLens model of
        Just ui ->
            View.Panel.view
                { close = SaveLoadClose
                , title = "Encounter Saves"
                , titleTrail = Nothing
                , subtitle = Nothing
                , collapse = collapse
                , extraClass = "panel-drawer--save-load"
                , body =
                    [ storageSection model.auth ui
                    , confirmBanner ui
                    , errorBanner ui
                    , bodyForStorage ui
                    ]
                }

        Nothing ->
            text ""


{-| The server option reads "Browser" for an anonymous GM,
because their saves land in `localStorage` rather than an
account.
-}
storageSection : Auth.AuthState -> SaveLoadUi -> Html Msg
storageSection auth ui =
    let
        serverLabel =
            case auth of
                Auth.AuthAuthenticated _ ->
                    "Server"

                _ ->
                    "Browser"
    in
    div [ class "save-load__storage" ]
        [ storageButton ui StorageServer serverLabel
        , storageButton ui StorageDevice "Device file"
        ]


storageButton : SaveLoadUi -> SaveStorage -> String -> Html Msg
storageButton ui storage label =
    button
        [ class
            (if ui.storage == storage then
                "action-btn action-btn--blue save-load__storage-btn"

             else
                "action-btn save-load__storage-btn"
            )
        , type_ "button"
        , onClick (SaveLoadStorageSet storage)
        , attribute "aria-pressed"
            (if ui.storage == storage then
                "true"

             else
                "false"
            )
        ]
        [ text label ]


bodyForStorage : SaveLoadUi -> Html Msg
bodyForStorage ui =
    case ui.storage of
        StorageServer ->
            div [ class "save-load__server" ]
                [ saveRow ui
                , savesSection ui
                ]

        StorageDevice ->
            deviceSection ui


{-| Name-and-write. Enter commits, so the common case — type a
name, save — never needs the mouse.
-}
saveRow : SaveLoadUi -> Html Msg
saveRow ui =
    div [ class "save-load__save-row" ]
        [ input
            [ id "save-load-filename"
            , class "save-load__filename"
            , type_ "text"
            , placeholder "Encounter name"
            , value ui.filename
            , maxlength SaveLoadUi.maxNameLength
            , autofocus True
            , onInput SaveLoadFilenameChanged
            , Html.Events.on "keydown" (Util.Keyboard.enterKey SaveLoadSaveSubmit)
            ]
            []
        , button
            [ class "action-btn action-btn--green"
            , type_ "button"
            , onClick SaveLoadSaveSubmit
            , disabled (ui.busy || String.isEmpty (String.trim ui.filename))
            ]
            [ text "Save" ]
        ]


savesSection : SaveLoadUi -> Html Msg
savesSection ui =
    div [ class "save-load__saves" ]
        [ h3 [ class "cond-section__heading" ] [ text "Saved encounters" ]
        , case ui.saves of
            ListLoading ->
                p [ class "empty" ] [ text "Loading…" ]

            ListFailed err ->
                p [ class "empty" ] [ text err ]

            ListLoaded [] ->
                p [ class "empty" ] [ text "No saved encounters yet." ]

            ListLoaded metas ->
                ul [ class "save-load__list" ]
                    (List.map (saveRowItem ui) metas)
        ]


{-| One save. The row is its own rename form while that rename
is in flight, so the name stays where the GM clicked rather than
moving to a field elsewhere.
-}
saveRowItem : SaveLoadUi -> SavedEncounterMeta -> Html Msg
saveRowItem ui meta =
    case ui.renaming of
        Just draft ->
            if draft.original == meta.name then
                renameRow ui draft.draft

            else
                readRow ui meta

        Nothing ->
            readRow ui meta


readRow : SaveLoadUi -> SavedEncounterMeta -> Html Msg
readRow ui meta =
    li [ class "save-load__row" ]
        [ span [ class "save-load__row-name" ] [ text meta.name ]
        , div [ class "save-load__row-actions" ]
            [ rowButton "action-btn action-btn--green"
                (SaveLoadLoadRequested meta.name)
                ui.busy
                Tooltips.saveLoadRowLoad
                "Load"
            , rowButton "action-btn"
                (SaveLoadOverwriteRequested meta.name)
                ui.busy
                Tooltips.saveRowOverwrite
                "Overwrite"
            , rowIcon "action-btn"
                (SaveLoadRenameStart meta.name)
                ui.busy
                Tooltips.saveRowRename
                "Rename"
                "✎"
            , rowIcon "action-btn action-btn--red"
                (SaveLoadDeleteRequested meta.name)
                ui.busy
                Tooltips.saveRowDelete
                "Delete"
                "🗑"
            ]
        ]


rowButton : String -> Msg -> Bool -> String -> String -> Html Msg
rowButton cls msg busy tip label =
    button
        [ class cls
        , type_ "button"
        , onClick msg
        , disabled busy
        , Tooltips.attr tip
        ]
        [ text label ]


rowIcon : String -> Msg -> Bool -> String -> String -> String -> Html Msg
rowIcon cls msg busy tip label glyph =
    button
        [ class cls
        , type_ "button"
        , onClick msg
        , disabled busy
        , Tooltips.attr tip
        , attribute "aria-label" label
        ]
        [ text glyph ]


renameRow : SaveLoadUi -> String -> Html Msg
renameRow ui draft =
    li [ class "save-load__row" ]
        [ input
            [ class "save-load__filename"
            , type_ "text"
            , value draft
            , maxlength SaveLoadUi.maxNameLength
            , autofocus True
            , onInput SaveLoadRenameChange
            , Html.Events.on "keydown" (Util.Keyboard.enterKey SaveLoadRenameSubmit)
            ]
            []
        , div [ class "save-load__row-actions" ]
            [ rowButton "action-btn action-btn--green"
                SaveLoadRenameSubmit
                ui.busy
                Tooltips.saveLoadRenameSubmit
                "Rename"
            , rowButton "action-btn"
                SaveLoadRenameCancel
                False
                Tooltips.saveLoadRenameCancel
                "Cancel"
            ]
        ]


{-| Device storage has no listing to work: a download writes the
file, and the picker reads one back.
-}
deviceSection : SaveLoadUi -> Html Msg
deviceSection ui =
    div [ class "save-load__device" ]
        [ p [ class "cond-section__caption" ]
            [ text "Saves as a file on this device, and reads one back." ]
        , div [ class "note-edit__buttons note-edit__buttons--start" ]
            [ button
                [ class "action-btn action-btn--green"
                , type_ "button"
                , onClick SaveLoadSaveSubmit
                , disabled ui.busy
                ]
                [ text "Download" ]
            , button
                [ class "action-btn action-btn--blue"
                , type_ "button"
                , onClick SaveLoadDeviceImportClick
                , disabled ui.busy
                ]
                [ text "Load from file…" ]
            ]
        ]


confirmBanner : SaveLoadUi -> Html Msg
confirmBanner ui =
    case ui.confirm of
        Just action ->
            let
                ( message, label ) =
                    case action of
                        ConfirmLoad name ->
                            ( "Load \"" ++ name ++ "\"? This replaces the encounter on screen."
                            , "Load"
                            )

                        ConfirmOverwrite name ->
                            ( "Overwrite \"" ++ name ++ "\" with the current encounter?"
                            , "Overwrite"
                            )

                        ConfirmDelete name ->
                            ( "Delete \"" ++ name ++ "\"? This cannot be undone."
                            , "Delete"
                            )
            in
            div [ class "save-load__confirm" ]
                [ span [ class "save-load__confirm-msg" ] [ text message ]
                , div [ class "save-load__row-actions" ]
                    [ rowButton "action-btn"
                        SaveLoadConfirmCancel
                        ui.busy
                        Tooltips.saveLoadConfirmCancel
                        "Cancel"
                    , rowButton "action-btn action-btn--red"
                        SaveLoadConfirmConfirm
                        ui.busy
                        Tooltips.saveLoadConfirmGo
                        label
                    ]
                ]

        Nothing ->
            text ""


errorBanner : SaveLoadUi -> Html Msg
errorBanner ui =
    case ui.error of
        Just err ->
            div [ class "save-load__error" ] [ text err ]

        Nothing ->
            text ""
