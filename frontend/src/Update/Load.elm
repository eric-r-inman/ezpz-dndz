module Update.Load exposing
    ( close
    , confirmCancel
    , confirmConfirm
    , deleteRequested
    , deleteResponse
    , fromDeviceClick
    , fromDeviceFileChosen
    , fromDeviceFileRead
    , fromServerRequested
    , listLoaded
    , open
    , renameCancel
    , renameChange
    , renameResponse
    , renameStart
    , renameSubmit
    , serverResponse
    )

{-| Update branches for the Load modal.

Loading is destructive — the chosen save replaces whatever is in
`model.encounter` — so every load goes through the inline
confirmation banner first. Rename / delete affordances mirror
the Save modal's because they hit the same server endpoints.

The "load from device" path is a small sub-flow: open the
browser file picker, read the chosen file as text, JSON-decode
it; success replaces the encounter in place (no confirm, since
the user explicitly picked the file from disk), failure raises
a toast.

-}

import Encounter exposing (Encounter)
import Encounter.Wire
import File exposing (File)
import File.Select
import Http
import Json.Decode as Decode
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Task
import Ui.Load as LoadUi exposing (ConfirmAction(..), LoadListState(..), LoadUi)
import Ui.Toast exposing (ToastKind(..))
import Update.Toast
import Util.Http


withLoadUi : (LoadUi -> LoadUi) -> Model -> Model
withLoadUi =
    Model.mapModal Model.loadLens


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model | modal = Just (ModalLoad LoadUi.fresh), controlMenu = Nothing }
    , Encounter.Wire.listSavesCmd LoadListLoaded
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


listLoaded :
    Result Http.Error (List Encounter.Wire.SavedEncounterMeta)
    -> Model
    -> ( Model, Cmd Msg )
listLoaded result model =
    let
        next =
            case result of
                Ok metas ->
                    LoadsLoaded metas

                Err err ->
                    LoadsFailed (Util.Http.errorToString err)
    in
    ( withLoadUi (\ui -> { ui | saves = next }) model, Cmd.none )


fromServerRequested : String -> Model -> ( Model, Cmd Msg )
fromServerRequested name model =
    ( withLoadUi
        (\ui -> { ui | confirm = Just (ConfirmLoad name), error = Nothing })
        model
    , Cmd.none
    )


confirmCancel : Model -> ( Model, Cmd Msg )
confirmCancel model =
    ( withLoadUi (\ui -> { ui | confirm = Nothing }) model, Cmd.none )


confirmConfirm : Model -> ( Model, Cmd Msg )
confirmConfirm model =
    case model.modal of
        Just (ModalLoad ui) ->
            case ui.confirm of
                Just (ConfirmLoad name) ->
                    ( withLoadUi
                        (\u ->
                            { u
                                | busy = True
                                , confirm = Nothing
                                , error = Nothing
                            }
                        )
                        model
                    , Encounter.Wire.getSaveCmd
                        (LoadServerResponse name)
                        name
                    )

                Just (ConfirmDelete name) ->
                    ( withLoadUi
                        (\u ->
                            { u
                                | busy = True
                                , confirm = Nothing
                                , error = Nothing
                            }
                        )
                        model
                    , Encounter.Wire.deleteSaveCmd
                        (LoadDeleteResponse name)
                        name
                    )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Server returned the encounter body. Replace the live
encounter and snapshot it as the savefile state (so Reset
returns to it). Force `round = 0` with no active creature so
the GM lands in pre-combat mode and clicks Run when ready.
The snapshot keeps the same shape so Reset returns to the
same pre-combat state.
-}
serverResponse : String -> Result Http.Error Encounter -> Model -> ( Model, Cmd Msg )
serverResponse name result model =
    case result of
        Ok encounter ->
            let
                fresh =
                    { encounter | round = 0, activeName = "" }

                next =
                    { model
                        | encounter = fresh
                        , savedSnapshot = Just fresh
                        , savedAs = Just name
                        , modal = Nothing
                    }
            in
            Update.Toast.push ToastSuccess
                ("Loaded \"" ++ name ++ "\".")
                next

        Err err ->
            ( withLoadUi
                (\ui ->
                    { ui
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


deleteRequested : String -> Model -> ( Model, Cmd Msg )
deleteRequested name model =
    ( withLoadUi
        (\ui -> { ui | confirm = Just (ConfirmDelete name), error = Nothing })
        model
    , Cmd.none
    )


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
            ( withLoadUi (\ui -> { ui | busy = False }) cleared
            , Encounter.Wire.listSavesCmd LoadListLoaded
            )

        Err err ->
            ( withLoadUi
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
    ( withLoadUi
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
    ( withLoadUi
        (\ui ->
            { ui
                | renaming =
                    Maybe.map
                        (\r -> { r | draft = String.left LoadUi.maxNameLength text })
                        ui.renaming
            }
        )
        model
    , Cmd.none
    )


renameSubmit : Model -> ( Model, Cmd Msg )
renameSubmit model =
    case model.modal of
        Just (ModalLoad ui) ->
            case ui.renaming of
                Just { original, draft } ->
                    let
                        trimmed =
                            String.trim draft
                    in
                    if String.isEmpty trimmed || trimmed == original then
                        ( withLoadUi (\u -> { u | renaming = Nothing }) model
                        , Cmd.none
                        )

                    else
                        ( withLoadUi
                            (\u -> { u | busy = True, error = Nothing })
                            model
                        , Encounter.Wire.renameSaveCmd
                            (LoadRenameResponse { from = original, to = trimmed })
                            { from = original, to = trimmed }
                        )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


renameCancel : Model -> ( Model, Cmd Msg )
renameCancel model =
    ( withLoadUi (\ui -> { ui | renaming = Nothing }) model, Cmd.none )


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
            ( withLoadUi
                (\ui -> { ui | busy = False, renaming = Nothing })
                renamedSavedAs
            , Encounter.Wire.listSavesCmd LoadListLoaded
            )

        Err err ->
            ( withLoadUi
                (\ui ->
                    { ui
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


fromDeviceClick : Model -> ( Model, Cmd Msg )
fromDeviceClick model =
    ( withLoadUi (\ui -> { ui | error = Nothing })
        { model | controlMenu = Nothing }
    , File.Select.file [ "application/json", "text/plain" ] LoadFromDeviceFileChosen
    )


fromDeviceFileChosen : File -> Model -> ( Model, Cmd Msg )
fromDeviceFileChosen file model =
    ( model, Task.perform LoadFromDeviceFileRead (File.toString file) )


{-| Decode the file the user picked. On parse success we replace
the encounter (forcing pre-combat mode — see `serverResponse`)
and close the modal; on failure we keep the modal open with an
inline error.
-}
fromDeviceFileRead : String -> Model -> ( Model, Cmd Msg )
fromDeviceFileRead raw model =
    case Decode.decodeString Encounter.Wire.decodeEncounter raw of
        Ok encounter ->
            let
                fresh =
                    { encounter | round = 0, activeName = "" }

                next =
                    { model
                        | encounter = fresh
                        , savedSnapshot = Just fresh
                        , savedAs = Nothing
                        , modal = Nothing
                    }
            in
            Update.Toast.push ToastSuccess "Loaded encounter from file." next

        Err err ->
            ( withLoadUi
                (\ui ->
                    { ui
                        | error =
                            Just ("Couldn't parse file: " ++ Decode.errorToString err)
                    }
                )
                model
            , Cmd.none
            )
