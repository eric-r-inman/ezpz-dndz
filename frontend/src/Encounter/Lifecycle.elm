module Encounter.Lifecycle exposing (nextTurn, applyBeginOfTurn, applyEndOfTurn)

{-| Turn-progression machinery for the encounter manager.

Owns the public `nextTurn` entry point plus the begin/end-of-turn
hooks that bracket the queue walk. Pulled out of `Encounter.elm`
so the rules-engine root file is shorter and the lifecycle helpers
can grow new phases (off-turn, reaction-window, etc.) without
crowding the value-type definitions.

The hooks are pure `Encounter -> Encounter` and don't fire `Cmd`s
— side effects like auto-roll saves live one layer up in
`Main.update`'s `NextTurn` branch.

@docs nextTurn, applyBeginOfTurn, applyEndOfTurn

-}

import Encounter
    exposing
        ( Condition
        , Cover(..)
        , Creature
        , Duration(..)
        , Encounter
        , TurnPhase(..)
        , TurnTarget(..)
        )
import Encounter.DeathSaves
import Encounter.SaveNotice
import Set


{-| Advance the turn marker by one slot.

In initiative order: the current creature's successor becomes
active. When the marker would step off the end of the queue it
wraps back to the first creature, which marks the start of a new
combat round, so `round` increments.

**Skip rules**: a creature is skipped if any of the following hold:

  - three failed death saves (dead);
  - downed (`currentHp == 0`) with `acceptingDeathSaves = False` —
    the GM hasn't opted into running the death-save clock for
    this creature, so they're effectively out of combat. Once the
    GM clicks the "Death Saves" button on the card the flag flips
    and the creature is back in the rotation; healing above 0
    also reverses both bits;
  - explicitly marked inactive (via the card's ∅ toggle).

The marker keeps walking past skipped creatures on every
subsequent Next Turn. Dead state isn't cleared automatically;
inactive state only clears when the user toggles the button
back off; the downed-without-opt-in state clears via the heal /
opt-in paths just described. An iteration cap of `length creatures`
protects the all-skipped edge case (TPK, or all-inactive while the
GM is setting up an encounter).

In addition to the queue walk, this fires two condition hooks
once per Next Turn click: end-of-turn for the OUTGOING active
creature, then begin-of-turn for the INCOMING (post-skip) active
creature.

-}
nextTurn : Encounter -> Encounter
nextTurn enc =
    enc
        |> applyEndOfTurn enc.activeName
        |> skipUnplayable (List.length enc.creatures)
        |> applyBeginOfTurnHook


skipUnplayable : Int -> Encounter -> Encounter
skipUnplayable budget enc =
    if budget <= 0 then
        enc

    else
        let
            advanced =
                advanceOne enc
        in
        case findByName advanced.activeName advanced.creatures of
            Just c ->
                if isUnplayable c then
                    skipUnplayable (budget - 1) advanced

                else
                    advanced

            Nothing ->
                advanced


{-| One creature's "skip this slot" predicate. Pulled out so the
three skip reasons read as a single OR rather than a dense inline
conditional.
-}
isUnplayable : Encounter.Creature -> Bool
isUnplayable c =
    Encounter.DeathSaves.isDead c.deathSaves
        || c.inactive
        || (c.currentHp == 0 && not c.acceptingDeathSaves)


applyBeginOfTurnHook : Encounter -> Encounter
applyBeginOfTurnHook enc =
    applyBeginOfTurn enc.activeName enc


{-| End-of-turn hook for the named creature: tick down their own
`DurationCountdown AtEnd` conditions, expire any
`DurationUntilTurn AtEnd <name>` across the whole encounter, and
decrement save notices.
-}
applyEndOfTurn : String -> Encounter -> Encounter
applyEndOfTurn name enc =
    enc
        |> tickCountdownFor name AtEnd
        |> tickSaveNoticesFor name
        |> tickTimerFor name AtEnd
        |> expireUntilTurn AtEnd name


tickSaveNoticesFor : String -> Encounter -> Encounter
tickSaveNoticesFor name enc =
    Encounter.mapCreature name
        (\c -> { c | saveNotices = Encounter.SaveNotice.tickList c.saveNotices })
        enc


tickTimerFor : String -> TurnPhase -> Encounter -> Encounter
tickTimerFor name phase enc =
    Encounter.mapCreature name
        (\c ->
            case c.timer of
                Just t ->
                    if t.ringing || t.phase /= phase then
                        c

                    else
                        let
                            nextRemaining =
                                t.remaining - 1
                        in
                        if nextRemaining <= 0 then
                            { c | timer = Just { t | remaining = 0, ringing = True } }

                        else
                            { c | timer = Just { t | remaining = nextRemaining } }

                Nothing ->
                    c
        )
        enc


{-| Begin-of-turn hook for the named creature. Symmetric to
`applyEndOfTurn` but for `AtBegin` durations, plus:

  - **Legendary-action reset** — the LA pip column returns to "all
    available", mirroring the 5e rule that a legendary creature
    regains expended legendary actions at the start of its turn.
    Legendary resistances do NOT reset (per long rest).
  - **Reaction reset** — `reactionUsed` flips back to False so
    the creature has a fresh reaction for the new round.

-}
applyBeginOfTurn : String -> Encounter -> Encounter
applyBeginOfTurn name enc =
    enc
        |> tickCountdownFor name AtBegin
        |> tickTimerFor name AtBegin
        |> expireUntilTurn AtBegin name
        |> resetLegendaryActionsFor name
        |> resetReactionFor name
        |> markSpentRechargesPendingFor name


resetLegendaryActionsFor : String -> Encounter -> Encounter
resetLegendaryActionsFor name enc =
    Encounter.mapCreature name
        (\c -> { c | legendaryActionsUsed = Set.empty })
        enc


resetReactionFor : String -> Encounter -> Encounter
resetReactionFor name enc =
    Encounter.mapCreature name
        (\c -> { c | reactionUsed = False })
        enc


{-| Flip `awaitingRoll = True` for any of the active creature's
recharge abilities that are currently spent. This is what makes
the blinking dice appear at the START of the creature's next
turn — spending an ability mid-turn leaves `awaitingRoll = False`
so the dice doesn't pop up on the same turn. Ready abilities are
unaffected.
-}
markSpentRechargesPendingFor : String -> Encounter -> Encounter
markSpentRechargesPendingFor name enc =
    Encounter.mapCreature name
        (\c ->
            { c
                | rechargeAbilities =
                    List.map
                        (\a ->
                            if a.ready then
                                a

                            else
                                { a | awaitingRoll = True }
                        )
                        c.rechargeAbilities
            }
        )
        enc


tickCountdownFor : String -> TurnPhase -> Encounter -> Encounter
tickCountdownFor name phase enc =
    Encounter.mapCreature name (\c -> { c | conditions = List.filterMap (tickCondition phase) c.conditions }) enc


tickCondition : TurnPhase -> Condition -> Maybe Condition
tickCondition phase cond =
    case cond.duration of
        DurationCountdown condPhase remaining skipNextTick ->
            if condPhase /= phase then
                Just cond

            else if skipNextTick then
                Just { cond | duration = DurationCountdown condPhase remaining False }

            else
                let
                    next =
                        remaining - 1
                in
                if next <= 0 then
                    Nothing

                else
                    Just { cond | duration = DurationCountdown condPhase next False }

        _ ->
            Just cond


expireUntilTurn : TurnPhase -> String -> Encounter -> Encounter
expireUntilTurn phase name enc =
    { enc
        | creatures =
            List.map
                (\c ->
                    { c | conditions = List.filterMap (advanceUntilTurn phase name) c.conditions }
                )
                enc.creatures
    }


advanceUntilTurn : TurnPhase -> String -> Condition -> Maybe Condition
advanceUntilTurn phase name cond =
    case cond.duration of
        DurationUntilTurn condPhase target ref ->
            if condPhase == phase && ref == name then
                case target of
                    OnCurrentTurn ->
                        Nothing

                    OnNextTurn ->
                        Just { cond | duration = DurationUntilTurn condPhase OnCurrentTurn ref }

            else
                Just cond

        _ ->
            Just cond


advanceOne : Encounter -> Encounter
advanceOne enc =
    case enc.creatures of
        [] ->
            enc

        first :: _ ->
            let
                newActive =
                    findNext enc.activeName enc.creatures
                        |> Maybe.withDefault first.name

                wrapped =
                    isLastInQueue enc.activeName enc.creatures
            in
            { enc
                | activeName = newActive
                , round =
                    if wrapped then
                        enc.round + 1

                    else
                        enc.round
            }


findNext : String -> List Creature -> Maybe String
findNext currentName creatures =
    case creatures of
        [] ->
            Nothing

        c :: rest ->
            if c.name == currentName then
                List.head rest |> Maybe.map .name

            else
                findNext currentName rest


isLastInQueue : String -> List Creature -> Bool
isLastInQueue name creatures =
    case List.reverse creatures of
        [] ->
            False

        last :: _ ->
            last.name == name || findByName name creatures == Nothing


findByName : String -> List Creature -> Maybe Creature
findByName name creatures =
    case creatures of
        [] ->
            Nothing

        c :: rest ->
            if c.name == name then
                Just c

            else
                findByName name rest
