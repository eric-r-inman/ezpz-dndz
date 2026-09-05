module Update.Status exposing (applySelected, applyTarget, close, coverCycle, flyHeightAdjust, open, openFor, toggleFlag)

{-| Update branches for the Status editor. The toggles edit a
draft; the two Apply buttons write the whole draft onto the
active creature or onto every selected creature.
-}

import Effects
import Encounter
import Model exposing (Model, Surface(..))
import Msg exposing (Msg, StatusFlag(..))
import Ui.Status as StatusUi exposing (StatusUi)


{-| The editor's own drawer entry, in the `Maybe Surface`
shape the pattern matches below were written against.
-}
drawerSurface : Model -> Maybe Surface
drawerSurface model =
    Model.drawerGet Model.statusLens model
        |> Maybe.map SurfaceStatus


{-| The column trigger: clicking it while any Status editor is
expanded closes it — the button wears the open ring and Cancel
hover text whenever the editor is open, so it must close
regardless of which creature a card status label aimed it at. A
fresh open prefills the draft from the target creature.
-}
open : String -> Model -> ( Model, Cmd Msg )
open target model =
    ( case drawerSurface model of
        Just (SurfaceStatus _) ->
            Model.closeDrawer Model.statusLens model

        _ ->
            Model.openDrawer Model.statusLens (prefilled target model) model
    , Cmd.none
    )


{-| A card's status label: it aims the editor at its own
creature, so an editor already open for someone else re-aims.
One already aimed here scrolls into view instead of closing — a
card control asks to see a creature's editor, which is the
opposite of dismissing it. The Actions column's own trigger
still toggles.
-}
openFor : String -> Model -> ( Model, Cmd Msg )
openFor target model =
    case drawerSurface model of
        Just (SurfaceStatus ui) ->
            if ui.target == target then
                ( model
                , Effects.scrollDrawerIndex
                    (Model.drawerIndexOf Model.statusLens model)
                )

            else
                ( Model.openDrawer Model.statusLens (prefilled target model) model
                , Cmd.none
                )

        _ ->
            ( Model.openDrawer Model.statusLens (prefilled target model) model
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
    ( Model.closeDrawer Model.statusLens model, Cmd.none )


withUi : (StatusUi -> StatusUi) -> Model -> Model
withUi =
    Model.mapDrawer Model.statusLens


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


{-| Write the draft onto the creature the editor is aimed at —
the one the target strip names, which is not always the active
creature since a card's status label can re-aim the editor.
-}
applyTarget : Model -> ( Model, Cmd Msg )
applyTarget model =
    ( case drawerSurface model of
        Just (SurfaceStatus ui) ->
            applyTo [ ui.target ] model

        _ ->
            model
    , Cmd.none
    )


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
    case drawerSurface model of
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
