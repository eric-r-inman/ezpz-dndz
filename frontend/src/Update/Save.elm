module Update.Save exposing
    ( close
    , confirmCancel
    , confirmConfirm
    , deleteRequested
    , deleteResponse
    , destinationSet
    , filenameChanged
    , listLoaded
    , open
    , overwriteRequested
    , persistResponse
    , renameCancel
    , renameChange
    , renameResponse
    , renameStart
    , renameSubmit
    , submit
    )

{-| Update branches for the Save modal.

The modal owns four interlocking concerns:

  - Pick destination (server vs. device download).
  - Pick / edit the filename.
  - List + manage existing server-side saves (delete / rename /
    overwrite via confirmation prompt).
  - Submit: either upload to server (with overwrite confirm if
    the name exists) or trigger a local file download.

`pushSnapshot` is the shared "we just persisted the encounter,
update the savefile snapshot" path used by both upload-success
and load-success branches; it backs the Reset button.

-}

import Auth
import Dict
import Encounter exposing (Encounter)
import Encounter.Wire
import File.Download
import Http
import Json.Encode as E
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..), SaveDestination(..))
import Ui.Save as SaveUi exposing (ConfirmAction(..), SaveListState(..), SaveUi)
import Ui.Toast exposing (ToastKind(..))
import Update.Toast
import Util.Http


{-| Lens over the SaveUi inside `model.modal`. Other update
modules don't touch save modal state.
-}
withSaveUi : (SaveUi -> SaveUi) -> Model -> Model
withSaveUi =
    Model.mapModal Model.saveLens


open : SaveDestination -> Model -> ( Model, Cmd Msg )
open destination model =
    let
        ( saves, listCmd ) =
            case model.auth of
                Auth.AuthAuthenticated _ ->
                    -- Server saves load async via the listSavesCmd.
                    ( SavesLoading, Encounter.Wire.listSavesCmd SaveListLoaded )

                _ ->
                    -- Anonymous: derive the metadata list from the
                    -- in-memory dict synchronously so the modal
                    -- shows the existing saves on first paint.
                    ( SavesLoaded (localSavesMetas model), Cmd.none )

        baseUi =
            SaveUi.fresh destination model.savedAs

        primedUi =
            { baseUi | saves = saves }
    in
    ( { model
        | modal = Just (ModalSave primedUi)
        , controlMenu = Nothing
      }
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
    ( { model | modal = Nothing }, Cmd.none )


destinationSet : SaveDestination -> Model -> ( Model, Cmd Msg )
destinationSet dest model =
    ( withSaveUi
        (\ui -> { ui | destination = dest, error = Nothing })
        model
    , Cmd.none
    )


filenameChanged : String -> Model -> ( Model, Cmd Msg )
filenameChanged text model =
    ( withSaveUi
        (\ui ->
            { ui
                | filename = String.left SaveUi.maxNameLength text
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
                    SavesLoaded metas

                Err err ->
                    SavesFailed (Util.Http.errorToString err)
    in
    ( withSaveUi (\ui -> { ui | saves = next }) model, Cmd.none )


{-| Submit the modal. Server-mode goes through the
upload pipeline (with a 409 conflict surfacing as an inline
overwrite prompt); device-mode triggers `File.Download.string`
immediately and closes the modal.
-}
submit : Model -> ( Model, Cmd Msg )
submit model =
    case model.modal of
        Just (ModalSave ui) ->
            let
                trimmed =
                    String.trim ui.filename
            in
            if String.isEmpty trimmed then
                ( withSaveUi
                    (\u -> { u | error = Just "Name is required." })
                    model
                , Cmd.none
                )

            else
                case ui.destination of
                    SaveDestinationServer ->
                        case model.auth of
                            Auth.AuthAuthenticated _ ->
                                ( withSaveUi
                                    (\u -> { u | busy = True, error = Nothing })
                                    model
                                , Encounter.Wire.putSaveCmd
                                    (SavePersistResponse trimmed)
                                    { name = trimmed, overwrite = False }
                                    model.encounter
                                )

                            _ ->
                                applyLocalEncounterSave trimmed False model

                    SaveDestinationDevice ->
                        ( { model | modal = Nothing }
                        , downloadEncounter trimmed model.encounter
                        )

        _ ->
            ( model, Cmd.none )


{-| Anonymous equivalent of the server save flow. If the name
already exists and `overwrite` is False, surface the same
confirm-overwrite banner the server's 409 path would (so the
UX matches across auth states). Otherwise insert / replace the
entry in `model.localEncounterSaves` and toast.

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
            ( withSaveUi
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
                        , modal = Nothing
                    }
            in
            Update.Toast.push ToastSuccess ("Saved \"" ++ name ++ "\".") next


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


{-| Server response to PUT. Success: snapshot the just-saved
encounter so Reset has somewhere to go back to, close the modal,
toast the success. 409 conflict: open the overwrite-confirm
banner. Other errors: surface inline.
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
                        , modal = Nothing
                    }
            in
            Update.Toast.push ToastSuccess
                ("Saved \"" ++ name ++ "\".")
                snapshotted

        Err (Http.BadStatus 409) ->
            ( withSaveUi
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
            ( withSaveUi
                (\ui ->
                    { ui
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


{-| The user clicked the overwrite icon next to an existing save
in the list. Bring up the overwrite-confirm banner.
-}
overwriteRequested : String -> Model -> ( Model, Cmd Msg )
overwriteRequested name model =
    ( withSaveUi
        (\ui -> { ui | confirm = Just (ConfirmOverwrite name), error = Nothing })
        model
    , Cmd.none
    )


deleteRequested : String -> Model -> ( Model, Cmd Msg )
deleteRequested name model =
    ( withSaveUi
        (\ui -> { ui | confirm = Just (ConfirmDelete name), error = Nothing })
        model
    , Cmd.none
    )


confirmCancel : Model -> ( Model, Cmd Msg )
confirmCancel model =
    ( withSaveUi (\ui -> { ui | confirm = Nothing }) model, Cmd.none )


{-| Fire the confirmed action. Overwrite re-PUTs with
`?overwrite=true`; delete fires the DELETE call.
-}
confirmConfirm : Model -> ( Model, Cmd Msg )
confirmConfirm model =
    case model.modal of
        Just (ModalSave ui) ->
            case ui.confirm of
                Just (ConfirmOverwrite name) ->
                    case model.auth of
                        Auth.AuthAuthenticated _ ->
                            ( withSaveUi
                                (\u ->
                                    { u
                                        | busy = True
                                        , confirm = Nothing
                                        , error = Nothing
                                    }
                                )
                                model
                            , Encounter.Wire.putSaveCmd
                                (SavePersistResponse name)
                                { name = name, overwrite = True }
                                model.encounter
                            )

                        _ ->
                            applyLocalEncounterSave name True model

                Just (ConfirmDelete name) ->
                    case model.auth of
                        Auth.AuthAuthenticated _ ->
                            ( withSaveUi
                                (\u ->
                                    { u
                                        | busy = True
                                        , confirm = Nothing
                                        , error = Nothing
                                    }
                                )
                                model
                            , Encounter.Wire.deleteSaveCmd
                                (SaveDeleteResponse name)
                                name
                            )

                        _ ->
                            applyLocalEncounterDelete name model

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Anonymous-mode delete: drop the entry from the dict, refresh
the modal's saves list, clear `savedAs` if it matched. The
update wrapper persists the new dict to localStorage.
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
            withSaveUi
                (\ui ->
                    { ui
                        | confirm = Nothing
                        , busy = False
                        , error = Nothing
                        , saves = SavesLoaded (localSavesMetas next)
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
            ( withSaveUi (\ui -> { ui | busy = False }) cleared
            , Encounter.Wire.listSavesCmd SaveListLoaded
            )

        Err err ->
            ( withSaveUi
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
    ( withSaveUi
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
    ( withSaveUi
        (\ui ->
            { ui
                | renaming =
                    Maybe.map
                        (\r -> { r | draft = String.left SaveUi.maxNameLength text })
                        ui.renaming
            }
        )
        model
    , Cmd.none
    )


renameSubmit : Model -> ( Model, Cmd Msg )
renameSubmit model =
    case model.modal of
        Just (ModalSave ui) ->
            case ui.renaming of
                Just { original, draft } ->
                    let
                        trimmed =
                            String.trim draft
                    in
                    if String.isEmpty trimmed || trimmed == original then
                        ( withSaveUi (\u -> { u | renaming = Nothing }) model
                        , Cmd.none
                        )

                    else
                        case model.auth of
                            Auth.AuthAuthenticated _ ->
                                ( withSaveUi
                                    (\u -> { u | busy = True, error = Nothing })
                                    model
                                , Encounter.Wire.renameSaveCmd
                                    (SaveRenameResponse { from = original, to = trimmed })
                                    { from = original, to = trimmed }
                                )

                            _ ->
                                applyLocalRename original trimmed model

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Anonymous-mode rename in the Save modal. Swaps the dict
key, bumps updated\_at, refreshes the saves list.
-}
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
            ( withSaveUi
                (\u ->
                    { u
                        | busy = False
                        , renaming = Nothing
                        , error = Nothing
                        , saves = SavesLoaded (localSavesMetas next)
                    }
                )
                next
            , Cmd.none
            )

        Nothing ->
            ( withSaveUi
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
    ( withSaveUi (\ui -> { ui | renaming = Nothing }) model, Cmd.none )


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
            ( withSaveUi
                (\ui -> { ui | busy = False, renaming = Nothing })
                renamedSavedAs
            , Encounter.Wire.listSavesCmd SaveListLoaded
            )

        Err err ->
            ( withSaveUi
                (\ui ->
                    { ui
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )
