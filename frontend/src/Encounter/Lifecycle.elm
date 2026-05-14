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

**Skip rules**: creatures with three failed death saves OR
explicitly marked inactive (via the card's ∅ toggle) are
skipped — the marker keeps walking past them on every
subsequent Next Turn. Dead state isn't cleared automatically;
inactive state only clears when the user toggles the button
back off. An iteration cap of `length creatures` protects the
all-skipped edge case (TPK, or all-inactive while the GM is
setting up an encounter).

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
                if Encounter.DeathSaves.isDead c.deathSaves || c.inactive then
                    skipUnplayable (budget - 1) advanced

                else
                    advanced

            Nothing ->
                advanced


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
`applyEndOfTurn` but for `AtBegin` durations, plus the legendary-
action reset so the LA pip column on the card returns to "all
available" — mirroring the 5e rule that a legendary creature
regains expended legendary actions at the start of its turn.
Legendary resistances do NOT reset (per long rest).
-}
applyBeginOfTurn : String -> Encounter -> Encounter
applyBeginOfTurn name enc =
    enc
        |> tickCountdownFor name AtBegin
        |> tickTimerFor name AtBegin
        |> expireUntilTurn AtBegin name
        |> resetLegendaryActionsFor name


resetLegendaryActionsFor : String -> Encounter -> Encounter
resetLegendaryActionsFor name enc =
    Encounter.mapCreature name
        (\c -> { c | legendaryActionsUsed = Set.empty })
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
