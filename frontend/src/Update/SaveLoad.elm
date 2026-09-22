module Update.SaveLoad exposing
    ( confirmCancel
    , confirmConfirm
    , deleteRequested
    , deleteResponse
    , deviceFileChosen
    , deviceFileRead
    , deviceImportClick
    , dismiss
    , filenameChanged
    , listLoaded
    , loadRequested
    , open
    , persistResponse
    , renameCancel
    , renameChange
    , renameResponse
    , renameStart
    , renameSubmit
    , select
    , serverResponse
    , storageSet
    , submit
    )

{-| Update branches for the two encounter save/load modals.

A named save belongs to the account that owns it, so every path
here that names a save wants a signed-in GM. The one errand that
does not is the file on the GM's own machine, which needs no
account at either end.

-}

import Auth
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


modalUi : Model -> Maybe SaveLoadUi
modalUi model =
    model.surface |> Maybe.andThen Model.saveLoadLens.extract


{-| Other update modules don't touch this modal's state.
-}
withUi : (SaveLoadUi -> SaveLoadUi) -> Model -> Model
withUi =
    Model.mapSurface Model.saveLoadLens


{-| Done with the modal. A save or a load that lands ends here,
so neither leaves the GM to dismiss it by hand.
-}
close : Model -> Model
close model =
    { model | surface = Nothing }


{-| Open one of the two modals, with its listing already on the
way. The Save modal warns from it that a name may already be
taken; the Load modal is the listing.
-}
open : SaveLoadUi.Purpose -> Model -> ( Model, Cmd Msg )
open purpose model =
    let
        fresh =
            SaveLoadUi.fresh purpose
    in
    primeList
        { model
            | surface =
                Just
                    (SurfaceSaveLoad
                        -- Land on the destination this session
                        -- can actually use.  An anonymous GM
                        -- would otherwise open on a sign-in wall
                        -- when a file would have done.
                        (case model.auth of
                            Auth.AuthAuthenticated _ ->
                                fresh

                            _ ->
                                { fresh | storage = StorageDevice }
                        )
                    )
            , encounterMenuOpen = False
        }


{-| Dismiss the modal without finishing its errand.
-}
dismiss : Model -> ( Model, Cmd Msg )
dismiss model =
    ( close model, Cmd.none )


{-| Ready a modal that has just come on screen: the filename
field takes the name the encounter was last saved under, so
re-saving doesn't make the GM retype it, and the listing is
fetched.
-}
primeList : Model -> ( Model, Cmd Msg )
primeList model =
    let
        primed saves =
            withUi
                (\ui ->
                    { ui
                        | saves = saves
                        , filename = Maybe.withDefault ui.filename model.savedAs
                    }
                )
                model
    in
    case model.auth of
        Auth.AuthAuthenticated _ ->
            ( primed ListLoading
            , Encounter.Wire.listSavesCmd SaveLoadListLoaded
            )

        _ ->
            ( primed (ListLoaded []), Cmd.none )


storageSet : SaveStorage -> Model -> ( Model, Cmd Msg )
storageSet storage model =
    ( withUi
        (\ui -> { ui | storage = storage, error = Nothing })
        model
    , Cmd.none
    )


{-| Pick the save the list's actions work on. Picking a different
one drops a rename or confirmation begun on the last, which would
otherwise land on a save the GM has moved away from.
-}
select : String -> Model -> ( Model, Cmd Msg )
select name model =
    ( withUi
        (\ui ->
            if ui.selected == Just name then
                ui

            else
                { ui
                    | selected = Just name
                    , renaming = Nothing
                    , confirm = Nothing
                    , error = Nothing
                }
        )
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


{-| Submit the Save modal. A download needs no name — an unnamed
encounter downloads under a default — so only the server path
insists on one. A name collision there comes back as a 409, which
`persistResponse` turns into the overwrite prompt.
-}
submit : Model -> ( Model, Cmd Msg )
submit model =
    case modalUi model of
        Just ui ->
            case ui.storage of
                StorageDevice ->
                    ( close model
                    , downloadEncounter (downloadName ui model) model.encounter
                    )

                StorageServer ->
                    submitToServer (String.trim ui.filename) model

        _ ->
            ( model, Cmd.none )


downloadName : SaveLoadUi -> Model -> String
downloadName ui model =
    [ String.trim ui.filename, Maybe.withDefault "" model.savedAs ]
        |> List.filter (not << String.isEmpty)
        |> List.head
        |> Maybe.withDefault "encounter"


submitToServer : String -> Model -> ( Model, Cmd Msg )
submitToServer trimmed model =
    case model.auth of
        Auth.AuthAuthenticated _ ->
            if String.isEmpty trimmed then
                ( withUi (\u -> { u | error = Just "Name is required." }) model
                , Cmd.none
                )

            else
                ( withUi (\u -> { u | busy = True, error = Nothing }) model
                , Encounter.Wire.putSaveCmd
                    (SaveLoadPersistResponse trimmed)
                    { name = trimmed, overwrite = False }
                    model.encounter
                )

        _ ->
            ( withUi (\u -> { u | error = Just signInRequired }) model
            , Cmd.none
            )


{-| What every account-gated path says when there is no account.
-}
signInRequired : String
signInRequired =
    "Sign in to use encounter saves on this server."


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


{-| Server response to PUT. A success records the name the
encounter is now saved under.
-}
persistResponse : String -> Result Http.Error () -> Model -> ( Model, Cmd Msg )
persistResponse name result model =
    case result of
        Ok () ->
            let
                named =
                    { model
                        | savedAs = Just name
                    }
            in
            Update.Toast.push ToastSuccess
                ("Saved \"" ++ name ++ "\".")
                (close named)

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


{-| Go through with the pending action.
-}
confirmConfirm : Model -> ( Model, Cmd Msg )
confirmConfirm model =
    case ( modalUi model, model.auth ) of
        ( Just ui, Auth.AuthAuthenticated _ ) ->
            let
                started cmd =
                    ( withUi
                        (\u -> { u | busy = True, confirm = Nothing, error = Nothing })
                        model
                    , cmd
                    )
            in
            case ui.confirm of
                Just (ConfirmLoad name) ->
                    started (Encounter.Wire.getSaveCmd (SaveLoadServerResponse name) name)

                Just (ConfirmOverwrite name) ->
                    started
                        (Encounter.Wire.putSaveCmd
                            (SaveLoadPersistResponse name)
                            { name = name, overwrite = True }
                            model.encounter
                        )

                Just (ConfirmDelete name) ->
                    started (Encounter.Wire.deleteSaveCmd (SaveLoadDeleteResponse name) name)

                Nothing ->
                    ( model, Cmd.none )

        ( Just _, _ ) ->
            ( withUi (\u -> { u | confirm = Nothing, error = Just signInRequired }) model
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


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
    case modalUi model of
        Just ui ->
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
                                ( withUi
                                    (\u -> { u | renaming = Nothing, error = Just signInRequired })
                                    model
                                , Cmd.none
                                )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


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
                (\ui -> { ui | busy = False, renaming = Nothing, selected = Just to })
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


{-| Server returned the encounter body. Replace the live
encounter and record the name it came from. Force round 1 with
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
                    Model.reaimStale
                        { model
                            | encounter = fresh
                            , savedAs = Just name
                        }
            in
            Update.Toast.push ToastSuccess
                ("Loaded \"" ++ name ++ "\".")
                (close next)

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
                    Model.reaimStale
                        { model
                            | encounter = fresh
                            , savedAs = Nothing
                        }
            in
            Update.Toast.push ToastSuccess
                "Loaded encounter from file."
                (close next)

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
