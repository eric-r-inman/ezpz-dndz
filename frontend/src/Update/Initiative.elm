module Update.Initiative exposing
    ( applySelected
    , applyTarget
    , autoRoll
    , close
    , customChanged
    , initiativeExpression
    , open
    , quickSort
    , rollsLanded
    , source
    )

{-| Update branches for the initiative manager modal: opening for a
specific creature, custom-value entry, the "sort by current
initiative" shortcut, the auto-roll batch (target / all / selected),
and the result handler that stamps rolled values onto creatures and
re-sorts the queue.
-}

import Dice
import Effects
import Encounter exposing (Creature)
import Encounter.Roster
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( Msg(..)
        , RollMode(..)
        , RollScope(..)
        )
import Random
import Ui.Initiative as InitiativeUi exposing (InitiativeUi)


{-| Apply `fn` to the open initiative-manager modal. No-op when
the modal is closed (or a different modal is open).
-}
withInitiative : (InitiativeUi -> InitiativeUi) -> Model -> Model
withInitiative =
    Model.mapModal Model.initiativeLens


open : String -> Model -> ( Model, Cmd Msg )
open target model =
    ( { model | modal = Just (ModalInitiative (InitiativeUi.fresh target)) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


customChanged : String -> Model -> ( Model, Cmd Msg )
customChanged text model =
    ( withInitiative (\u -> { u | customValueText = text }) model
    , Cmd.none
    )


quickSort : Model -> ( Model, Cmd Msg )
quickSort model =
    ( { model
        | encounter = Encounter.Roster.sortByInitiative model.encounter
        , modal = Nothing
      }
    , Cmd.none
    )


{-| Resolve which creatures the scope picks out and fire one
batched roll Cmd. Mode picks the per-creature generator
(standard 1d20+bonus vs. 2d20-keep-high+bonus). The handler
(`InitiativeRollsLanded`) is shape-agnostic — it works for
1-element or N-element batches and for either roll mode.
-}
autoRoll : RollScope -> RollMode -> Model -> ( Model, Cmd Msg )
autoRoll scope mode model =
    let
        creatures =
            case scope of
                ScopeTarget ->
                    case model.modal of
                        Just (ModalInitiative ui) ->
                            List.filter
                                (\c -> c.name == ui.target)
                                model.encounter.creatures

                        _ ->
                            []

                ScopeAll ->
                    model.encounter.creatures

                ScopeSelected ->
                    List.filter .selected model.encounter.creatures
    in
    ( model, initiativeRollCmd mode creatures )


{-| Manual override for one creature. Closes the modal whether or
not the value parsed; an unparsable input gets silently discarded
(same UX as the HP edit).
-}
applyTarget : Model -> ( Model, Cmd Msg )
applyTarget model =
    case model.modal of
        Just (ModalInitiative ui) ->
            ( applyCustomInitiative [ ui.target ] ui model
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


applySelected : Model -> ( Model, Cmd Msg )
applySelected model =
    case model.modal of
        Just (ModalInitiative ui) ->
            let
                targets =
                    List.filter .selected model.encounter.creatures
                        |> List.map .name
            in
            ( applyCustomInitiative targets ui model
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


{-| Fold each (creature name, roll) pair into a fresh `Model`:
stamp the rolled total onto the creature's initiative, push the
roll into the dice history. Then sort the queue, close the modal,
and persist all the rolls server-side. `mapCreature` silently
no-ops on unknown names so a stale roll (defensive) won't blow up.
-}
rollsLanded : List ( String, Dice.Roll ) -> Model -> ( Model, Cmd Msg )
rollsLanded results model =
    let
        applyOne ( name, roll ) m =
            { m
                | encounter =
                    Encounter.mapCreature name
                        (\c -> { c | initiative = roll.total })
                        m.encounter
            }
                |> Effects.pushDiceRoll roll

        m1 =
            List.foldl applyOne model results

        rolls =
            List.map Tuple.second results
    in
    ( { m1
        | encounter = Encounter.Roster.sortByInitiative m1.encounter
        , modal = Nothing
      }
    , Cmd.batch (List.map Effects.persistDiceRoll rolls)
    )



-- ── HELPERS ────────────────────────────────────────────────────────────


{-| Build a single batched dice Cmd that rolls initiative for each
creature in `creatures` using the chosen `mode`. Empty input →
`Cmd.none` (handles the "Selected" buttons being clicked when no
creatures are selected).
-}
initiativeRollCmd : RollMode -> List Creature -> Cmd Msg
initiativeRollCmd mode creatures =
    if List.isEmpty creatures then
        Cmd.none

    else
        Dice.batchRollCmd InitiativeRollsLanded
            (List.map
                (\c ->
                    ( c.name
                    , source c.name
                    , initiativeGenerator mode c
                    )
                )
                creatures
            )


{-| Pick the per-creature roll generator for the given mode.
Standard uses `Dice.generator` over a 1d20+bonus expression;
advantage / disadvantage delegate to `Dice.advantageGenerator` /
`Dice.disadvantageGenerator`, which natively handle the
2d20-keep-highest / 2d20-keep-lowest mechanic and tag the kept
die in the resulting `Roll.groups`.
-}
initiativeGenerator : RollMode -> Creature -> Random.Generator Dice.Roll
initiativeGenerator mode c =
    case mode of
        ModeStandard ->
            Dice.generator (initiativeExpression c.initiativeBonus)

        ModeAdvantage ->
            Dice.advantageGenerator c.initiativeBonus

        ModeDisadvantage ->
            Dice.disadvantageGenerator c.initiativeBonus


{-| `1d20 + bonus`, the standard 5e initiative roll. Takes the
bonus directly so it serves both Encounter.Creature and
Compendium.Creature flows (which share the field name but not the
record type). Canonical owner per the modularization plan.
-}
initiativeExpression : Int -> Dice.Expression
initiativeExpression bonus =
    { dice =
        [ { count = 1, faces = 20, sign = Dice.Positive } ]
    , constant = bonus
    , damageType = Nothing
    }


{-| Source label for initiative rolls so the dice history shows
"Initiative → <creature>". Exposed so the compendium-add path
can use the same label for newly-spawned creatures' initial rolls.
-}
source : String -> Dice.Source
source name =
    { feature = "Initiative", target = Just name }


{-| Custom-initiative apply path: parse the modal's text input, set
each named creature's initiative to that value, sort the queue,
close the modal. An unparseable text just closes the modal without
mutating anything.
-}
applyCustomInitiative : List String -> InitiativeUi -> Model -> Model
applyCustomInitiative names ui model =
    case String.toInt (String.trim ui.customValueText) of
        Just n ->
            let
                applyOne name m =
                    { m
                        | encounter =
                            Encounter.mapCreature name
                                (\c -> { c | initiative = n })
                                m.encounter
                    }

                m1 =
                    List.foldl applyOne model names
            in
            { m1
                | encounter = Encounter.Roster.sortByInitiative m1.encounter
                , modal = Nothing
            }

        Nothing ->
            { model | modal = Nothing }
