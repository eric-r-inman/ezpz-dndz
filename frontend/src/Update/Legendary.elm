module Update.Legendary exposing (toggleSpecialReaction, useAction, useResistance)

{-| Update branches for the legendary-action and
legendary-resistance readouts on creature cards, plus the
special-reaction badges beside them.

The 5e rule that LA and reactions refresh at the start of the
creature's turn is enforced separately by
`Encounter.Lifecycle.applyBeginOfTurn`, which clears
`legendaryActionsUsed` and `specialReactionsUsed` when the
creature becomes active. LR deliberately doesn't auto-reset (it's
per long rest in the rules, not per turn), which is why clicking
a spent readout refills it.

-}

import Encounter exposing (Creature, Encounter)
import Model exposing (Model)
import Msg exposing (Msg)
import Set exposing (Set)


withEncounter : (Encounter -> Encounter) -> Model -> Model
withEncounter fn model =
    { model | encounter = fn model.encounter }


useAction : String -> Model -> ( Model, Cmd Msg )
useAction name model =
    ( withEncounter
        (Encounter.mapCreature name
            (\c ->
                { c
                    | legendaryActionsUsed =
                        spend (c.legendaryActionsCount + c.legendaryActionsLairBonus)
                            c.legendaryActionsUsed
                }
            )
        )
        model
    , Cmd.none
    )


useResistance : String -> Model -> ( Model, Cmd Msg )
useResistance name model =
    ( withEncounter
        (Encounter.mapCreature name
            (\c ->
                { c
                    | legendaryResistanceUsed =
                        spend (c.legendaryResistanceCount + c.legendaryResistanceLairBonus)
                            c.legendaryResistanceUsed
                }
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


{-| One more use, or a full pool once the last one is spent — the
readout is a single control, so clicking past empty is how the GM
refills it. The set's members carry no meaning beyond how many
there are, so it is rebuilt from the new count rather than added
to, which also settles any set an older build left behind.
-}
spend : Int -> Set Int -> Set Int
spend capacity used =
    if Set.size used >= capacity then
        Set.empty

    else
        Set.fromList (List.range 0 (Set.size used))
