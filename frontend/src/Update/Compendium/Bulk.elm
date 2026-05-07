module Update.Compendium.Bulk exposing
    ( deleteFromBrowser, importClick, importFileChosen
    , importFileRead, importResponse, pendingCancel, pendingConfirm
    , resetClick, resetResponse
    , clearAll, clearSelected
    )

{-| Bulk import / reset / per-row delete flow for the compendium
browser. All three actions go through a "pending" confirmation
banner before the wire call fires so a mis-click can't replace
the library or wipe a creature without one final yes.

`PendingReset`, `PendingImport`, `PendingDelete` (an ADT in
`Ui.Compendium`) identify which destructive action the GM has
queued; `pendingConfirm` dispatches to the right Cmd.

@docs deleteFromBrowser, importClick, importFileChosen
@docs importFileRead, importResponse, pendingCancel, pendingConfirm
@docs resetClick, resetResponse

-}

import Compendium
import Compendium.Wire
import File exposing (File)
import File.Select
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Model exposing (Model)
import Msg exposing (Msg(..))
import Set
import Task
import Ui.Compendium
    exposing
        ( CompendiumDb(..)
        , CompendiumUi
        , PendingAction(..)
        )
import Ui.Toast exposing (ToastKind(..))
import Update.Compendium.Browser exposing (withCompendium)
import Update.Toast
import Util.Http


importClick : Model -> ( Model, Cmd Msg )
importClick model =
    ( withCompendium (\ui -> { ui | bulkError = Nothing }) model
    , File.Select.file [ "application/json", "text/plain" ] CompendiumImportFileChosen
    )


importFileChosen : File -> Model -> ( Model, Cmd Msg )
importFileChosen file model =
    ( model, Task.perform CompendiumImportFileRead (File.toString file) )


importFileRead : String -> Model -> ( Model, Cmd Msg )
importFileRead raw model =
    ( withCompendium (importFileLoaded raw) model, Cmd.none )


{-| Decode the file the user picked. On parse success we set the
pending action and surface an inline confirmation banner so the GM
gets one final "yes, replace everything" before the wire call
fires. On parse failure we keep the modal open and show the
error.
-}
importFileLoaded : String -> CompendiumUi -> CompendiumUi
importFileLoaded raw ui =
    case Decode.decodeString (Decode.list Compendium.Wire.decodeCreature) raw of
        Ok creatures ->
            { ui
                | pending = Just (PendingImport creatures (List.length creatures))
                , bulkError = Nothing
            }

        Err err ->
            { ui
                | pending = Nothing
                , bulkError = Just ("Couldn't parse file: " ++ Decode.errorToString err)
            }


resetClick : Model -> ( Model, Cmd Msg )
resetClick model =
    ( withCompendium (\ui -> { ui | pending = Just PendingReset, bulkError = Nothing }) model
    , Cmd.none
    )


deleteFromBrowser : String -> String -> Model -> ( Model, Cmd Msg )
deleteFromBrowser id displayName model =
    ( withCompendium
        (\ui ->
            { ui
                | pending = Just (PendingDelete id displayName)
                , bulkError = Nothing
            }
        )
        model
    , Cmd.none
    )


pendingCancel : Model -> ( Model, Cmd Msg )
pendingCancel model =
    ( withCompendium (\ui -> { ui | pending = Nothing, bulkError = Nothing }) model
    , Cmd.none
    )


pendingConfirm : Model -> ( Model, Cmd Msg )
pendingConfirm model =
    case model.compendium.pending of
        Just PendingReset ->
            ( withCompendium
                (\ui -> { ui | bulkBusy = True, pending = Nothing })
                model
            , resetCmd
            )

        Just (PendingImport creatures _) ->
            ( withCompendium
                (\ui -> { ui | bulkBusy = True, pending = Nothing })
                model
            , importCmd creatures
            )

        Just (PendingDelete id _) ->
            ( withCompendium
                (\ui -> { ui | bulkBusy = True, pending = Nothing })
                model
            , deleteCmd id
            )

        Nothing ->
            ( model, Cmd.none )


deleteCmd : String -> Cmd Msg
deleteCmd id =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/compendium/creatures/" ++ id
        , body = Http.emptyBody
        , expect = Http.expectWhatever (CompendiumEditDeleteResponse id)
        , timeout = Nothing
        , tracker = Nothing
        }


resetCmd : Cmd Msg
resetCmd =
    Http.post
        { url = "/api/compendium/reset"
        , body = Http.emptyBody
        , expect =
            Http.expectJson CompendiumResetResponse
                (Decode.list Compendium.Wire.decodeCreature)
        }


importCmd : List Compendium.Creature -> Cmd Msg
importCmd creatures =
    Http.post
        { url = "/api/compendium/import"
        , body =
            Http.jsonBody (Encode.list Compendium.Wire.encodeCreature creatures)
        , expect =
            Http.expectJson CompendiumImportResponse
                (Decode.field "imported" Decode.int)
        }


{-| Wholesale-replace the compendium with an empty list.
Routes through the existing import endpoint (the server treats
an empty array as a valid wipe), so `importResponse` cleans up
the local cache + selection + clearMenu state on success.

Closes the Clear dropdown synchronously; the user shouldn't see
the dropdown still hovering after the destructive op fires.

-}
clearAll : Model -> ( Model, Cmd Msg )
clearAll model =
    ( withCompendium
        (\ui -> { ui | clearMenuOpen = False, bulkBusy = True })
        model
    , importCmd []
    )


{-| Replace the compendium with the kept set — every creature
NOT in `selectedIds`. Same wire path as `clearAll` so success
runs through `importResponse`. No-op when nothing is selected
or the library hasn't loaded.
-}
clearSelected : Model -> ( Model, Cmd Msg )
clearSelected model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            let
                kept =
                    Compendium.toList db
                        |> List.filter
                            (\c -> not (Set.member c.id model.compendium.selectedIds))
            in
            ( withCompendium
                (\ui -> { ui | clearMenuOpen = False, bulkBusy = True })
                model
            , importCmd kept
            )

        _ ->
            ( withCompendium (\ui -> { ui | clearMenuOpen = False }) model
            , Cmd.none
            )


importResponse : Result Http.Error Int -> Model -> ( Model, Cmd Msg )
importResponse result model =
    case result of
        Err err ->
            withCompendium
                (\ui ->
                    { ui
                        | bulkBusy = False
                        , bulkError = Just (Util.Http.errorToString err)
                    }
                )
                model
                |> Update.Toast.push ToastError
                    ("Import failed: " ++ Util.Http.errorToString err)

        Ok count ->
            -- Wholesale replace from a file leaves the library in
            -- a "saved" state matching what's on disk, so the
            -- dirty flag clears.  The same path runs after Clear
            -- All / Clear Selected (those re-import a curated set)
            -- so we also wipe `selectedIds` and close any stale
            -- Clear dropdown.
            withCompendium
                (\ui ->
                    { ui
                        | bulkBusy = False
                        , selectedId = Nothing
                        , selectedIds = Set.empty
                        , clearMenuOpen = False
                        , compendiumDirty = False
                    }
                )
                model
                |> Update.Toast.pushWith ToastSuccess
                    ("Imported " ++ String.fromInt count ++ " creatures")
                    (Compendium.Wire.fetchAll CompendiumLoaded)


resetResponse : Result Http.Error (List Compendium.Creature) -> Model -> ( Model, Cmd Msg )
resetResponse result model =
    case result of
        Err err ->
            withCompendium
                (\ui ->
                    { ui
                        | bulkBusy = False
                        , bulkError = Just (Util.Http.errorToString err)
                    }
                )
                model
                |> Update.Toast.push ToastError
                    ("Reset failed: " ++ Util.Http.errorToString err)

        Ok creatures ->
            -- Reset restores the bundled set; the library is
            -- back to its baseline so dirty clears, and any
            -- bulk-selection from before the reset is now stale.
            withCompendium
                (\ui ->
                    { ui
                        | bulkBusy = False
                        , selectedId = Nothing
                        , selectedIds = Set.empty
                        , compendiumDirty = False
                    }
                )
                model
                |> Update.Toast.pushWith ToastSuccess
                    ("Library reset to " ++ String.fromInt (List.length creatures) ++ " bundled creatures")
                    (Compendium.Wire.fetchAll CompendiumLoaded)
