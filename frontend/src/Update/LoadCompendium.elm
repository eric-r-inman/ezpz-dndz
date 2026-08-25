module Update.LoadCompendium exposing
    ( close
    , confirmCancel
    , confirmConfirm
    , fromServerRequested
    , listLoaded
    , open
    , serverResponse
    , sourceSet
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
import Compendium.Group
import Compendium.Wire
import Effects
import Http
import Model exposing (Model, Surface(..))
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
    Model.mapSurface Model.loadCompendiumLens


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model
        | surface = Just (SurfaceLoadCompendium LoadCompendiumUi.fresh)
        , compendium = CompendiumUi.closeMenus model.compendium
      }
    , Compendium.Wire.listCompendiumSavesCmd LoadCompendiumListLoaded
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | surface = Nothing }, Cmd.none )


{-| Flip the source radio between Server and Device. Clears
the inline error so a prior 401 / network message from a
previous Server attempt doesn't bleed into the Device view.
-}
sourceSet : Msg.LoadSource -> Model -> ( Model, Cmd Msg )
sourceSet source model =
    ( withLoadUi (\ui -> { ui | source = source, error = Nothing }) model
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
    case model.surface of
        Just (SurfaceLoadCompendium ui) ->
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


{-| Server returned the snapshot's bundle (creatures + groups).
Push it into the live compendium via
`Effects.importCompendiumBundle` (`POST /api/compendium/import`
with the bundle shape) so the server replaces both the shared
bestiary and the caller's groups in one wire call. On success,
the `importResponse` handler clears the dirty flag + refreshes
the local creature DB and groups dict.
-}
serverResponse :
    String
    -> Result Http.Error ( List Compendium.Creature, List Compendium.Group.Group )
    -> Model
    -> ( Model, Cmd Msg )
serverResponse name result model =
    case result of
        Ok ( creatures, groups ) ->
            let
                next =
                    { model
                        | surface = Nothing
                        , compendium =
                            CompendiumUi.markSaved name model.compendium
                    }
            in
            Update.Toast.pushWith ToastSuccess
                ("Loaded compendium \"" ++ name ++ "\".")
                (Effects.importCompendiumBundle creatures groups)
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
