module Update.Status exposing (applySelected, applyTarget, concentrationNoteChanged, coverCycle, flyHeightAdjust, maxConcentrationNoteLength, openFor, toggleFlag)

{-| Update branches for the Status editor. The toggles edit a
draft; the two Apply buttons add what it holds to the target
creature or to every selected creature.
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


{-| A card's status label: it aims the editor at its own
creature, so an editor already open for someone else re-aims.
Aiming it anywhere starts an empty draft whatever that creature
already carries; showing an editor already aimed there keeps what
the GM has toggled.
Every path unfolds and scrolls the panel fully into view — a card
control asks to see a creature's editor, whether that means
showing what is already open, re-aiming it, or opening it fresh.
-}
openFor : String -> Model -> ( Model, Cmd Msg )
openFor target model =
    let
        nextModel =
            case drawerSurface model of
                Just (SurfaceStatus ui) ->
                    if ui.target == target then
                        Model.unfoldDrawer Model.statusLens model

                    else
                        Model.openDrawer Model.statusLens (StatusUi.fresh target) model

                _ ->
                    Model.openDrawer Model.statusLens (StatusUi.fresh target) model
    in
    ( nextModel
    , Effects.scrollDrawerIndex (Model.drawerIndexOf Model.statusLens nextModel)
    )


withUi : (StatusUi -> StatusUi) -> Model -> Model
withUi =
    Model.mapDrawer Model.statusLens


{-| The note is only ever read while `concentrating` is set, so
it survives the toggle going off and comes back with it.
-}
concentrationNoteChanged : String -> Model -> ( Model, Cmd Msg )
concentrationNoteChanged text model =
    ( withUi (\u -> { u | concentrationNote = String.left maxConcentrationNoteLength text }) model
    , Cmd.none
    )


{-| What the card can show beside the status without pushing the
row's other readouts out of line.
-}
maxConcentrationNoteLength : Int
maxConcentrationNoteLength =
    15


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


{-| Add the draft to the creature the editor is aimed at — the
one the target strip names, which is not always the active
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


{-| Add the draft's statuses to each named creature, leaving
what it does not name alone. Applying is how a status goes on
and the × beside it on the card is how it comes off, so a toggle
the GM left off cannot take away one the creature already has —
which matters most when applying to a selection, where one draft
lands on creatures in different states. The draft empties
afterwards, ready for the next thing to add.
-}
applyTo : List String -> Model -> Model
applyTo names model =
    case drawerSurface model of
        Just (SurfaceStatus ui) ->
            let
                targets =
                    Encounter.excludingPlaceholderNames model.encounter names

                add c =
                    { c
                        | cover =
                            if ui.cover == Encounter.NoCover then
                                c.cover

                            else
                                ui.cover
                        , concentrating = c.concentrating || ui.concentrating
                        , concentrationNote =
                            if ui.concentrating && not (String.isEmpty (String.trim ui.concentrationNote)) then
                                String.trim ui.concentrationNote

                            else
                                c.concentrationNote
                        , hiding = c.hiding || ui.hiding
                        , dodging = c.dodging || ui.dodging
                        , flying = c.flying || ui.flying
                        , flyHeight =
                            if ui.flying then
                                ui.flyHeight

                            else
                                c.flyHeight
                    }
            in
            withUi (\u -> StatusUi.fresh u.target)
                { model
                    | encounter =
                        List.foldl
                            (\name enc -> Encounter.mapCreature name add enc)
                            model.encounter
                            targets
                }

        _ ->
            model
