module Update.HpChange exposing
    ( amountChanged
    , apply
    , applyToSelectedToggle
    , close
    , editCancel
    , editChange
    , editCommit
    , editStart
    , expressionChanged
    , ignoreTempToggle
    , modeSet
    , open
    , rollLanded
    )

{-| Update branches for the HP-change modal (damage / heal / temp HP)
and the inline HP edit pencil on each creature card.

The modal converges manual and dice-mode entry on a single
`applyHpChangeAndClose` step; both paths arrive at the engine with
an integer amount and a kind, the difference being that dice mode
takes a detour through `DiceRollLanded` to roll the expression
first.

-}

import Dice
import Effects
import Encounter exposing (Creature, Encounter)
import HpChange
import Model exposing (Model)
import Msg
    exposing
        ( HpField(..)
        , HpInputMode(..)
        , HpKind(..)
        , Msg(..)
        )
import Ui.HpChange as HpChangeUi exposing (HpChangeUi)


{-| Apply `fn` to the open HP-change modal. No-op when the modal is
closed (the field is `Nothing`).
-}
withHpChange : (HpChangeUi -> HpChangeUi) -> Model -> Model
withHpChange fn model =
    { model | hpChange = Maybe.map fn model.hpChange }


open : String -> HpKind -> Model -> ( Model, Cmd Msg )
open target kind model =
    ( { model | hpChange = Just (HpChangeUi.fresh target kind) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | hpChange = Nothing }, Cmd.none )


modeSet : HpInputMode -> Model -> ( Model, Cmd Msg )
modeSet mode model =
    ( withHpChange (\u -> { u | mode = mode, parseError = Nothing }) model
    , Cmd.none
    )


{-| Mirror the dice-modifier pattern: track raw text for the
controlled input, only update the parsed integer when the input
actually parses. Unsigned here — heal and temp-HP can't be
negative, and damage flips the sign internally via the engine.
-}
amountChanged : String -> Model -> ( Model, Cmd Msg )
amountChanged text model =
    ( withHpChange
        (\u ->
            { u
                | amountText = text
                , amount =
                    String.toInt (String.trim text)
                        |> Maybe.map (Basics.max 0)
                        |> Maybe.withDefault u.amount
            }
        )
        model
    , Cmd.none
    )


expressionChanged : String -> Model -> ( Model, Cmd Msg )
expressionChanged text model =
    ( withHpChange (\u -> { u | expression = text, parseError = Nothing }) model
    , Cmd.none
    )


ignoreTempToggle : Model -> ( Model, Cmd Msg )
ignoreTempToggle model =
    ( withHpChange (\u -> { u | ignoreTemp = not u.ignoreTemp }) model
    , Cmd.none
    )


applyToSelectedToggle : Model -> ( Model, Cmd Msg )
applyToSelectedToggle model =
    ( withHpChange (\u -> { u | applyToSelected = not u.applyToSelected }) model
    , Cmd.none
    )


{-| Manual mode commits ui.amount via the engine straight away.
Dice mode parses the expression and fires `Dice.rollCmd`; the
resulting roll comes back via `HpChangeRollLanded` which then
commits with the rolled total AND logs the roll to the dice
history. So both paths converge on a single
`applyHpChangeAndClose` step.
-}
apply : Model -> ( Model, Cmd Msg )
apply model =
    case model.hpChange of
        Nothing ->
            ( model, Cmd.none )

        Just ui ->
            case ui.mode of
                ManualMode ->
                    ( applyHpChangeAndClose ui ui.amount model
                    , Cmd.none
                    )

                DiceMode ->
                    case Dice.parse ui.expression of
                        Ok expr ->
                            ( model
                            , Dice.rollCmd HpChangeRollLanded
                                (hpChangeSource ui model.encounter)
                                expr
                            )

                        Err err ->
                            ( withHpChange (\u -> { u | parseError = Just err }) model
                            , Cmd.none
                            )


{-| The dice-mode path lands here. We commit the change with
`roll.total`, log the roll to the dice history (so the user has a
record), and persist it server-side through the same
`/api/dice/history` pipe the dice modal uses. If the modal got
closed mid-flight (defensive), still log/persist so we don't drop
rolls on the floor.
-}
rollLanded : Dice.Roll -> Model -> ( Model, Cmd Msg )
rollLanded roll model =
    let
        logged =
            Effects.pushDiceRoll roll model

        committed =
            case logged.hpChange of
                Just ui ->
                    applyHpChangeAndClose ui roll.total logged

                Nothing ->
                    logged
    in
    ( committed, Effects.persistDiceRoll roll )


editStart : String -> HpField -> Int -> Model -> ( Model, Cmd Msg )
editStart name field current model =
    ( { model
        | hpEdit =
            Just
                { target = name
                , field = field
                , text = String.fromInt current
                }
      }
    , Cmd.none
    )


editChange : String -> Model -> ( Model, Cmd Msg )
editChange text model =
    ( case model.hpEdit of
        Just edit ->
            { model | hpEdit = Just { edit | text = text } }

        Nothing ->
            model
    , Cmd.none
    )


{-| Parse the text. On success, write through HpChange's manual-edit
helpers (which clamp + recompute bloodied). On parse failure, just
close the editor without changing anything — easier than surfacing
a transient error inline.
-}
editCommit : Model -> ( Model, Cmd Msg )
editCommit model =
    case model.hpEdit of
        Nothing ->
            ( model, Cmd.none )

        Just edit ->
            case String.toInt (String.trim edit.text) of
                Just n ->
                    let
                        transform =
                            case edit.field of
                                CurrentHpField ->
                                    HpChange.setCurrentHp n

                                MaxHpField ->
                                    HpChange.setMaxHp n
                    in
                    ( { model
                        | encounter =
                            Encounter.mapCreature edit.target transform model.encounter
                        , hpEdit = Nothing
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( { model | hpEdit = Nothing }, Cmd.none )


editCancel : Model -> ( Model, Cmd Msg )
editCancel model =
    ( { model | hpEdit = Nothing }, Cmd.none )



-- ── HELPERS ────────────────────────────────────────────────────────────


{-| Build the `Dice.Source` label for an HP-change roll, so the dice
history reads "Damage → Brakka" or "Heal → Aria, Brakka".
-}
hpChangeSource : HpChangeUi -> Encounter -> Dice.Source
hpChangeSource ui enc =
    let
        feature =
            case ui.kind of
                DamageKind ->
                    "Damage"

                HealKind ->
                    "Heal"

                TempHpKind ->
                    "Temp HP"

        targetLabel =
            if ui.applyToSelected then
                let
                    names =
                        hpChangeTargets ui enc
                in
                if List.isEmpty names then
                    ui.target

                else
                    String.join ", " names

            else
                ui.target
    in
    { feature = feature, target = Just targetLabel }


{-| Resolve the modal's kind + flags into an `HpChange.Change`,
hand it to the engine, write the updated creature back through
`Encounter.mapCreature`, push a log entry capturing the before/after
snapshot, and close the modal. The caller decides the amount — it
comes from the manual input on the manual path or from the rolled
total on the dice path.

When `ui.applyToSelected` is True, the change is applied to every
selected creature (`Creature.selected = True`). Same amount across
all targets — for dice mode this means the GM rolled once and N
creatures soak the same total, which matches 5e's
single-roll-per-AOE convention (a Fireball rolls 8d6 once and each
target takes that much, not 8d6 per target).

When `applyToSelected` is False, only `ui.target` is affected (the
original single-card flow).

If no creatures match (no selection), the modal still closes
without applying to anyone — better than silently falling back to
`ui.target`, which would surprise the GM who explicitly checked the
multi-target toggle.

-}
applyHpChangeAndClose : HpChangeUi -> Int -> Model -> Model
applyHpChangeAndClose ui amount model =
    let
        change =
            case ui.kind of
                DamageKind ->
                    HpChange.Damage
                        { amount = amount
                        , ignoreTemp = ui.ignoreTemp
                        }

                HealKind ->
                    HpChange.Heal amount

                TempHpKind ->
                    HpChange.TempHp amount

        targets =
            hpChangeTargets ui model.encounter

        applyOne name acc =
            let
                before =
                    findCreature name acc.encounter

                newEnc =
                    Encounter.mapCreature name (HpChange.apply change) acc.encounter

                after =
                    findCreature name newEnc

                entry =
                    Maybe.map2
                        (\b a ->
                            { kind = ui.kind
                            , target = name
                            , amount = amount
                            , beforeHp = b.currentHp
                            , beforeTemp = b.tempHp
                            , afterHp = a.currentHp
                            , afterTemp = a.tempHp
                            }
                        )
                        before
                        after
            in
            { encounter = newEnc
            , log =
                case entry of
                    Just e ->
                        e :: acc.log

                    Nothing ->
                        acc.log
            }

        result =
            List.foldl applyOne { encounter = model.encounter, log = [] } targets
    in
    { model
        | encounter = result.encounter
        , hpChange = Nothing
        , hpChangeLog =
            List.reverse result.log
                ++ List.take (Basics.max 0 (HpChangeUi.maxHpLogEntries - List.length result.log)) model.hpChangeLog
    }


hpChangeTargets : HpChangeUi -> Encounter -> List String
hpChangeTargets ui enc =
    if ui.applyToSelected then
        enc.creatures
            |> List.filter .selected
            |> List.map .name

    else
        [ ui.target ]


findCreature : String -> Encounter -> Maybe Creature
findCreature name enc =
    List.filter (\c -> c.name == name) enc.creatures
        |> List.head
