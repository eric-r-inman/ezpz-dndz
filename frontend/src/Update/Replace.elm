module Update.Replace exposing (apply, applySelected, close, open, pick, searchChanged)

{-| Update branches for the Replace editor: pick a compendium
creature, then swap it in for the active creature (or every
selected creature), preserving each old creature's queue
position and initiative — the same core swap the Quick Add
picker's replace mode performs.
-}

import Compendium
import Encounter.Roster
import Model exposing (Model, Surface(..))
import Msg exposing (Msg)
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Replace as ReplaceUi exposing (ReplaceUi)


{-| The editor's own drawer entry, in the `Maybe Surface`
shape the pattern matches below were written against.
-}
drawerSurface : Model -> Maybe Surface
drawerSurface model =
    Model.drawerGet Model.replaceLens model
        |> Maybe.map SurfaceReplace


{-| Opening is a toggle: clicking the column's Replace button
while the editor is already open for the same target closes it.
-}
open : String -> Model -> ( Model, Cmd Msg )
open target model =
    ( case drawerSurface model of
        Just (SurfaceReplace ui) ->
            if ui.target == target then
                Model.closeDrawer Model.replaceLens model

            else
                Model.openDrawer Model.replaceLens (ReplaceUi.fresh target) model

        _ ->
            Model.openDrawer Model.replaceLens (ReplaceUi.fresh target) model
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( Model.closeDrawer Model.replaceLens model, Cmd.none )


withUi : (ReplaceUi -> ReplaceUi) -> Model -> Model
withUi =
    Model.mapDrawer Model.replaceLens


searchChanged : String -> Model -> ( Model, Cmd Msg )
searchChanged text model =
    ( withUi (\u -> { u | searchText = text }) model, Cmd.none )


{-| Clicking a list row picks (or re-clicking un-picks) the
replacement creature.
-}
pick : String -> Model -> ( Model, Cmd Msg )
pick creatureId model =
    ( withUi
        (\u ->
            { u
                | pickedId =
                    if u.pickedId == Just creatureId then
                        Nothing

                    else
                        Just creatureId
            }
        )
        model
    , Cmd.none
    )


{-| Swap the picked creature in for the editor's target.
-}
apply : Model -> ( Model, Cmd Msg )
apply model =
    case drawerSurface model of
        Just (SurfaceReplace ui) ->
            applyTo [ ui.target ] model

        _ ->
            ( model, Cmd.none )


{-| Swap the picked creature in for every selected creature.
-}
applySelected : Model -> ( Model, Cmd Msg )
applySelected model =
    applyTo
        (model.encounter.creatures
            |> List.filter .selected
            |> List.map .name
        )
        model


{-| Swap the picked compendium creature in for every named
target, one at a time so instance names stay unique, log one
entry, and leave the editor open.
-}
applyTo : List String -> Model -> ( Model, Cmd Msg )
applyTo targets model =
    case ( Model.drawerGet Model.replaceLens model, model.compendium.db ) of
        ( Just ui, CompendiumDbLoaded db ) ->
            case Maybe.andThen (\id -> Compendium.find id db) ui.pickedId of
                Just source ->
                    let
                        result =
                            List.foldl (replaceOne source)
                                { model = model, news = [] }
                                targets

                        entry =
                            { olds = targets
                            , news = List.reverse result.news
                            }

                        applied =
                            result.model
                    in
                    ( if List.isEmpty result.news then
                        applied

                      else
                        { applied
                            | replaceLog =
                                entry
                                    :: List.take
                                        (ReplaceUi.maxReplaceLogEntries - 1)
                                        applied.replaceLog
                        }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| One swap: unique-name the incoming instance against the
queue minus the outgoing creature, then let
`Encounter.Roster.replaceCreature` preserve position and
initiative. A target no longer in the queue no-ops.
-}
replaceOne :
    Compendium.Creature
    -> String
    -> { model : Model, news : List String }
    -> { model : Model, news : List String }
replaceOne source oldName acc =
    if List.any (\c -> c.name == oldName) acc.model.encounter.creatures then
        let
            existing =
                acc.model.encounter.creatures
                    |> List.map .name
                    |> List.filter (\n -> n /= oldName)

            newName =
                Encounter.Roster.uniqueInstanceName source.name existing

            newCreature =
                -- `initiativeRoll = 0` because Roster.replaceCreature
                -- overrides it with the old creature's preserved value.
                Compendium.draftToInstance
                    { displayName = newName, initiativeRoll = 0 }
                    source

            m =
                acc.model
        in
        { model =
            { m
                | encounter =
                    Encounter.Roster.replaceCreature oldName newCreature m.encounter
            }
        , news = newName :: acc.news
        }

    else
        acc
