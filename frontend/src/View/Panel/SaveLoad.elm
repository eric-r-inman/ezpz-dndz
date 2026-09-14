module View.Panel.SaveLoad exposing (view)

{-| Encounter save/load panel; the chrome comes from
`View.Panel`.
-}

import Auth
import Encounter
import Encounter.Wire exposing (SavedEncounterMeta)
import Html exposing (Html, button, div, input, li, p, span, text, ul)
import Html.Attributes
    exposing
        ( attribute
        , autofocus
        , class
        , disabled
        , for
        , id
        , maxlength
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
import View.Inline.ApplyButton as ApplyButton
import View.Inline.Field as Field
import View.Panel
import View.Tooltips as Tooltips


view : View.Panel.Header -> Model -> Html Msg
view header model =
    case Model.drawerGet Model.saveLoadLens model of
        Just ui ->
            View.Panel.view
                { title = "Save/Load Encounter"
                , titleTrail =
                    View.Panel.titleMarkIf
                        (Encounter.rosterDirty model.encounter model.savedSnapshot)
                , subtitle = Nothing
                , header = header
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


{-| The server option names the browser for an anonymous GM,
because their saves land in `localStorage` rather than an
account.
-}
storageSection : Auth.AuthState -> SaveLoadUi -> Html Msg
storageSection auth ui =
    let
        serverLabel =
            case auth of
                Auth.AuthAuthenticated _ ->
                    "This server"

                _ ->
                    "This browser"
    in
    div [ class "save-load__storage-block" ]
        [ span [ class "cond-label" ] [ text "Save this encounter to:" ]
        , div [ class "save-load__storage" ]
            [ storageButton ui StorageServer serverLabel
            , storageButton ui StorageDevice "This device"
            ]
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
    div [ class "save-load__save" ]
        [ div [ class "cond-row" ]
            [ Html.label
                [ for "save-load-filename", class "cond-label" ]
                [ text "Encounter Name:" ]
            , input
                [ id "save-load-filename"
                , class "cond-input cond-input--grow"
                , type_ "text"
                , value ui.filename
                , maxlength SaveLoadUi.maxNameLength
                , autofocus True
                , onInput SaveLoadFilenameChanged
                , Html.Events.on "keydown" (Util.Keyboard.enterKey SaveLoadSaveSubmit)
                ]
                []
            ]
        , div [ class "note-edit__buttons note-edit__buttons--start" ]
            [ button
                [ class "action-btn action-btn--green"
                , type_ "button"
                , onClick SaveLoadSaveSubmit
                , disabled (ui.busy || String.isEmpty (String.trim ui.filename))
                ]
                [ text "Save" ]
            ]
        ]


{-| The saves fold away until the GM asks for them. A save is
picked before anything is done to it, so its actions sit once
under the list rather than on every row.
-}
savesSection : SaveLoadUi -> Html Msg
savesSection ui =
    div [ class "save-load__saves" ]
        (Field.foldHead
            { open = ui.savesOpen
            , title = "Saved Encounters" ++ savesCount ui.saves
            , msg = SaveLoadSavesToggle
            , trail = []
            }
            :: (if ui.savesOpen then
                    savesBody ui

                else
                    []
               )
        )


savesCount : ListState -> String
savesCount saves =
    case saves of
        ListLoaded metas ->
            " (" ++ String.fromInt (List.length metas) ++ ")"

        _ ->
            ""


savesBody : SaveLoadUi -> List (Html Msg)
savesBody ui =
    case ui.saves of
        ListLoading ->
            [ p [ class "empty" ] [ text "Loading…" ] ]

        ListFailed err ->
            [ p [ class "empty" ] [ text err ] ]

        ListLoaded [] ->
            [ p [ class "empty" ] [ text "No saved encounters yet." ] ]

        ListLoaded metas ->
            let
                picked =
                    pickedSave ui metas
            in
            [ ul
                [ class "quick-add__list quick-add__list--docked"
                , attribute "role" "listbox"
                ]
                (List.map (saveListRow ui picked) metas)
            , actions ui picked
            ]


{-| The picked save, while the listing still holds it: a save
deleted or renamed away leaves nothing picked.
-}
pickedSave : SaveLoadUi -> List SavedEncounterMeta -> Maybe String
pickedSave ui metas =
    ui.selected
        |> Maybe.andThen
            (\name ->
                if List.any (\meta -> meta.name == name) metas then
                    Just name

                else
                    Nothing
            )


{-| One save. The row being renamed becomes its own name field,
so the name is edited where the GM picked it.
-}
saveListRow : SaveLoadUi -> Maybe String -> SavedEncounterMeta -> Html Msg
saveListRow ui picked meta =
    case ui.renaming of
        Just draft ->
            if draft.original == meta.name then
                renameRow draft.draft

            else
                readRow picked meta

        Nothing ->
            readRow picked meta


readRow : Maybe String -> SavedEncounterMeta -> Html Msg
readRow picked meta =
    let
        isPicked =
            picked == Just meta.name
    in
    li
        [ class
            (if isPicked then
                "quick-add__row quick-add__row--picked"

             else
                "quick-add__row"
            )
        , onClick (SaveLoadSelect meta.name)
        , attribute "role" "option"
        , attribute "aria-selected"
            (if isPicked then
                "true"

             else
                "false"
            )
        ]
        [ span [ class "quick-add__name" ] [ text meta.name ] ]


renameRow : String -> Html Msg
renameRow draft =
    li [ class "quick-add__row quick-add__row--picked save-load__row--renaming" ]
        [ input
            [ class "cond-input cond-input--grow"
            , type_ "text"
            , value draft
            , maxlength SaveLoadUi.maxNameLength
            , autofocus True
            , onInput SaveLoadRenameChange
            , Html.Events.on "keydown" (Util.Keyboard.enterKey SaveLoadRenameSubmit)
            , attribute "aria-label" "New name for the save"
            ]
            []
        ]


{-| What can be done to the picked save. With nothing picked the
buttons stay where they are but dead, and say why.
-}
actions : SaveLoadUi -> Maybe String -> Html Msg
actions ui picked =
    div [ class "note-edit__buttons note-edit__buttons--start" ]
        (case ui.renaming of
            Just _ ->
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

            Nothing ->
                let
                    name =
                        Maybe.withDefault "" picked

                    enabled =
                        picked /= Nothing && not ui.busy

                    tip actionTip =
                        if picked == Nothing then
                            Tooltips.saveLoadPickFirst

                        else
                            actionTip
                in
                [ ApplyButton.view
                    { enabled = enabled
                    , cls = "action-btn action-btn--green"
                    , msg = SaveLoadLoadRequested name
                    , tip = tip Tooltips.saveLoadRowLoad
                    , label = "Load"
                    }
                , ApplyButton.view
                    { enabled = enabled
                    , cls = "action-btn action-btn--orange"
                    , msg = SaveLoadOverwriteRequested name
                    , tip = tip Tooltips.saveRowOverwrite
                    , label = "Overwrite"
                    }
                , ApplyButton.view
                    { enabled = enabled
                    , cls = "action-btn action-btn--blue"
                    , msg = SaveLoadRenameStart name
                    , tip = tip Tooltips.saveRowRename
                    , label = "Rename"
                    }
                , ApplyButton.icon
                    { enabled = enabled
                    , cls = "action-btn action-btn--red"
                    , msg = SaveLoadDeleteRequested name
                    , tip = tip Tooltips.saveRowDelete
                    , label = "Delete"
                    , glyph = "🗑"
                    }
                ]
        )


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
            div [ class "cond-section__caption cond-section__caption--danger" ] [ text err ]

        Nothing ->
            text ""
