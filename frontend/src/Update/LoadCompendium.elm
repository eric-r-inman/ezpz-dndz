module Update.LoadCompendium exposing
    ( close
    , confirmCancel
    , confirmConfirm
    , fromServerRequested
    , listLoaded
    , open
    , serverResponse
    )

{-| Update branches for the Load-compendium modal.

Loading is destructive — the chosen snapshot replaces the
current creature library — so the load goes through an inline
confirmation banner first. Device load reuses the existing
`CompendiumImportClick` flow (file picker + parse + replace\_all)
which the rest of the bulk-actions code already handles.

The successful load wires the snapshot's creature list back
through the same `replace_all` server endpoint so the canonical
on-disk state stays in sync with what the user sees.

-}

import Compendium
import Compendium.Wire
import Http
import Json.Decode as Decode
import Json.Encode as E
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Compendium as CompendiumUi
import Ui.LoadCompendium as LoadCompendiumUi
    exposing
        ( ConfirmAction(..)
        , LoadCompendiumUi
        , LoadListState(..)
        )
import Ui.Toast exposing (ToastKind(..))
import Update.Toast
import Util.Http


withLoadUi : (LoadCompendiumUi -> LoadCompendiumUi) -> Model -> Model
withLoadUi =
    Model.mapModal Model.loadCompendiumLens


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model
        | modal = Just (ModalLoadCompendium LoadCompendiumUi.fresh)
        , compendium = CompendiumUi.closeMenus model.compendium
      }
    , Compendium.Wire.listCompendiumSavesCmd LoadCompendiumListLoaded
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


listLoaded :
    Result Http.Error (List Compendium.Wire.SavedCompendiumMeta)
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
        Just (ModalLoadCompendium ui) ->
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
                    , Compendium.Wire.getCompendiumSaveCmd
                        (LoadCompendiumServerResponse name)
                        name
                    )

                Just (ConfirmDelete _) ->
                    -- MVP modal doesn't surface a delete button.
                    ( withLoadUi
                        (\u -> { u | confirm = Nothing })
                        model
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Server returned the snapshot's creature list. Push it into
the live compendium via the existing `/api/compendium/import`
endpoint (wholesale replace); on success, mark the library as
synced (clean) and remember the snapshot name.

The Cmd uses `CompendiumImportResponse` so the existing import
response handler does the right thing — refreshes the local
`db`, clears the dirty flag, etc.

-}
serverResponse :
    String
    -> Result Http.Error (List Compendium.Creature)
    -> Model
    -> ( Model, Cmd Msg )
serverResponse name result model =
    case result of
        Ok creatures ->
            let
                next =
                    { model
                        | modal = Nothing
                        , compendium =
                            CompendiumUi.markSaved name model.compendium
                    }
            in
            Update.Toast.pushWith ToastSuccess
                ("Loaded compendium \"" ++ name ++ "\".")
                (pushCreatures creatures)
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


{-| Replace the live compendium with the supplied creature list.
Goes through `POST /api/compendium/import` (the existing
wholesale-replace endpoint) so the response lands in
`Update.Compendium.Bulk.importResponse` and refreshes the local
`db` + dirty flag like a regular import.
-}
pushCreatures : List Compendium.Creature -> Cmd Msg
pushCreatures creatures =
    Http.post
        { url = "/api/compendium/import"
        , body =
            Http.jsonBody
                (E.list Compendium.Wire.encodeCreature creatures)
        , expect =
            Http.expectJson CompendiumImportResponse
                (Decode.field "imported" Decode.int)
        }
