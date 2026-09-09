module Ui.DurationEdit exposing (apply, isOneMinute, kindOf, parseTurnRef, turnRefValue)

{-| The duration picker's editing rules, shared by the Save Chain
editor's effect and immunity pickers: how one control's change
folds into an `EffectDuration`, and the option values the "until"
select trades in.

@docs apply, isOneMinute, kindOf, parseTurnRef, turnRefValue

-}

import Encounter
import Encounter.SaveChain exposing (EffectDuration(..), TurnRef(..))
import Msg exposing (DurationEdit(..), DurationKind(..))


{-| Fold one picker change into a duration, carrying over the parts
the change didn't touch: switching to Countdown keeps a phase the
GM already picked, and typing a turn count keeps the phase.
-}
apply : DurationEdit -> EffectDuration -> EffectDuration
apply edit current =
    let
        ( phase, ref, turns ) =
            parts current
    in
    case edit of
        DurationKindPicked DurKindManual ->
            LastsUntilRemoved

        DurationKindPicked DurKindUntilTurn ->
            LastsUntilTurn phase ref

        DurationKindPicked DurKindCountdown ->
            LastsForTurns phase turns

        DurationOneMinutePicked ->
            LastsOneMinute

        DurationUntilRefPicked raw ->
            LastsUntilTurn phase (parseTurnRef raw)

        DurationUntilPhasePicked picked ->
            LastsUntilTurn picked ref

        DurationTurnsTyped text ->
            LastsForTurns phase
                (String.toInt (String.trim text)
                    |> Maybe.map (Basics.clamp 1 99)
                    |> Maybe.withDefault turns
                )

        DurationCountdownPhasePicked picked ->
            LastsForTurns picked turns


parts : EffectDuration -> ( Encounter.TurnPhase, TurnRef, Int )
parts duration =
    case duration of
        LastsUntilRemoved ->
            ( Encounter.AtEnd, TurnOfBearer, 1 )

        LastsUntilTurn phase ref ->
            ( phase, ref, 1 )

        LastsForTurns phase turns ->
            ( phase, TurnOfBearer, turns )

        LastsOneMinute ->
            ( Encounter.AtEnd, TurnOfBearer, 10 )


{-| The kind chip a duration lights. The 1-Minute preset counts as
a countdown here and lights its own chip through `isOneMinute`,
the way the Condition editor's preset flag does.
-}
kindOf : EffectDuration -> DurationKind
kindOf duration =
    case duration of
        LastsUntilRemoved ->
            DurKindManual

        LastsUntilTurn _ _ ->
            DurKindUntilTurn

        LastsForTurns _ _ ->
            DurKindCountdown

        LastsOneMinute ->
            DurKindCountdown


isOneMinute : EffectDuration -> Bool
isOneMinute duration =
    duration == LastsOneMinute


{-| The "until" select's option value for a reference. A creature
name carries a prefix so the two role words can't collide with
one.
-}
turnRefValue : TurnRef -> String
turnRefValue ref =
    case ref of
        TurnOfBearer ->
            "bearer"

        TurnOfActive ->
            "active"

        TurnOf name ->
            "name:" ++ name


parseTurnRef : String -> TurnRef
parseTurnRef raw =
    if raw == "active" then
        TurnOfActive

    else if String.startsWith "name:" raw then
        TurnOf (String.dropLeft 5 raw)

    else
        TurnOfBearer
