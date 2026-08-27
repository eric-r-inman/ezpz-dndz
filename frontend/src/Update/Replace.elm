module Update.Replace exposing (apply, applyToSelectedToggle, close, open, pick, searchChanged)

{-| Update branches for the encounter toolbar's Replace editor:
pick a compendium creature, then swap it in for the active
creature (or every selected creature), preserving each old
creature's queue position and initiative — the same core swap
the Quick Add picker's replace mode performs.
-}

import Compendium
import Encounter.Roster
import Model exposing (Model, Surface(..))
import Msg exposing (Msg)
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Replace as ReplaceUi exposing (ReplaceUi)


{-| Opening is a toggle: clicking the toolbar's Replace button
while the editor is already open for the same target closes it.
-}
open : String -> Model -> ( Model, Cmd Msg )
open target model =
    ( case model.surface of
        Just (SurfaceReplace ui) ->
            if ui.target == target then
                { model | surface = Nothing }

            else
                { model | surface = Just (SurfaceReplace (ReplaceUi.fresh target)) }

        _ ->
            { model | surface = Just (SurfaceReplace (ReplaceUi.fresh target)) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | surface = Nothing }, Cmd.none )


withUi : (ReplaceUi -> ReplaceUi) -> Model -> Model
withUi fn model =
    case model.surface of
        Just (SurfaceReplace ui) ->
            { model | surface = Just (SurfaceReplace (fn ui)) }

        _ ->
            model


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


applyToSelectedToggle : Model -> ( Model, Cmd Msg )
applyToSelectedToggle model =
    ( withUi (\u -> { u | applyToSelected = not u.applyToSelected }) model
    , Cmd.none
    )


{-| Swap the picked compendium creature in for every resolved
target, one at a time so instance names stay unique, log one
entry, and leave the editor open.
-}
apply : Model -> ( Model, Cmd Msg )
apply model =
    case ( model.surface, model.compendium.db ) of
        ( Just (SurfaceReplace ui), CompendiumDbLoaded db ) ->
            case Maybe.andThen (\id -> Compendium.find id db) ui.pickedId of
                Just source ->
                    let
                        targets =
                            if ui.applyToSelected then
                                model.encounter.creatures
                                    |> List.filter .selected
                                    |> List.map .name

                            else
                                [ ui.target ]

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
