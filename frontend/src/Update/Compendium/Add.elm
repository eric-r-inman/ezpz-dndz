module Update.Compendium.Add exposing (addToQueue, initiativeRolled)

{-| Add-to-queue flow for the compendium browser: the GM picks a
creature, clicks Add, and we fire a single-creature initiative
roll Cmd. When the roll lands, `initiativeRolled` materialises
the instance, appends it to the encounter, and posts a success
toast. The browser modal stays open so the GM can quickly add
several different creatures back-to-back.

Decoupled from the rest of the compendium update surface because
this is the only section that touches `Encounter.Roster`,
`Update.Initiative.source`, and the dice-batch machinery.

@docs addToQueue, initiativeRolled

-}

import Compendium
import Dice
import Effects
import Encounter.Roster
import Model exposing (Model)
import Msg exposing (Msg(..))
import Random
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
