module Update.Compendium.Bulk exposing
    ( deleteRequested, groupDeleteRequested, loreDeleteRequested, importClick, importFileChosen
    , importFileRead, importResponse, pendingCancel, pendingConfirm
    , resetClick, resetResponse
    , clearAll, clearClick, clearResponse, clearSelected, deleteSelected
    )

{-| Bulk import / reset / per-row delete flow for the compendium
browser. All three actions go through a "pending" confirmation
banner before the wire call fires so a mis-click can't replace
the library or wipe a creature without one final yes.

`Ui.Compendium.PendingAction` identifies which destructive
action the GM has queued; `pendingConfirm` dispatches to the
right Cmd.

@docs deleteRequested, groupDeleteRequested, loreDeleteRequested, importClick, importFileChosen
@docs importFileRead, importResponse, pendingCancel, pendingConfirm
@docs resetClick, resetResponse

-}

import Auth
import Compendium
import Compendium.Group exposing (Group)
import Compendium.GroupWire
import Compendium.Wire
import Dict
import Effects
import File exposing (File)
import File.Select
import Http
import Json.Decode as Decode
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
import Update.Compendium.Group
import Update.Compendium.Lore
import Update.Toast
import Util.Http
import Util.Number


importClick : Model -> ( Model, Cmd Msg )
importClick model =
    ( withCompendium (\ui -> { ui | bulkError = Nothing }) model
    , File.Select.file [ "application/json", "text/plain" ] CompendiumImportFileChosen
    )


importFileChosen : File -> Model -> ( Model, Cmd Msg )
importFileChosen file model =
    ( { model | surface = withoutLoadDialog model.surface }
    , Task.perform CompendiumImportFileRead (File.toString file)
    )


{-| The Load Compendium dialog would cover what a picked file brings
up on the page: the confirmation, or the alert for a bad file.
-}
withoutLoadDialog : Maybe Model.Surface -> Maybe Model.Surface
withoutLoadDialog surface =
    case surface of
        Just (Model.SurfaceLoadCompendium _) ->
            Nothing

        _ ->
            surface


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
banner. A parse failure shows its error on the page instead. The
error tells a file that is no compendium from one that is but will
not read. Either way nothing changed.

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

        Err _ ->
            -- The alert that shows `bulkError` carries an OK button,
            -- so the DM can dismiss it and pick another file.
            { ui
                | pending = Nothing
                , bulkError =
                    Just
                        (if isCompendiumShaped raw then
                            "This compendium file could not be read. It may come from another version of the app. Nothing changed."

                         else
                            "This file is not a compendium. Nothing changed."
                        )
            }


{-| Whether `raw` has a compendium's outline: an object with a
`creatures` field, or a bare list.
-}
isCompendiumShaped : String -> Bool
isCompendiumShaped raw =
    Decode.decodeString
        (Decode.oneOf
            [ Decode.field "creatures" Decode.value |> Decode.map (always True)
            , Decode.list Decode.value |> Decode.map (always True)
            ]
        )
        raw
        |> Result.withDefault False


resetClick : Model -> ( Model, Cmd Msg )
resetClick model =
    ( withCompendium (\ui -> { ui | pending = Just PendingReset, bulkError = Nothing }) model
    , Cmd.none
    )


{-| Every compendium delete asks first through the same banner. The
list's 🗑 and the editor's Delete both stage a creature here.
-}
deleteRequested : String -> String -> Model -> ( Model, Cmd Msg )
deleteRequested id displayName =
    staged (PendingDelete id displayName)


groupDeleteRequested : String -> Model -> ( Model, Cmd Msg )
groupDeleteRequested groupId model =
    staged
        (PendingGroupDelete groupId
            (Dict.get groupId model.compendium.groups
                |> Maybe.map .name
                |> Maybe.withDefault "this group"
            )
        )
        model


loreDeleteRequested : String -> Model -> ( Model, Cmd Msg )
loreDeleteRequested id model =
    staged
        (PendingLoreDelete id
            (Update.Compendium.Lore.findGroup id model
                |> Maybe.map .name
                |> Maybe.withDefault "this lore grouping"
            )
        )
        model


staged : PendingAction -> Model -> ( Model, Cmd Msg )
staged action model =
    ( withCompendium (\ui -> { ui | pending = Just action, bulkError = Nothing }) model
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
        -- PendingClear resolves through its own scope buttons
        -- (`clearAll` / `clearSelected`), never this generic
        -- confirm, so it falls through to the no-op arm.
        Just PendingReset ->
            case model.auth of
                Auth.AuthAuthenticated _ ->
                    ( withCompendium
                        (\ui -> { ui | bulkBusy = True, pending = Nothing })
                        model
                    , Effects.resetCompendium
                    )

                _ ->
                    applyLocalReset model

        Just (PendingImport creatures groups _) ->
            case model.auth of
                Auth.AuthAuthenticated _ ->
                    ( withCompendium
                        (\ui -> { ui | bulkBusy = True, pending = Nothing })
                        model
                    , Effects.importCompendiumBundle creatures groups
                    )

                _ ->
                    applyLocalImport creatures groups model

        Just (PendingDelete id _) ->
            case model.auth of
                Auth.AuthAuthenticated _ ->
                    ( withCompendium
                        (\ui -> { ui | bulkBusy = True, pending = Nothing })
                        model
                    , Effects.deleteCompendiumCreature id
                    )

                _ ->
                    applyLocalCompendiumDelete id model

        Just (PendingGroupDelete groupId _) ->
            Update.Compendium.Group.delete groupId (withCompendium (\ui -> { ui | pending = Nothing }) model)

        Just (PendingLoreDelete id _) ->
            Update.Compendium.Lore.delete id (withCompendium (\ui -> { ui | pending = Nothing }) model)

        Just PendingClear ->
            ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


{-| Anonymous-mode equivalent of the import wire round-trip:
replace the in-memory creatures + groups, mark not-dirty (the
import IS the saved baseline), clear selections, toast. Update
loop persists the new snapshot to localStorage.
-}
applyLocalImport : List Compendium.Creature -> List Group -> Model -> ( Model, Cmd Msg )
applyLocalImport creatures groups model =
    let
        compendium =
            model.compendium

        groupsDict =
            List.foldl (\g acc -> Dict.insert g.id g acc) Dict.empty groups
    in
    { model
        | compendium =
            { compendium
                | db = CompendiumDbLoaded (Compendium.fromList creatures)
                , groups = groupsDict
                , bulkBusy = False
                , pending = Nothing
                , selectedId = Nothing
                , selectedIds = Set.empty
                , bulkMenu = Nothing
                , compendiumDirty = False
            }
    }
        |> Update.Toast.push ToastSuccess
            ("Imported "
                ++ String.fromInt (List.length creatures)
                ++ " "
                ++ Util.Number.pluralize "creature" "creatures" (List.length creatures)
            )


{-| Anonymous-mode equivalent of the reset wire round-trip: drop
the local snapshot back to the bundled defaults. We fire
`fetchAllPublic` to re-read the bundled JSON since the in-memory
list may have diverged considerably from the bundled set; the
response handler installs the fresh list and we mark the library
not-dirty.
-}
applyLocalReset : Model -> ( Model, Cmd Msg )
applyLocalReset model =
    let
        compendium =
            model.compendium
    in
    ( { model
        | compendium =
            { compendium
                | bulkBusy = False
                , pending = Nothing
                , selectedId = Nothing
                , selectedIds = Set.empty
                , bulkMenu = Nothing
                , compendiumDirty = False
                , groups = Dict.empty
                , hiddenBundled = Set.empty
            }
        , nextLocalCreatureId = 1
      }
    , Compendium.Wire.fetchAllPublic CompendiumLoaded
    )


{-| Anonymous-mode equivalent of the single-row delete wire round-
trip. Drop the creature from the in-memory DB, clear it from
selections, close an editor open on it, toast. The update wrapper
persists the snapshot.
-}
applyLocalCompendiumDelete : String -> Model -> ( Model, Cmd Msg )
applyLocalCompendiumDelete id model =
    let
        compendium =
            model.compendium

        newDb =
            case compendium.db of
                CompendiumDbLoaded db ->
                    CompendiumDbLoaded (Compendium.remove id db)

                other ->
                    other

        editingIt =
            case model.surface of
                Just (Model.SurfaceCompendiumEdit { mode }) ->
                    case mode of
                        Ui.Compendium.EditExisting edited ->
                            edited.id == id

                        Ui.Compendium.CreateMode ->
                            False

                _ ->
                    False
    in
    { model
        | surface =
            if editingIt then
                Nothing

            else
                model.surface
        , compendiumEditDraft =
            if editingIt then
                Nothing

            else
                model.compendiumEditDraft
        , compendium =
            { compendium
                | db = newDb
                , bulkBusy = False
                , pending = Nothing
                , selectedId =
                    if compendium.selectedId == Just id then
                        Nothing

                    else
                        compendium.selectedId
                , selectedIds = Set.remove id compendium.selectedIds
                , compendiumDirty = True
            }
    }
        |> Update.Toast.push ToastSuccess "Creature deleted"


{-| The Clear trigger: stage the dialog that picks a scope.
-}
clearClick : Model -> ( Model, Cmd Msg )
clearClick model =
    ( withCompendium
        (\ui -> { ui | pending = Just PendingClear, bulkError = Nothing })
        model
    , Cmd.none
    )


{-| Clear All, from the staged dialog's own button.
Routes through `Effects.keepCompendiumCreatures` so the
response lands in `clearResponse` and keeps the library marked
dirty — the GM just discarded everything, so Export should
still flag unsaved changes.
-}
clearAll : Model -> ( Model, Cmd Msg )
clearAll model =
    case model.auth of
        Auth.AuthAuthenticated _ ->
            ( withCompendium
                (hideLeftOut [] >> (\ui -> { ui | pending = Nothing, bulkBusy = True }))
                model
            , Effects.keepCompendiumCreatures []
            )

        _ ->
            applyLocalClear []
                (withCompendium (\ui -> { ui | pending = Nothing }) model)


{-| Replace the compendium with the kept set — every creature
NOT in `selectedIds`. Same wire path as `clearAll` (also via
`Effects.keepCompendiumCreatures`). No-op when nothing is
selected or the library hasn't loaded.
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
            case model.auth of
                Auth.AuthAuthenticated _ ->
                    ( withCompendium
                        (hideLeftOut kept >> (\ui -> { ui | pending = Nothing, bulkBusy = True }))
                        model
                    , Effects.keepCompendiumCreatures kept
                    )

                _ ->
                    applyLocalClear kept
                        (withCompendium (\ui -> { ui | pending = Nothing }) model)

        _ ->
            ( withCompendium (\ui -> { ui | pending = Nothing }) model
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
            case model.auth of
                Auth.AuthAuthenticated _ ->
                    ( withCompendium
                        (hideLeftOut kept
                            >> (\ui ->
                                    { ui
                                        | bulkMenu = Nothing
                                        , bulkBusy = True
                                        , pending = Nothing
                                        , bulkError = Nothing
                                    }
                               )
                        )
                        model
                    , Effects.keepCompendiumCreatures kept
                    )

                _ ->
                    applyLocalClear kept model

        _ ->
            ( withCompendium
                (\ui -> { ui | bulkMenu = Nothing, pending = Nothing })
                model
            , Cmd.none
            )


{-| The bundled creatures a keep leaves out join the hidden set.
-}
hideLeftOut : List Compendium.Creature -> CompendiumUi -> CompendiumUi
hideLeftOut kept ui =
    let
        keptIds =
            Set.fromList (List.map .id kept)

        leftOut =
            case ui.db of
                CompendiumDbLoaded db ->
                    Compendium.toList db
                        |> List.filter (\c -> c.isBundled && not (Set.member c.id keptIds))
                        |> List.map .id
                        |> Set.fromList

                _ ->
                    Set.empty
    in
    { ui | hiddenBundled = Set.union ui.hiddenBundled leftOut }


{-| Anonymous-mode equivalent of `Effects.keepCompendiumCreatures`

  - `clearResponse`: keep only the supplied creatures (which the
    caller has already filtered down). Library stays marked dirty
    since the GM just discarded creatures. The bundled creatures
    left out stay hidden across reloads.

-}
applyLocalClear : List Compendium.Creature -> Model -> ( Model, Cmd Msg )
applyLocalClear kept model =
    let
        compendium =
            hideLeftOut kept model.compendium
    in
    { model
        | compendium =
            { compendium
                | db = CompendiumDbLoaded (Compendium.fromList kept)
                , bulkBusy = False
                , pending = Nothing
                , selectedId = Nothing
                , selectedIds = Set.empty
                , bulkMenu = Nothing
                , bulkError = Nothing
                , compendiumDirty = True
            }
    }
        |> Update.Toast.push ToastSuccess
            ("Library now has "
                ++ String.fromInt (List.length kept)
                ++ " "
                ++ Util.Number.pluralize "creature" "creatures" (List.length kept)
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
            -- Refetch BOTH creatures AND groups —
            -- `Effects.importCompendiumBundle` sends the full
            -- body shape so the server may have replaced the
            -- caller's groups along with the creatures.
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
                    ("Imported " ++ String.fromInt count ++ " " ++ Util.Number.pluralize "creature" "creatures" count)
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
                    ("Library now has " ++ String.fromInt count ++ " " ++ Util.Number.pluralize "creature" "creatures" count)
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
                        , hiddenBundled = Set.empty
                    }
                )
                model
                |> Update.Toast.pushWith ToastSuccess
                    ("Library reset to " ++ String.fromInt (List.length creatures) ++ " bundled creatures")
                    (Compendium.Wire.fetchAll CompendiumLoaded)
