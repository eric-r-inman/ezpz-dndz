module Update.SaveCompendium exposing
    ( close
    , confirmCancel
    , confirmConfirm
    , destinationSet
    , filenameChanged
    , listLoaded
    , open
    , overwriteRequested
    , persistResponse
    , submit
    )

{-| Update branches for the Save-compendium modal.

Mirrors the encounter `Update.Save` for snapshotting the
creature library to the server (under a name) or to the user's
local device (as a JSON download). The modal is opened with
its destination preselected via `Compendium → Export → Server /
Device` so the user lands on the right radio.

`pushSnapshot` semantics differ from the encounter modal: a
successful server save flips `compendiumDirty` back to `False`
(the on-disk snapshot is now in sync with the canonical server
copy on display), whereas a successful save does not change
`savedSnapshot` — there's no compendium analogue of the
encounter Reset.

-}

import Compendium
import Compendium.Group
import Compendium.GroupWire
import Compendium.Wire
import File.Download
import Http
import Json.Encode as E
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..), SaveDestination(..))
import Ui.Compendium as CompendiumUi
import Ui.SaveCompendium as SaveCompendiumUi
    exposing
        ( ConfirmAction(..)
        , SaveCompendiumUi
        , SaveListState(..)
        )
import Ui.Toast exposing (ToastKind(..))
import Update.Toast
import Util.Http


{-| Lens over the SaveCompendiumUi inside `model.surface`.
-}
withSaveUi : (SaveCompendiumUi -> SaveCompendiumUi) -> Model -> Model
withSaveUi =
    Model.mapSurface Model.saveCompendiumLens


open : SaveDestination -> Model -> ( Model, Cmd Msg )
open destination model =
    let
        suggested =
            model.compendium.savedAs
    in
    ( { model
        | surface =
            Just
                (SurfaceSaveCompendium
                    (SaveCompendiumUi.fresh destination suggested)
                )
        , compendium =
            CompendiumUi.closeMenus model.compendium
      }
    , Compendium.Wire.listCompendiumSavesCmd SaveCompendiumListLoaded
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | surface = Nothing }, Cmd.none )


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
                | filename =
                    String.left SaveCompendiumUi.maxNameLength text
                , error = Nothing
            }
        )
        model
    , Cmd.none
    )


listLoaded :
    Result Http.Error (List Compendium.Wire.SavedCompendiumMeta)
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


submit : Model -> ( Model, Cmd Msg )
submit model =
    case model.surface of
        Just (SurfaceSaveCompendium ui) ->
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
                        ( withSaveUi
                            (\u -> { u | busy = True, error = Nothing })
                            model
                        , Compendium.Wire.putCompendiumSaveCmd
                            (SaveCompendiumPersistResponse trimmed)
                            { name = trimmed, overwrite = False }
                            (CompendiumUi.currentCreatures model.compendium)
                            (CompendiumUi.groupsList model.compendium)
                        )

                    SaveDestinationDevice ->
                        ( { model | surface = Nothing }
                        , downloadCompendium trimmed
                            (CompendiumUi.currentCreatures model.compendium)
                            (CompendiumUi.groupsList model.compendium)
                        )

        _ ->
            ( model, Cmd.none )


{-| Encode the compendium and trigger a JSON download with the
user's filename. Bundles the shared creature catalogue and the
GM's per-user creature groups in a single object so the file
round-trips both halves on import (the server's
`/api/compendium/import` accepts this shape). Slash / backslash
in the filename get sanitized so the user can't inadvertently
navigate paths via the download filename.
-}
downloadCompendium :
    String
    -> List Compendium.Creature
    -> List Compendium.Group.Group
    -> Cmd Msg
downloadCompendium rawName creatures groups =
    let
        safe =
            rawName
                |> String.replace "/" "_"
                |> String.replace "\\" "_"

        body =
            E.object
                [ ( "creatures", E.list Compendium.Wire.encodeCreature creatures )
                , ( "groups", E.list Compendium.GroupWire.encodeGroup groups )
                ]
                |> E.encode 2
    in
    File.Download.string (safe ++ ".json") "application/json" body


persistResponse :
    String
    -> Result Http.Error ()
    -> Model
    -> ( Model, Cmd Msg )
persistResponse name result model =
    case result of
        Ok () ->
            let
                snapshotted =
                    { model
                        | compendium =
                            CompendiumUi.markSaved name model.compendium
                        , surface = Nothing
                    }
            in
            Update.Toast.push ToastSuccess
                ("Saved compendium \"" ++ name ++ "\".")
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


overwriteRequested : String -> Model -> ( Model, Cmd Msg )
overwriteRequested name model =
    ( withSaveUi
        (\ui ->
            { ui
                | confirm = Just (ConfirmOverwrite name)
                , error = Nothing
            }
        )
        model
    , Cmd.none
    )


confirmCancel : Model -> ( Model, Cmd Msg )
confirmCancel model =
    ( withSaveUi (\ui -> { ui | confirm = Nothing }) model, Cmd.none )


confirmConfirm : Model -> ( Model, Cmd Msg )
confirmConfirm model =
    case model.surface of
        Just (SurfaceSaveCompendium ui) ->
            case ui.confirm of
                Just (ConfirmOverwrite name) ->
                    ( withSaveUi
                        (\u ->
                            { u
                                | busy = True
                                , confirm = Nothing
                                , error = Nothing
                            }
                        )
                        model
                    , Compendium.Wire.putCompendiumSaveCmd
                        (SaveCompendiumPersistResponse name)
                        { name = name, overwrite = True }
                        (CompendiumUi.currentCreatures model.compendium)
                        (CompendiumUi.groupsList model.compendium)
                    )

                Just (ConfirmDelete _) ->
                    -- MVP modal doesn't expose delete; this branch
                    -- is unreachable but kept exhaustive in case
                    -- the action surface grows.
                    ( withSaveUi
                        (\u -> { u | confirm = Nothing })
                        model
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )
