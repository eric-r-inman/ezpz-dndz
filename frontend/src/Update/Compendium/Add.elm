module Update.Compendium.Add exposing
    ( addToQueue, initiativeRolled
    , addSelectedToQueue, addSelectedRolled
    )

{-| Add-to-queue flow for the compendium browser: the GM picks a
creature, clicks Add, and we fire a single-creature initiative
roll Cmd. When the roll lands, `initiativeRolled` materialises
the instance, appends it to the encounter, and posts a success
toast. The browser modal stays open so the GM can quickly add
several different creatures back-to-back.

`addSelectedToQueue` is the bulk-add path: every checkbox-selected
creature is rolled in one batched Cmd, and the response handler
materialises all of them with a single toast.

Decoupled from the rest of the compendium update surface because
this is the only section that touches `Encounter.Roster`,
`Update.Initiative.source`, and the dice-batch machinery.

@docs addToQueue, initiativeRolled
@docs addSelectedToQueue, addSelectedRolled

-}

import Compendium
import Dice
import Dict exposing (Dict)
import Effects
import Encounter.Roster
import Model exposing (Model)
import Msg exposing (Msg(..))
import Random
import Set
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Toast exposing (ToastKind(..))
import Update.Initiative
import Update.Toast


addToQueue : String -> Model -> ( Model, Cmd Msg )
addToQueue creatureId model =
    ( model, addToQueueCmd model creatureId )


{-| Resolve the selected compendium creature and dispatch a
single-creature initiative roll. When it lands,
`initiativeRolled` spawns one instance with the freshly-rolled
value. Multi-add was removed because the GM can simply click
Add again — the modal stays open after each add for that exact
flow.
-}
addToQueueCmd : Model -> String -> Cmd Msg
addToQueueCmd model creatureId =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            case Compendium.find creatureId db of
                Just source ->
                    let
                        existing =
                            List.map .name model.encounter.creatures

                        name =
                            Encounter.Roster.uniqueInstanceName source.name
                                existing
                    in
                    Dice.batchRollCmd
                        (CompendiumInitiativeRolled creatureId)
                        [ instanceSpec source name ]

                Nothing ->
                    Cmd.none

        _ ->
            Cmd.none


instanceSpec :
    Compendium.Creature
    -> String
    -> ( String, Dice.Source, Random.Generator Dice.Roll )
instanceSpec source displayName =
    ( displayName
    , Update.Initiative.source displayName
    , Dice.generator (Update.Initiative.initiativeExpression source.initiativeBonus)
    )


{-| Bulk-add: roll initiative for every checkbox-selected creature
in `ui.selectedIds` in one batched Cmd. Display names are
generated up-front so name collisions across the bulk add are
resolved deterministically (e.g. three goblins become Goblin,
Goblin 2, Goblin 3). We carry each creature's compendium id
alongside the display name so the response handler can
`Compendium.find` each source without losing track of which roll
belongs to which creature.
-}
addSelectedToQueue : Model -> ( Model, Cmd Msg )
addSelectedToQueue model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            let
                selectedIds =
                    Set.toList model.compendium.selectedIds

                sources =
                    List.filterMap
                        (\id -> Compendium.find id db)
                        selectedIds

                existingNames =
                    List.map .name model.encounter.creatures

                -- Fold left so each newly-assigned name is in the
                -- "existing" set for the next iteration — three
                -- goblins added at once need to land as Goblin,
                -- Goblin 2, Goblin 3 rather than three Goblins.
                ( entriesRev, _ ) =
                    List.foldl
                        (\source ( acc, takenNames ) ->
                            let
                                displayName =
                                    Encounter.Roster.uniqueInstanceName
                                        source.name
                                        takenNames
                            in
                            ( ( source.id, source, displayName ) :: acc
                            , displayName :: takenNames
                            )
                        )
                        ( [], existingNames )
                        sources

                entries =
                    List.reverse entriesRev
            in
            if List.isEmpty entries then
                ( model, Cmd.none )

            else
                ( model, addSelectedCmd entries )

        _ ->
            ( model, Cmd.none )


{-| Build the batched initiative-roll Cmd for `addSelectedToQueue`.
The display name doubles as the lookup key on the way back: we
keep a `displayName -> creatureId` dict so the response handler
can rejoin each `(displayName, roll)` pair with its source id.
-}
addSelectedCmd : List ( String, Compendium.Creature, String ) -> Cmd Msg
addSelectedCmd entries =
    let
        idByDisplayName : Dict String String
        idByDisplayName =
            entries
                |> List.map (\( id, _, displayName ) -> ( displayName, id ))
                |> Dict.fromList

        specs =
            List.map
                (\( _, source, displayName ) -> instanceSpec source displayName)
                entries

        toMsg : List ( String, Dice.Roll ) -> Msg
        toMsg rolls =
            CompendiumAddSelectedRolled
                (List.filterMap
                    (\( displayName, roll ) ->
                        Dict.get displayName idByDisplayName
                            |> Maybe.map
                                (\creatureId ->
                                    ( creatureId, displayName, roll )
                                )
                    )
                    rolls
                )
    in
    Dice.batchRollCmd toMsg specs


addSelectedRolled :
    List ( String, String, Dice.Roll )
    -> Model
    -> ( Model, Cmd Msg )
addSelectedRolled triples model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            let
                instances =
                    List.filterMap
                        (\( creatureId, displayName, roll ) ->
                            Compendium.find creatureId db
                                |> Maybe.map
                                    (\source ->
                                        Compendium.draftToInstance
                                            { displayName = displayName
                                            , initiativeRoll = roll.total
                                            }
                                            source
                                    )
                        )
                        triples

                ( m1, flashCmds ) =
                    List.foldl
                        (\( _, _, r ) ( m, cs ) ->
                            let
                                ( pushed, flashCmd ) =
                                    Effects.pushDiceRoll r m
                            in
                            ( pushed, flashCmd :: cs )
                        )
                        ( model, [] )
                        triples

                addedCount =
                    List.length instances

                toastMessage =
                    "Added " ++ String.fromInt addedCount ++ " creatures to encounter"
            in
            { m1 | encounter = Encounter.Roster.appendCreatures instances m1.encounter }
                |> Update.Toast.pushWith ToastSuccess
                    toastMessage
                    (Cmd.batch
                        (List.map
                            (\( _, _, r ) -> Effects.persistDiceRoll r)
                            triples
                            ++ flashCmds
                        )
                    )

        _ ->
            ( model, Cmd.none )


initiativeRolled : String -> List ( String, Dice.Roll ) -> Model -> ( Model, Cmd Msg )
initiativeRolled creatureId rolls model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            case Compendium.find creatureId db of
                Just source ->
                    let
                        instances =
                            List.map
                                (\( displayName, roll ) ->
                                    Compendium.draftToInstance
                                        { displayName = displayName
                                        , initiativeRoll = roll.total
                                        }
                                        source
                                )
                                rolls

                        ( m1, flashCmds ) =
                            List.foldl
                                (\( _, r ) ( m, cs ) ->
                                    let
                                        ( pushed, flashCmd ) =
                                            Effects.pushDiceRoll r m
                                    in
                                    ( pushed, flashCmd :: cs )
                                )
                                ( model, [] )
                                rolls

                        addedCount =
                            List.length instances

                        toastMessage =
                            if addedCount == 1 then
                                "Added " ++ source.name ++ " to encounter"

                            else
                                "Added " ++ String.fromInt addedCount ++ " × " ++ source.name
                    in
                    -- Modal stays open intentionally: the GM can
                    -- queue several different creatures back-to-back
                    -- without having to re-open the browser each time.
                    { m1 | encounter = Encounter.Roster.appendCreatures instances m1.encounter }
                        |> Update.Toast.pushWith ToastSuccess
                            toastMessage
                            (Cmd.batch
                                (List.map (\( _, r ) -> Effects.persistDiceRoll r) rolls
                                    ++ flashCmds
                                )
                            )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )
