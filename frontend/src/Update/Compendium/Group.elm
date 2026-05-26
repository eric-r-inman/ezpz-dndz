module Update.Compendium.Group exposing
    ( open, openFromSelected, openExisting, close
    , nameChanged, initiativeModeSet, manualInitiativeChanged
    , entryAdd, entryRemove
    , entryCreatureChanged, entryCountChanged, entryMinionTypeSet
    , submit, created, updated
    , expandToggle, select, delete, deleteResponse
    , groupsLoaded
    )

{-| Update branches for the **Create / Edit Group** modal and the
in-list group interactions (expand/collapse, select, delete).

Persistence is server-side via `/api/compendium/groups`: create
fires `POST`, edit fires `PUT`, delete fires `DELETE`. The
response handlers update the in-memory dict so the list re-renders
without an extra refetch. Boot fires `Compendium.GroupWire.fetchAll`
and `groupsLoaded` ingests the result.

@docs open, openFromSelected, openExisting, close
@docs nameChanged, initiativeModeSet, manualInitiativeChanged
@docs entryAdd, entryRemove
@docs entryCreatureChanged, entryCountChanged, entryMinionTypeSet
@docs submit, created, updated
@docs expandToggle, select, delete, deleteResponse
@docs groupsLoaded

-}

import Auth
import Compendium.Group as Group exposing (Group, MinionType(..))
import Compendium.GroupWire as GroupWire
import Dict exposing (Dict)
import Http
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Set
import Ui.Compendium as CompendiumUi
import Ui.GroupEdit as GroupEdit exposing (GroupEditMode(..))
import Ui.Toast exposing (ToastKind(..))
import Update.Compendium.Browser exposing (withCompendium)
import Update.Toast
import Util.Http



-- ── OPEN / CLOSE ─────────────────────────────────────────────────────────────


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model | modal = Just (ModalGroupEdit GroupEdit.fresh) }
    , Cmd.none
    )


openFromSelected : Model -> ( Model, Cmd Msg )
openFromSelected model =
    let
        selected =
            Set.toList model.compendium.selectedIds

        ui =
            GroupEdit.freshFromSelected selected
    in
    ( { model | modal = Just (ModalGroupEdit ui) }
    , Cmd.none
    )


openExisting : String -> Model -> ( Model, Cmd Msg )
openExisting groupId model =
    case Dict.get groupId model.compendium.groups of
        Just group ->
            ( { model | modal = Just (ModalGroupEdit (GroupEdit.fromGroup group)) }
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )



-- ── FORM-FIELD HANDLERS ──────────────────────────────────────────────────────


nameChanged : String -> Model -> ( Model, Cmd Msg )
nameChanged raw model =
    ( withGroupEdit
        (\ui -> { ui | name = String.left GroupEdit.maxNameLength raw })
        model
    , Cmd.none
    )


initiativeModeSet : String -> Model -> ( Model, Cmd Msg )
initiativeModeSet key model =
    case Group.initiativeModeFromKey key of
        Just mode ->
            ( withGroupEdit (\ui -> { ui | initiativeMode = mode }) model
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


manualInitiativeChanged : String -> Model -> ( Model, Cmd Msg )
manualInitiativeChanged raw model =
    ( withGroupEdit
        (\ui -> { ui | manualInitiative = String.left 3 raw })
        model
    , Cmd.none
    )


entryAdd : Model -> ( Model, Cmd Msg )
entryAdd model =
    ( withGroupEdit
        (\ui ->
            { ui
                | entries =
                    ui.entries
                        ++ [ { creatureId = ""
                             , count = "1"
                             , minionType = MinionNone
                             }
                           ]
            }
        )
        model
    , Cmd.none
    )


entryRemove : Int -> Model -> ( Model, Cmd Msg )
entryRemove index model =
    ( withGroupEdit
        (\ui -> { ui | entries = removeAt index ui.entries })
        model
    , Cmd.none
    )


entryCreatureChanged : Int -> String -> Model -> ( Model, Cmd Msg )
entryCreatureChanged index creatureId model =
    ( withGroupEdit
        (\ui ->
            { ui
                | entries =
                    updateAt index
                        (\e -> { e | creatureId = creatureId })
                        ui.entries
            }
        )
        model
    , Cmd.none
    )


entryCountChanged : Int -> String -> Model -> ( Model, Cmd Msg )
entryCountChanged index raw model =
    ( withGroupEdit
        (\ui ->
            { ui
                | entries =
                    updateAt index
                        (\e -> { e | count = String.left 3 raw })
                        ui.entries
            }
        )
        model
    , Cmd.none
    )


entryMinionTypeSet : Int -> String -> Model -> ( Model, Cmd Msg )
entryMinionTypeSet index key model =
    case Group.minionTypeFromKey key of
        Just minionType ->
            ( withGroupEdit
                (\ui ->
                    { ui
                        | entries =
                            updateAt index
                                (\e -> { e | minionType = minionType })
                                ui.entries
                    }
                )
                model
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )



-- ── SUBMIT ───────────────────────────────────────────────────────────────────


{-| Validate the form and fire the appropriate HTTP call.
Create-mode dispatches `POST /api/compendium/groups` with the
draft; edit-mode dispatches `PUT /api/compendium/groups/{id}`
with the full record (the server preserves `created_at`).

On validation failure, the inline error banner shows and no
network call fires; the modal stays open with its current
fields intact so the GM can correct the issue.

-}
submit : Model -> ( Model, Cmd Msg )
submit model =
    case Maybe.andThen Model.groupEditLens.extract model.modal of
        Nothing ->
            ( model, Cmd.none )

        Just ui ->
            case GroupEdit.validate ui of
                Err err ->
                    ( withGroupEdit (\u -> { u | submitError = Just err }) model
                    , Cmd.none
                    )

                Ok validated ->
                    case model.auth of
                        Auth.AuthAuthenticated _ ->
                            let
                                cmd =
                                    case ui.mode of
                                        GroupCreateMode ->
                                            GroupWire.create
                                                (draftFromGroup validated)
                                                CompendiumGroupCreated

                                        GroupEditExisting _ ->
                                            GroupWire.update validated
                                                CompendiumGroupUpdated
                            in
                            ( withGroupEdit
                                (\u -> { u | submitting = True, submitError = Nothing })
                                model
                            , cmd
                            )

                        _ ->
                            applyLocalGroupSubmit ui.mode validated model


{-| Anonymous-mode equivalent of the create/update wire round-
trip. Mutate `model.compendium.groups` directly; CreateMode
allocates a fresh local id from the shared counter so reload
won't collide.
-}
applyLocalGroupSubmit : GroupEditMode -> Group -> Model -> ( Model, Cmd Msg )
applyLocalGroupSubmit mode validated model =
    let
        ( finalGroup, withId ) =
            case mode of
                GroupCreateMode ->
                    let
                        idN =
                            model.nextLocalCreatureId

                        finalId =
                            "local-group-" ++ String.fromInt idN
                    in
                    ( { validated | id = finalId }
                    , { model | nextLocalCreatureId = idN + 1 }
                    )

                GroupEditExisting _ ->
                    ( validated, model )

        next =
            { withId | modal = Nothing }
                |> withCompendium (CompendiumUi.addGroup finalGroup)
    in
    Update.Toast.push ToastSuccess
        ("Group \"" ++ finalGroup.name ++ "\" saved.")
        next


draftFromGroup : Group -> GroupWire.Draft
draftFromGroup g =
    { name = g.name
    , initiativeMode = g.initiativeMode
    , entries = g.entries
    }


{-| `POST` response: stash the server-returned group (it has the
real id + timestamps), close the modal, toast.
-}
created : Result Http.Error Group -> Model -> ( Model, Cmd Msg )
created result model =
    case result of
        Err err ->
            ( withGroupEdit
                (\u ->
                    { u
                        | submitting = False
                        , submitError = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )

        Ok group ->
            { model | modal = Nothing }
                |> withCompendium (CompendiumUi.addGroup group)
                |> Update.Toast.push ToastSuccess
                    ("Group \"" ++ group.name ++ "\" created.")


{-| `PUT` response: replace the local copy with the server's
returned record, close, toast.
-}
updated : Result Http.Error Group -> Model -> ( Model, Cmd Msg )
updated result model =
    case result of
        Err err ->
            ( withGroupEdit
                (\u ->
                    { u
                        | submitting = False
                        , submitError = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )

        Ok group ->
            { model | modal = Nothing }
                |> withCompendium (CompendiumUi.addGroup group)
                |> Update.Toast.push ToastSuccess
                    ("Group \"" ++ group.name ++ "\" saved.")


{-| Boot-fetch response: drop the returned groups into the
dict. Errors are silently swallowed — same discipline as the
creature fetch, since a fresh user with no groups is fine.
-}
groupsLoaded :
    Result Http.Error (List Group)
    -> Model
    -> ( Model, Cmd Msg )
groupsLoaded result model =
    case result of
        Ok groups ->
            ( withCompendium
                (\ui ->
                    { ui
                        | groups =
                            groups
                                |> List.map (\g -> ( g.id, g ))
                                |> Dict.fromList
                    }
                )
                model
            , Cmd.none
            )

        Err _ ->
            ( model, Cmd.none )



-- ── BROWSER-LIST INTERACTIONS ────────────────────────────────────────────────


expandToggle : String -> Model -> ( Model, Cmd Msg )
expandToggle groupId model =
    ( withCompendium
        (\ui ->
            { ui
                | expandedGroupIds =
                    if Set.member groupId ui.expandedGroupIds then
                        Set.remove groupId ui.expandedGroupIds

                    else
                        Set.insert groupId ui.expandedGroupIds
            }
        )
        model
    , Cmd.none
    )


select : String -> Model -> ( Model, Cmd Msg )
select groupId model =
    ( withCompendium
        (\ui ->
            { ui
                | selectedGroupId = Just groupId

                -- Selecting a group clears any creature-pane
                -- selection so the right pane reads as "this
                -- group's details".
                , selectedId = Nothing
            }
        )
        model
    , Cmd.none
    )


{-| Fire a DELETE for the group; the local dict is updated when
the response lands in [`deleteResponse`](#deleteResponse).
Optimistic delete would be slightly snappier but would diverge
from the server on a permission / network failure.
-}
delete : String -> Model -> ( Model, Cmd Msg )
delete groupId model =
    case model.auth of
        Auth.AuthAuthenticated _ ->
            ( model, GroupWire.delete groupId (CompendiumGroupDeleted groupId) )

        _ ->
            let
                groupName =
                    Dict.get groupId model.compendium.groups
                        |> Maybe.map .name
                        |> Maybe.withDefault "Group"
            in
            model
                |> withCompendium (CompendiumUi.removeGroup groupId)
                |> Update.Toast.push ToastSuccess
                    ("Deleted group \"" ++ groupName ++ "\".")


deleteResponse :
    String
    -> Result Http.Error ()
    -> Model
    -> ( Model, Cmd Msg )
deleteResponse groupId result model =
    case result of
        Ok () ->
            let
                groupName =
                    Dict.get groupId model.compendium.groups
                        |> Maybe.map .name
                        |> Maybe.withDefault "Group"
            in
            model
                |> withCompendium (CompendiumUi.removeGroup groupId)
                |> Update.Toast.push ToastSuccess
                    ("Deleted group \"" ++ groupName ++ "\".")

        Err err ->
            Update.Toast.push ToastError
                ("Couldn't delete group: " ++ Util.Http.errorToString err)
                model



-- ── INTERNAL ─────────────────────────────────────────────────────────────────


withGroupEdit : (GroupEdit.GroupEditUi -> GroupEdit.GroupEditUi) -> Model -> Model
withGroupEdit fn model =
    Model.mapModal Model.groupEditLens fn model


removeAt : Int -> List a -> List a
removeAt index xs =
    List.indexedMap Tuple.pair xs
        |> List.filterMap
            (\( i, x ) ->
                if i == index then
                    Nothing

                else
                    Just x
            )


updateAt : Int -> (a -> a) -> List a -> List a
updateAt index fn xs =
    List.indexedMap
        (\i x ->
            if i == index then
                fn x

            else
                x
        )
        xs
