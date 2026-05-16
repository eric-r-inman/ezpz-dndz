module Update.Compendium.Bulk exposing
    ( deleteFromBrowser, importClick, importFileChosen
    , importFileRead, importResponse, pendingCancel, pendingConfirm
    , resetClick, resetResponse
    , clearAll, clearResponse, clearSelected, deleteSelected
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
import Compendium.Group exposing (Group)
import Compendium.GroupWire
import Compendium.Wire
import Dict
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


{-| Decode the file the user picked. Two shapes accepted:

  - **New** — `{ "creatures": [...], "groups": [...] }` produced
    by today's `Update.SaveCompendium.downloadCompendium`. The
    `groups` field is optional so a file authored before the
    Group feature still imports.
  - **Legacy** — a bare `[creature, ...]` array from earlier
    exports.

The two parsers are tried in order via `Decode.oneOf`; whichever
matches sets the `PendingImport` ready for the confirmation
banner. On parse failure we keep the modal open and show the
error.

-}
importFileLoaded : String -> CompendiumUi -> CompendiumUi
importFileLoaded raw ui =
    let
        fullDecoder =
            Decode.map2 Tuple.pair
                (Decode.field "creatures"
                    (Decode.list Compendium.Wire.decodeCreature)
                )
                (Decode.oneOf
                    [ Decode.field "groups"
                        (Decode.list Compendium.GroupWire.decodeGroup)
                    , Decode.succeed []
                    ]
                )

        legacyDecoder =
            Decode.list Compendium.Wire.decodeCreature
                |> Decode.map (\cs -> ( cs, [] ))
    in
    case Decode.decodeString (Decode.oneOf [ fullDecoder, legacyDecoder ]) raw of
        Ok ( creatures, groups ) ->
            { ui
                | pending =
                    Just
                        (PendingImport creatures groups (List.length creatures))
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

        Just (PendingImport creatures groups _) ->
            ( withCompendium
                (\ui -> { ui | bulkBusy = True, pending = Nothing })
                model
            , importCmd creatures groups
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


{-| Import-from-file path. Sends the **full** body shape
(`{ creatures, groups }`) so both the shared bestiary and the
caller's groups get replaced server-side in one wire call.
-}
importCmd : List Compendium.Creature -> List Compendium.Group.Group -> Cmd Msg
importCmd creatures groups =
    Http.post
        { url = "/api/compendium/import"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "creatures"
                      , Encode.list Compendium.Wire.encodeCreature creatures
                      )
                    , ( "groups"
                      , Encode.list Compendium.GroupWire.encodeGroup groups
                      )
                    ]
                )
        , expect =
            Http.expectJson CompendiumImportResponse
                (Decode.field "imported" Decode.int)
        }


{-| Clear-All / Clear-Selected wire path. Sends the **legacy**
bare-array body shape so the server's `import_compendium`
handler keeps groups untouched — a clear is about creatures
only. The response shape (`{ imported }`) is the same as
`importCmd`, but the Msg is tagged so the frontend dirty-flag
semantics differ: Clear keeps dirty=True, file-import clears it.
-}
clearCmd : List Compendium.Creature -> Cmd Msg
clearCmd creatures =
    Http.post
        { url = "/api/compendium/import"
        , body =
            Http.jsonBody (Encode.list Compendium.Wire.encodeCreature creatures)
        , expect =
            Http.expectJson CompendiumClearResponse
                (Decode.field "imported" Decode.int)
        }


{-| Wholesale-replace the compendium with an empty list.
Routes through `clearCmd` so the response lands in
`clearResponse` and keeps the library marked dirty (the GM
just discarded everything; Export should still flag as having
unsaved changes).

Closes the Clear dropdown synchronously; the user shouldn't
see the dropdown still hovering after the destructive op
fires.

-}
clearAll : Model -> ( Model, Cmd Msg )
clearAll model =
    ( withCompendium
        (\ui -> { ui | bulkMenu = Nothing, bulkBusy = True })
        model
    , clearCmd []
    )


{-| Replace the compendium with the kept set — every creature
NOT in `selectedIds`. Same wire path as `clearAll` (also via
`clearCmd`). No-op when nothing is selected or the library
hasn't loaded.
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
                (\ui -> { ui | bulkMenu = Nothing, bulkBusy = True })
                model
            , clearCmd kept
            )

        _ ->
            ( withCompendium (\ui -> { ui | bulkMenu = Nothing }) model
            , Cmd.none
            )


{-| "Delete Selected" from the delete-confirm banner: identical
to `clearSelected`'s wire path, but also dismisses the pending
PendingDelete that opened the banner so the confirm UI doesn't
linger after the bulk op fires.
-}
deleteSelected : Model -> ( Model, Cmd Msg )
deleteSelected model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            let
                kept =
                    Compendium.toList db
                        |> List.filter
                            (\c -> not (Set.member c.id model.compendium.selectedIds))
            in
            ( withCompendium
                (\ui ->
                    { ui
                        | bulkMenu = Nothing
                        , bulkBusy = True
                        , pending = Nothing
                        , bulkError = Nothing
                    }
                )
                model
            , clearCmd kept
            )

        _ ->
            ( withCompendium
                (\ui -> { ui | bulkMenu = Nothing, pending = Nothing })
                model
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
            -- dirty flag clears.  Clear All / Clear Selected
            -- route through `clearResponse` instead, which keeps
            -- dirty=True since the GM just discarded creatures.
            --
            -- Refetch BOTH creatures AND groups — `importCmd`
            -- sends the full body shape so the server may have
            -- replaced the caller's groups along with the
            -- creatures.
            withCompendium
                (\ui ->
                    { ui
                        | bulkBusy = False
                        , selectedId = Nothing
                        , selectedIds = Set.empty
                        , bulkMenu = Nothing
                        , compendiumDirty = False
                    }
                )
                model
                |> Update.Toast.pushWith ToastSuccess
                    ("Imported " ++ String.fromInt count ++ " creatures")
                    (Cmd.batch
                        [ Compendium.Wire.fetchAll CompendiumLoaded
                        , Compendium.GroupWire.fetchAll CompendiumGroupsLoaded
                        ]
                    )


{-| Response handler for Clear All / Clear Selected. Same
shape as `importResponse` but keeps `compendiumDirty = True`
on success — the user's just-completed wipe is itself an
alteration that warrants the Export "save me!" cue.
-}
clearResponse : Result Http.Error Int -> Model -> ( Model, Cmd Msg )
clearResponse result model =
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
                    ("Clear failed: " ++ Util.Http.errorToString err)

        Ok count ->
            withCompendium
                (\ui ->
                    { ui
                        | bulkBusy = False
                        , selectedId = Nothing
                        , selectedIds = Set.empty
                        , bulkMenu = Nothing
                        , compendiumDirty = True
                    }
                )
                model
                |> Update.Toast.pushWith ToastSuccess
                    ("Library now has " ++ String.fromInt count ++ " creatures")
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
            -- The server also wipes the caller's groups (groups
            -- reference creature ids that may be gone after the
            -- reset), so clear them locally too.
            withCompendium
                (\ui ->
                    { ui
                        | bulkBusy = False
                        , selectedId = Nothing
                        , selectedIds = Set.empty
                        , compendiumDirty = False
                        , groups = Dict.empty
                        , expandedGroupIds = Set.empty
                        , selectedGroupId = Nothing
                    }
                )
                model
                |> Update.Toast.pushWith ToastSuccess
                    ("Library reset to " ++ String.fromInt (List.length creatures) ++ " bundled creatures")
                    (Compendium.Wire.fetchAll CompendiumLoaded)
