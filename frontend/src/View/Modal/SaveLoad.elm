module View.Modal.SaveLoad exposing (view)

{-| The two modals the Encounter menu opens.

Saving asks where first, because the two destinations want
different things: a file needs nowhere to put it, and the server
needs an account and a name. Loading asks the same question by
offering both sources at once — the account's saves as a list,
and the GM's own machine behind a file picker.

-}

import Auth
import Encounter.Wire exposing (SavedEncounterMeta)
import Html exposing (Html, a, button, div, input, li, p, span, text, ul)
import Html.Attributes
    exposing
        ( attribute
        , autofocus
        , class
        , disabled
        , for
        , href
        , id
        , maxlength
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..), SaveStorage(..))
import Ui.SaveLoad as SaveLoadUi
    exposing
        ( ConfirmAction(..)
        , ListState(..)
        , Purpose(..)
        , SaveLoadUi
        )
import Util.Keyboard
import View.Inline.ApplyButton as ApplyButton
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.surface of
        Just (SurfaceSaveLoad ui) ->
            View.Modal.view
                { close = SaveLoadClose
                , noOp = NoOp
                , title =
                    case ui.purpose of
                        ForSave ->
                            "Save Encounter"

                        ForLoad ->
                            "Load Encounter"
                , extraClass = "modal--save"
                , chrome = model.modalChrome
                , body =
                    [ confirmBanner ui
                    , errorBanner ui
                    , case ui.purpose of
                        ForSave ->
                            saveBody model.auth ui

                        ForLoad ->
                            loadBody model.auth ui
                    ]
                }

        _ ->
            text ""



-- SAVE


saveBody : Auth.AuthState -> SaveLoadUi -> Html Msg
saveBody auth ui =
    div [ class "save-load__server" ]
        [ div [ class "save-load__storage-block" ]
            [ span [ class "cond-label" ] [ text "Save this encounter to:" ]
            , div [ class "save-load__storage" ]
                [ storageButton ui StorageDevice "A file on this device"
                , storageButton ui StorageServer "This server"
                ]
            ]
        , case ui.storage of
            StorageDevice ->
                downloadSection ui

            StorageServer ->
                serverSaveSection auth ui
        ]


downloadSection : SaveLoadUi -> Html Msg
downloadSection ui =
    div [ class "save-load__device" ]
        [ p [ class "cond-section__caption" ]
            [ text "Writes the encounter to your downloads as a JSON file." ]
        , div [ class "cond-row" ]
            [ Html.label [ for "save-load-filename", class "cond-label" ]
                [ text "File name:" ]
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
                , disabled ui.busy
                ]
                [ text "Download" ]
            ]
        ]


serverSaveSection : Auth.AuthState -> SaveLoadUi -> Html Msg
serverSaveSection auth ui =
    case auth of
        Auth.AuthAuthenticated _ ->
            div [ class "save-load__save" ]
                [ div [ class "cond-row" ]
                    [ Html.label [ for "save-load-filename", class "cond-label" ]
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
                , overwriteHint ui
                ]

        _ ->
            signInNotice "Saving to the server keeps an encounter with your account, on any device you sign in from."


{-| A heads-up that a name already on the server is an overwrite,
shown only once there is a save to collide with.
-}
overwriteHint : SaveLoadUi -> Html Msg
overwriteHint ui =
    case ui.saves of
        ListLoaded (_ :: _) ->
            p [ class "cond-section__caption" ]
                [ text "Saving under a name you already have will ask before replacing it." ]

        _ ->
            text ""



-- LOAD


loadBody : Auth.AuthState -> SaveLoadUi -> Html Msg
loadBody auth ui =
    div [ class "save-load__server" ]
        [ div [ class "save-load__device" ]
            [ p [ class "cond-section__caption" ]
                [ text "Reads an encounter back from a file on this device." ]
            , div [ class "note-edit__buttons note-edit__buttons--start" ]
                [ button
                    [ class "action-btn action-btn--blue"
                    , type_ "button"
                    , onClick SaveLoadDeviceImportClick
                    , disabled ui.busy
                    ]
                    [ text "Load from file…" ]
                ]
            ]
        , div [ class "save-load__saves" ]
            (span [ class "cond-label" ] [ text ("Saved on this server" ++ savesCount ui.saves) ]
                :: serverLoadSection auth ui
            )
        ]


serverLoadSection : Auth.AuthState -> SaveLoadUi -> List (Html Msg)
serverLoadSection auth ui =
    case auth of
        Auth.AuthAuthenticated _ ->
            savesBody ui

        _ ->
            [ signInNotice "Sign in to keep encounters on the server and load them from any device." ]


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



-- SHARED


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


{-| What an anonymous GM sees where an account's saves would be,
with the way to get one.
-}
signInNotice : String -> Html Msg
signInNotice why =
    div [ class "save-load__device" ]
        [ p [ class "cond-section__caption" ] [ text why ]
        , a [ class "action-btn action-btn--blue", href "/login" ] [ text "Sign in" ]
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
