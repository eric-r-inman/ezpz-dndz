module Update.Compendium.Add exposing (addToQueue, initiativeRolled)

{-| Add-to-queue flow for the compendium browser: the GM picks a
creature + a count (`addCountChanged` lives in `Browser`), clicks
Add, and we fire a single batched initiative roll Cmd. When the
rolls land, `initiativeRolled` materialises one creature instance
per result, appends them, and closes the browser modal with a
success toast.

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


{-| Resolve the selected compendium creature, build N auto-numbered
initiative roll specs, and dispatch a single batched Cmd. The
handler closes over `creatureId` so when the rolls land we can
look the source back up to spawn instances against the
freshly-rolled values.
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

                        names =
                            pickInstanceNames source.name model.compendium.addCount existing

                        specs =
                            List.map (instanceSpec source) names
                    in
                    Dice.batchRollCmd
                        (CompendiumInitiativeRolled creatureId)
                        specs

                Nothing ->
                    Cmd.none

        _ ->
            Cmd.none


{-| Generate `count` unique display names for new instances of
`base`, threading the running set of reserved names through so each
new pick honors prior picks within the same batch. So adding three
Goblins to a fresh queue yields `Goblin / Goblin 2 / Goblin 3`.
-}
pickInstanceNames : String -> Int -> List String -> List String
pickInstanceNames base count existing =
    let
        loop n acc reserved =
            if n <= 0 then
                List.reverse acc

            else
                let
                    next =
                        Encounter.Roster.uniqueInstanceName base reserved
                in
                loop (n - 1) (next :: acc) (next :: reserved)
    in
    loop count [] existing


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

                        m1 =
                            List.foldl (\( _, r ) m -> Effects.pushDiceRoll r m) model rolls

                        addedCount =
                            List.length instances

                        toastMessage =
                            if addedCount == 1 then
                                "Added " ++ source.name ++ " to encounter"

                            else
                                "Added " ++ String.fromInt addedCount ++ " × " ++ source.name
                    in
                    { m1
                        | encounter = Encounter.Roster.appendCreatures instances m1.encounter
                        , compendium =
                            let
                                ui =
                                    m1.compendium
                            in
                            { ui | open = False }
                    }
                        |> Update.Toast.pushWith ToastSuccess
                            toastMessage
                            (Cmd.batch (List.map (\( _, r ) -> Effects.persistDiceRoll r) rolls))

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )
