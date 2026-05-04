module Update.LegendaryPip exposing (toggleAction, toggleResistance)

{-| Update branches for the legendary-action and legendary-resistance
pip strips on creature cards.

The 5e rule that LA refresh at the start of the creature's turn is
enforced separately by `Encounter.Lifecycle.applyBeginOfTurn`,
which clears `legendaryActionsUsed` when the creature becomes
active. LR deliberately doesn't auto-reset (it's per long rest in
the rules, not per turn — the GM clears these manually).

-}

import Encounter exposing (Creature, Encounter)
import Model exposing (Model)
import Msg exposing (Msg)
import Set exposing (Set)


withEncounter : (Encounter -> Encounter) -> Model -> Model
withEncounter fn model =
    { model | encounter = fn model.encounter }


toggleAction : String -> Int -> Model -> ( Model, Cmd Msg )
toggleAction name idx model =
    ( withEncounter
        (Encounter.mapCreature name
            (\c ->
                { c | legendaryActionsUsed = toggleSetMember idx c.legendaryActionsUsed }
            )
        )
        model
    , Cmd.none
    )


toggleResistance : String -> Int -> Model -> ( Model, Cmd Msg )
toggleResistance name idx model =
    ( withEncounter
        (Encounter.mapCreature name
            (\c ->
                { c | legendaryResistanceUsed = toggleSetMember idx c.legendaryResistanceUsed }
            )
        )
        model
    , Cmd.none
    )


toggleSetMember : Int -> Set Int -> Set Int
toggleSetMember idx set =
    if Set.member idx set then
        Set.remove idx set

    else
        Set.insert idx set
