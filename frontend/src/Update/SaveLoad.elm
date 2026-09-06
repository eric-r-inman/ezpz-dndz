module Update.SaveLoad exposing
    ( close
    , confirmCancel
    , confirmConfirm
    , deleteRequested
    , deleteResponse
    , deviceFileChosen
    , deviceFileRead
    , deviceImportClick
    , filenameChanged
    , listLoaded
    , loadRequested
    , open
    , overwriteRequested
    , persistResponse
    , renameCancel
    , renameChange
    , renameResponse
    , renameStart
    , renameSubmit
    , serverResponse
    , storageSet
    , submit
    )

{-| Update branches for the encounter save/load panel.

An anonymous GM's saves live in `localStorage` rather than on
the server, so each handler that talks to the server has a local
counterpart; `model.auth` picks between them.

-}

import Auth
import Dict
import Encounter exposing (Encounter)
import Encounter.Wire
import File exposing (File)
import File.Download
import File.Select
import Http
import Json.Decode as Decode
import Json.Encode as E
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..), SaveStorage(..))
import Task
import Ui.SaveLoad as SaveLoadUi exposing (ConfirmAction(..), ListState(..), SaveLoadUi)
import Ui.Toast exposing (ToastKind(..))
import Update.Toast
import Util.Http


drawerSurface : Model -> Maybe Surface
drawerSurface model =
    Model.drawerGet Model.saveLoadLens model
        |> Maybe.map SurfaceSaveLoad


{-| Other update modules don't touch this panel's state.
-}
withUi : (SaveLoadUi -> SaveLoadUi) -> Model -> Model
withUi =
    Model.mapSurface Model.saveLoadLens


open : Model -> ( Model, Cmd Msg )
open model =
    let
        ( saves, listCmd ) =
            case model.auth of
                Auth.AuthAuthenticated _ ->
                    ( ListLoading, Encounter.Wire.listSavesCmd SaveLoadListLoaded )

                _ ->
                    -- Anonymous: derive the metadata list from the
                    -- in-memory dict synchronously so the panel
                    -- shows the existing saves on first paint.
                    ( ListLoaded (localSavesMetas model), Cmd.none )

        baseUi =
            SaveLoadUi.fresh model.savedAs

        primedUi =
            { baseUi | saves = saves }
    in
    ( Model.toggleDrawer Model.saveLoadLens primedUi model
    , listCmd
    )


{-| Build the same metadata-list shape the server returns from
`GET /api/encounter/saves`, sorted newest first, from the
in-memory localStorage dict.
-}
localSavesMetas : Model -> List Encounter.Wire.SavedEncounterMeta
localSavesMetas model =
    model.localEncounterSaves
        |> Dict.toList
        |> List.map Encounter.Wire.localSaveToMeta
        |> List.sortBy (\m -> -m.updatedAt)


close : Model -> ( Model, Cmd Msg )
close model =
    ( Model.closeDrawer Model.saveLoadLens model, Cmd.none )


storageSet : SaveStorage -> Model -> ( Model, Cmd Msg )
storageSet storage model =
    ( withUi
        (\ui -> { ui | storage = storage, error = Nothing })
        model
    , Cmd.none
    )


filenameChanged : String -> Model -> ( Model, Cmd Msg )
filenameChanged text model =
    ( withUi
        (\ui ->
            { ui
                | filename = String.left SaveLoadUi.maxNameLength text
                , error = Nothing
            }
        )
        model
    , Cmd.none
    )


listLoaded :
    Result Http.Error (List Encounter.Wire.SavedEncounterMeta)
    -> Model
    -> ( Model, Cmd Msg )
listLoaded result model =
    let
        next =
            case result of
                Ok metas ->
                    ListLoaded metas

                Err err ->
                    ListFailed (Util.Http.errorToString err)
    in
    ( withUi (\ui -> { ui | saves = next }) model, Cmd.none )


{-| Submit the panel. A name collision comes back as a 409,
which `persistResponse` turns into the overwrite prompt.
-}
submit : Model -> ( Model, Cmd Msg )
submit model =
    case drawerSurface model of
        Just (SurfaceSaveLoad ui) ->
            let
                trimmed =
                    String.trim ui.filename
            in
            if String.isEmpty trimmed then
                ( withUi
                    (\u -> { u | error = Just "Name is required." })
                    model
                , Cmd.none
                )

            else
                case ui.storage of
                    StorageServer ->
                        case model.auth of
                            Auth.AuthAuthenticated _ ->
                                ( withUi
                                    (\u -> { u | busy = True, error = Nothing })
                                    model
                                , Encounter.Wire.putSaveCmd
                                    (SaveLoadPersistResponse trimmed)
                                    { name = trimmed, overwrite = False }
                                    model.encounter
                                )

                            _ ->
                                applyLocalEncounterSave trimmed False model

                    StorageDevice ->
                        ( Model.closeDrawer Model.saveLoadLens model
                        , downloadEncounter trimmed model.encounter
                        )

        _ ->
            ( model, Cmd.none )


{-| Anonymous equivalent of the server save flow. If the name
already exists and `overwrite` is False, surface the same
confirm-overwrite banner the server's 409 path would, so the UX
matches across auth states.

The update-loop wrapper notices the dict change and writes the
new snapshot to `localStorage.encounterSaves`.

-}
applyLocalEncounterSave : String -> Bool -> Model -> ( Model, Cmd Msg )
applyLocalEncounterSave name overwrite model =
    let
        existing =
            Dict.get name model.localEncounterSaves
    in
    case ( existing, overwrite ) of
        ( Just _, False ) ->
            ( withUi
                (\ui ->
                    { ui
                        | busy = False
                        , confirm = Just (ConfirmOverwrite name)
                        , error = Nothing
                    }
                )
                model
            , Cmd.none
            )

        _ ->
            let
                createdAt =
                    existing
                        |> Maybe.map .createdAt
                        |> Maybe.withDefault model.bootMs

                entry =
                    { encounter = model.encounter
                    , createdAt = createdAt
                    , updatedAt = model.bootMs
                    }

                next =
                    { model
                        | localEncounterSaves =
                            Dict.insert name entry model.localEncounterSaves
                        , savedSnapshot = Just model.encounter
                        , savedAs = Just name
                    }
            in
            Update.Toast.push ToastSuccess
                ("Saved \"" ++ name ++ "\".")
                (Model.closeDrawer Model.saveLoadLens next)


{-| Encode the encounter and trigger a JSON download with the
user's filename. Sanitizes the filename slightly so a name with
a slash doesn't try to navigate paths on the user's box.
-}
downloadEncounter : String -> Encounter -> Cmd Msg
downloadEncounter rawName encounter =
    let
        safe =
            rawName
                |> String.replace "/" "_"
                |> String.replace "\\" "_"

        body =
            encounter
                |> Encounter.Wire.encodeEncounter
                |> E.encode 2
    in
    File.Download.string (safe ++ ".json") "application/json" body


{-| Server response to PUT. A success snapshots the just-saved
encounter, so Reset has somewhere to go back to.
-}
persistResponse : String -> Result Http.Error () -> Model -> ( Model, Cmd Msg )
persistResponse name result model =
    case result of
        Ok () ->
            let
                snapshotted =
                    { model
                        | savedSnapshot = Just model.encounter
                        , savedAs = Just name
                    }
            in
            Update.Toast.push ToastSuccess
                ("Saved \"" ++ name ++ "\".")
                (Model.closeDrawer Model.saveLoadLens snapshotted)

        Err (Http.BadStatus 409) ->
            ( withUi
                (\ui ->
                    { ui
                        | busy = False
                        , confirm = Just (ConfirmOverwrite name)
                        , error = Nothing
                    }
                )
                model
            , Cmd.none
            )

        Err err ->
            ( withUi
                (\ui ->
                    { ui
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


overwriteRequested : String -> Model -> ( Model, Cmd Msg )
overwriteRequested name model =
    ( withUi
        (\ui -> { ui | confirm = Just (ConfirmOverwrite name), error = Nothing })
        model
    , Cmd.none
    )


deleteRequested : String -> Model -> ( Model, Cmd Msg )
deleteRequested name model =
    ( withUi
        (\ui -> { ui | confirm = Just (ConfirmDelete name), error = Nothing })
        model
    , Cmd.none
    )


confirmCancel : Model -> ( Model, Cmd Msg )
confirmCancel model =
    ( withUi (\ui -> { ui | confirm = Nothing }) model, Cmd.none )


confirmConfirm : Model -> ( Model, Cmd Msg )
confirmConfirm model =
    case drawerSurface model of
        Just (SurfaceSaveLoad ui) ->
            case ui.confirm of
                Just (ConfirmLoad name) ->
                    case model.auth of
                        Auth.AuthAuthenticated _ ->
                            ( withUi
                                (\u ->
                                    { u
                                        | busy = True
                                        , confirm = Nothing
                                        , error = Nothing
                                    }
                                )
                                model
                            , Encounter.Wire.getSaveCmd
                                (SaveLoadServerResponse name)
                                name
                            )

                        _ ->
                            applyLocalLoad name model

                Just (ConfirmOverwrite name) ->
                    case model.auth of
                        Auth.AuthAuthenticated _ ->
                            ( withUi
                                (\u ->
                                    { u
                                        | busy = True
                                        , confirm = Nothing
                                        , error = Nothing
                                    }
                                )
                                model
                            , Encounter.Wire.putSaveCmd
                                (SaveLoadPersistResponse name)
                                { name = name, overwrite = True }
                                model.encounter
                            )

                        _ ->
                            applyLocalEncounterSave name True model

                Just (ConfirmDelete name) ->
                    case model.auth of
                        Auth.AuthAuthenticated _ ->
                            ( withUi
                                (\u ->
                                    { u
                                        | busy = True
                                        , confirm = Nothing
                                        , error = Nothing
                                    }
                                )
                                model
                            , Encounter.Wire.deleteSaveCmd
                                (SaveLoadDeleteResponse name)
                                name
                            )

                        _ ->
                            applyLocalEncounterDelete name model

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Anonymous-mode delete. The update wrapper persists the new
dict to localStorage.
-}
applyLocalEncounterDelete : String -> Model -> ( Model, Cmd Msg )
applyLocalEncounterDelete name model =
    let
        cleared =
            if model.savedAs == Just name then
                { model | savedAs = Nothing }

            else
                model

        next =
            { cleared
                | localEncounterSaves =
                    Dict.remove name model.localEncounterSaves
            }

        refreshed =
            withUi
                (\ui ->
                    { ui
                        | confirm = Nothing
                        , busy = False
                        , error = Nothing
                        , saves = ListLoaded (localSavesMetas next)
                    }
                )
                next
    in
    ( refreshed, Cmd.none )


deleteResponse : String -> Result Http.Error () -> Model -> ( Model, Cmd Msg )
deleteResponse name result model =
    case result of
        Ok () ->
            let
                cleared =
                    if model.savedAs == Just name then
                        { model | savedAs = Nothing }

                    else
                        model
            in
            ( withUi (\ui -> { ui | busy = False }) cleared
            , Encounter.Wire.listSavesCmd SaveLoadListLoaded
            )

        Err err ->
            ( withUi
                (\ui ->
                    { ui
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


renameStart : String -> Model -> ( Model, Cmd Msg )
renameStart name model =
    ( withUi
        (\ui ->
            { ui
                | renaming = Just { original = name, draft = name }
                , confirm = Nothing
                , error = Nothing
            }
        )
        model
    , Cmd.none
    )


renameChange : String -> Model -> ( Model, Cmd Msg )
renameChange text model =
    ( withUi
        (\ui ->
            { ui
                | renaming =
                    Maybe.map
                        (\r -> { r | draft = String.left SaveLoadUi.maxNameLength text })
                        ui.renaming
            }
        )
        model
    , Cmd.none
    )


renameSubmit : Model -> ( Model, Cmd Msg )
renameSubmit model =
    case drawerSurface model of
        Just (SurfaceSaveLoad ui) ->
            case ui.renaming of
                Just { original, draft } ->
                    let
                        trimmed =
                            String.trim draft
                    in
                    if String.isEmpty trimmed || trimmed == original then
                        ( withUi (\u -> { u | renaming = Nothing }) model
                        , Cmd.none
                        )

                    else
                        case model.auth of
                            Auth.AuthAuthenticated _ ->
                                ( withUi
                                    (\u -> { u | busy = True, error = Nothing })
                                    model
                                , Encounter.Wire.renameSaveCmd
                                    (SaveLoadRenameResponse { from = original, to = trimmed })
                                    { from = original, to = trimmed }
                                )

                            _ ->
                                applyLocalRename original trimmed model

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


applyLocalRename : String -> String -> Model -> ( Model, Cmd Msg )
applyLocalRename from to model =
    case Dict.get from model.localEncounterSaves of
        Just entry ->
            let
                bumped =
                    { entry | updatedAt = model.bootMs }

                renamedSavedAs =
                    if model.savedAs == Just from then
                        { model | savedAs = Just to }

                    else
                        model

                nextSaves =
                    model.localEncounterSaves
                        |> Dict.remove from
                        |> Dict.insert to bumped

                next =
                    { renamedSavedAs | localEncounterSaves = nextSaves }
            in
            ( withUi
                (\u ->
                    { u
                        | busy = False
                        , renaming = Nothing
                        , error = Nothing
                        , saves = ListLoaded (localSavesMetas next)
                    }
                )
                next
            , Cmd.none
            )

        Nothing ->
            ( withUi
                (\u ->
                    { u
                        | busy = False
                        , renaming = Nothing
                        , error = Just "That save no longer exists."
                    }
                )
                model
            , Cmd.none
            )


renameCancel : Model -> ( Model, Cmd Msg )
renameCancel model =
    ( withUi (\ui -> { ui | renaming = Nothing }) model, Cmd.none )


renameResponse :
    { from : String, to : String }
    -> Result Http.Error ()
    -> Model
    -> ( Model, Cmd Msg )
renameResponse { from, to } result model =
    case result of
        Ok () ->
            let
                renamedSavedAs =
                    if model.savedAs == Just from then
                        { model | savedAs = Just to }

                    else
                        model
            in
            ( withUi
                (\ui -> { ui | busy = False, renaming = Nothing })
                renamedSavedAs
            , Encounter.Wire.listSavesCmd SaveLoadListLoaded
            )

        Err err ->
            ( withUi
                (\ui ->
                    { ui
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


loadRequested : String -> Model -> ( Model, Cmd Msg )
loadRequested name model =
    ( withUi
        (\ui -> { ui | confirm = Just (ConfirmLoad name), error = Nothing })
        model
    , Cmd.none
    )


{-| Anonymous-mode load. The name should always resolve — the
list is rendered from the same dict — so a miss surfaces as an
error rather than passing quietly.
-}
applyLocalLoad : String -> Model -> ( Model, Cmd Msg )
applyLocalLoad name model =
    case Dict.get name model.localEncounterSaves of
        Just save ->
            let
                encounter =
                    save.encounter

                fresh =
                    { encounter | round = 1, activeName = "" }

                next =
                    { model
                        | encounter = fresh
                        , savedSnapshot = Just fresh
                        , savedAs = Just name
                    }
            in
            Update.Toast.push ToastSuccess
                ("Loaded \"" ++ name ++ "\".")
                (Model.closeDrawer Model.saveLoadLens next)

        Nothing ->
            ( withUi
                (\u ->
                    { u
                        | busy = False
                        , confirm = Nothing
                        , error = Just "That save no longer exists."
                    }
                )
                model
            , Cmd.none
            )


{-| Server returned the encounter body. Replace the live
encounter and snapshot it as the savefile state, so the Save
button reads clean until the roster changes. Force round 1 with
no active creature so the GM lands in pre-combat mode and
starts the fight when ready.
-}
serverResponse : String -> Result Http.Error Encounter -> Model -> ( Model, Cmd Msg )
serverResponse name result model =
    case result of
        Ok encounter ->
            let
                fresh =
                    { encounter | round = 1, activeName = "" }

                next =
                    { model
                        | encounter = fresh
                        , savedSnapshot = Just fresh
                        , savedAs = Just name
                    }
            in
            Update.Toast.push ToastSuccess
                ("Loaded \"" ++ name ++ "\".")
                (Model.closeDrawer Model.saveLoadLens next)

        Err err ->
            ( withUi
                (\ui ->
                    { ui
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


deviceImportClick : Model -> ( Model, Cmd Msg )
deviceImportClick model =
    ( withUi (\ui -> { ui | error = Nothing }) model
    , File.Select.file [ "application/json", "text/plain" ] SaveLoadDeviceFileChosen
    )


deviceFileChosen : File -> Model -> ( Model, Cmd Msg )
deviceFileChosen file model =
    ( model, Task.perform SaveLoadDeviceFileRead (File.toString file) )


{-| Decode the file the GM picked. A success forces pre-combat
mode, for the reason `serverResponse` gives.
-}
deviceFileRead : String -> Model -> ( Model, Cmd Msg )
deviceFileRead raw model =
    case Decode.decodeString Encounter.Wire.decodeEncounter raw of
        Ok encounter ->
            let
                fresh =
                    { encounter | round = 1, activeName = "" }

                next =
                    { model
                        | encounter = fresh
                        , savedSnapshot = Just fresh
                        , savedAs = Nothing
                    }
            in
            Update.Toast.push ToastSuccess
                "Loaded encounter from file."
                (Model.closeDrawer Model.saveLoadLens next)

        Err err ->
            ( withUi
                (\ui ->
                    { ui
                        | error =
                            Just ("Couldn't parse file: " ++ Decode.errorToString err)
                    }
                )
                model
            , Cmd.none
            )
