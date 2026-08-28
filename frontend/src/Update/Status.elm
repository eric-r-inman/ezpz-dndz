module Update.Status exposing (applyActive, applySelected, close, coverCycle, flyHeightAdjust, open, openFor, toggleFlag)

{-| Update branches for the encounter toolbar's Status editor.
The toggles edit a draft; the two Apply buttons write the whole
draft onto the active creature or onto every selected creature.
-}

import Encounter
import Model exposing (Model, Surface(..))
import Msg exposing (Msg, StatusFlag(..))
import Ui.Status as StatusUi exposing (StatusUi)


{-| The toolbar trigger: clicking it while any Status editor is
expanded closes it — the button shows the fold caret and Cancel
hover text whenever the editor is open, so it must close
regardless of which creature a card status label aimed it at. A
fresh open prefills the draft from the target creature.
-}
open : String -> Model -> ( Model, Cmd Msg )
open target model =
    ( case model.surface of
        Just (SurfaceStatus _) ->
            { model | surface = Nothing }

        _ ->
            { model | surface = Just (SurfaceStatus (prefilled target model)) }
    , Cmd.none
    )


{-| A card's status label: it aims the editor at its own
creature, so an editor already open for someone else re-aims
rather than closing. Re-clicking the label of the creature
being edited folds the editor away, matching the toolbar
trigger's toggle.
-}
openFor : String -> Model -> ( Model, Cmd Msg )
openFor target model =
    ( case model.surface of
        Just (SurfaceStatus ui) ->
            if ui.target == target then
                { model | surface = Nothing }

            else
                { model | surface = Just (SurfaceStatus (prefilled target model)) }

        _ ->
            { model | surface = Just (SurfaceStatus (prefilled target model)) }
    , Cmd.none
    )


prefilled : String -> Model -> StatusUi
prefilled target model =
    model.encounter.creatures
        |> List.filter (\c -> c.name == target)
        |> List.head
        |> Maybe.map StatusUi.fromCreature
        |> Maybe.withDefault (StatusUi.fresh target)


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | surface = Nothing }, Cmd.none )


withUi : (StatusUi -> StatusUi) -> Model -> Model
withUi fn model =
    case model.surface of
        Just (SurfaceStatus ui) ->
            { model | surface = Just (SurfaceStatus (fn ui)) }

        _ ->
            model


coverCycle : Model -> ( Model, Cmd Msg )
coverCycle model =
    ( withUi (\u -> { u | cover = Encounter.nextCover u.cover }) model
    , Cmd.none
    )


toggleFlag : StatusFlag -> Model -> ( Model, Cmd Msg )
toggleFlag flag model =
    ( withUi
        (\u ->
            case flag of
                FlagConcentrating ->
                    { u | concentrating = not u.concentrating }

                FlagHiding ->
                    { u | hiding = not u.hiding }

                FlagDodging ->
                    { u | dodging = not u.dodging }

                FlagFlying ->
                    { u | flying = not u.flying }
        )
        model
    , Cmd.none
    )


flyHeightAdjust : Int -> Model -> ( Model, Cmd Msg )
flyHeightAdjust delta model =
    ( withUi (\u -> { u | flyHeight = max 0 (u.flyHeight + delta) }) model
    , Cmd.none
    )


{-| Write the draft onto the active creature (top of the queue
before combat starts, matching the toolbar's target fallback).
-}
applyActive : Model -> ( Model, Cmd Msg )
applyActive model =
    let
        target =
            if String.isEmpty model.encounter.activeName then
                model.encounter.creatures
                    |> List.head
                    |> Maybe.map .name
                    |> Maybe.withDefault ""

            else
                model.encounter.activeName
    in
    ( applyTo [ target ] model, Cmd.none )


applySelected : Model -> ( Model, Cmd Msg )
applySelected model =
    ( applyTo
        (model.encounter.creatures
            |> List.filter .selected
            |> List.map .name
        )
        model
    , Cmd.none
    )


{-| Stamp every draft field onto each named creature. A grounded
draft zeroes the flight height so a later re-fly starts at 0,
matching the card toggles' old behaviour.
-}
applyTo : List String -> Model -> Model
applyTo names model =
    case model.surface of
        Just (SurfaceStatus ui) ->
            let
                stamp c =
                    { c
                        | cover = ui.cover
                        , concentrating = ui.concentrating
                        , hiding = ui.hiding
                        , dodging = ui.dodging
                        , flying = ui.flying
                        , flyHeight =
                            if ui.flying then
                                ui.flyHeight

                            else
                                0
                    }
            in
            { model
                | encounter =
                    List.foldl
                        (\name enc -> Encounter.mapCreature name stamp enc)
                        model.encounter
                        names
            }

        _ ->
            model
