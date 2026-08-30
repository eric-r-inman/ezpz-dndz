module Update.LegendaryPip exposing (toggleAction, toggleResistance, toggleSpecialReaction)

{-| Update branches for the legendary-action and legendary-resistance
pip strips on creature cards, plus the special-reaction badges
beside them.

The 5e rule that LA and reactions refresh at the start of the
creature's turn is enforced separately by
`Encounter.Lifecycle.applyBeginOfTurn`, which clears
`legendaryActionsUsed` and `specialReactionsUsed` when the
creature becomes active. LR deliberately doesn't auto-reset (it's
per long rest in the rules, not per turn — the GM clears these
manually).

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


toggleSpecialReaction : String -> String -> Model -> ( Model, Cmd Msg )
toggleSpecialReaction name reaction model =
    ( withEncounter
        (Encounter.mapCreature name (Encounter.toggleSpecialReaction reaction))
        model
    , Cmd.none
    )


toggleSetMember : Int -> Set Int -> Set Int
toggleSetMember member set =
    if Set.member member set then
        Set.remove member set

    else
        Set.insert member set
