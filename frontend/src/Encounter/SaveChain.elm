module Encounter.SaveChain exposing
    ( SaveChain, SaveOutcome, HpEffect(..)
    , EffectApply, EffectDuration(..), TurnRef(..), EffectSave
    , empty, isEffectivelyEmpty, needsDc, emptyEffect
    , applyResolvedHp, applyEffects, halfFailDamage
    , rawAmount
    , EffectContext, resolveDuration
    , immunityName, isImmune, grantImmunity
    )

{-| Save Chain: a reusable "creature makes a save; something
happens" bundle the GM can create once and re-apply through the
combat.

The domain type is intentionally small — it's the recipe, not
the resolution mechanism. A `SaveChain` names a save ability
(the target rolls this), an optional DC (the GM either fixes
the DC in the preset or enters it at apply-time), and two
outcomes (`onFail` / `onSuccess`). Each outcome may deal
damage, heal, or apply a condition — any combination, including
none-at-all which just marks a "the save happened but nothing
came of it" beat.

Damage / heal amounts are stored as raw text (`String`) so a
GM can save a preset with either a fixed value (`"28"`) or a
dice formula (`"8d6"`). The Update layer resolves the text at
apply time — an integer applies directly, a dice formula rolls
first and the total lands via `SaveChainApplyRollLanded`.

The `HpEffect.HalfFailDamage` variant is a success-side hint:
resolve the fail's raw text (rolling if it's a formula), then
halve the resulting integer. Independent from any prior Fail
apply so a GM can click Pass without having clicked Fail first.

@docs SaveChain, SaveOutcome, HpEffect
@docs EffectApply, EffectDuration, TurnRef, EffectSave
@docs empty, isEffectivelyEmpty, needsDc, emptyEffect
@docs applyResolvedHp, applyEffects, halfFailDamage
@docs rawAmount
@docs EffectContext, resolveDuration
@docs immunityName, isImmune, grantImmunity

-}

import Compendium exposing (Ability(..))
import Encounter
import HpChange


{-| A saved chain the GM can pick from a dropdown. `name` is
`""` on a fresh new chain — the GM must fill it in to save the
recipe, but they can still apply an unnamed chain one-shot.
`saveDc` is `Nothing` for chains authored without a fixed DC;
the editor asks for one before a Save-to-end effect can apply.
`immunity` is the grant a successful save carries — the target
can't be affected by this chain again for that long — or
`Nothing` when the effect grants none.
-}
type alias SaveChain =
    { name : String
    , saveAbility : Ability
    , saveDc : Maybe Int
    , onFail : SaveOutcome
    , onSuccess : SaveOutcome
    , immunity : Maybe EffectDuration
    }


{-| One side of the chain: what happens on a failed (or
successful) save. Both fields are independent — a spell can
deal damage AND apply a condition (Phantasmal Killer), or just
one, or neither.
-}
type alias SaveOutcome =
    { hp : HpEffect

    -- Zero-or-more conditions / effects to apply.  Each has a
    -- name (matched against the standard 5e list in the view,
    -- or free-form for spells like Banishment / Slow /
    -- Confusion whose effects don't map cleanly to a 5e
    -- condition) and an optional note carried onto the
    -- applied condition.  Multi-condition spells like
    -- Hypnotic Pattern (Charmed + Incapacitated) apply as a
    -- list; single-effect spells are a one-element list;
    -- damage-only outcomes are `[]`.
    , effects : List EffectApply
    }


{-| One condition / effect entry. Name may reference a
standard 5e condition (Blinded, Paralyzed, etc.) or a
free-form label ("Banished", "Slowed", "Hexed by Bestow
Curse", etc.) for spells whose in-game effect isn't part of
the 5e condition list. Note is optional flavour or a
reminder of the ongoing mechanic.

`duration` is how long the applied condition lasts, in the
Condition editor's terms but relative to the creatures at hand,
since a preset can't name them; `resolveDuration` settles it at
apply time.

`saveToEnd` opts this effect into the save-to-end mechanic:

  - `Nothing` — no automatic re-save; the applied condition
    lasts out its duration or until the GM removes it. Used
    for effects like Hypnotic Pattern's Charmed (ends on
    damage, not a save) or Suggestion (no re-save at all).
  - `Just save` — the applied condition inherits the chain's
    save ability + DC (Hold Person's WIS DC 15, etc.) and
    fires per the save's `AutoRollMode`, with its failed-save
    outcome along for the ride.

-}
type alias EffectApply =
    { name : String
    , note : String
    , duration : EffectDuration
    , saveToEnd : Maybe EffectSave
    }


{-| How long an applied effect lasts, mirroring the Condition
editor's choices. A preset can't name the creature an
"until turn" refers to, so it names a role instead.
-}
type EffectDuration
    = LastsUntilRemoved
    | LastsUntilTurn Encounter.TurnPhase TurnRef
    | LastsForTurns Encounter.TurnPhase Int
    | LastsOneMinute


{-| Whose turn an "until turn" duration watches: the creature
the effect lands on, the creature whose turn it is when the
chain applies (the caster, for a monster's own ability), or a
named creature for a one-off chain.
-}
type TurnRef
    = TurnOfBearer
    | TurnOfActive
    | TurnOf String


{-| The save-to-end an effect opts into: when it rolls, and what
a failure does beyond leaving the condition in place.
-}
type alias EffectSave =
    { autoRoll : Encounter.AutoRollMode
    , onFail : Encounter.FailedSave
    }


{-| HP side of an outcome. `NoHpEffect` is the default — most
condition-apply chains don't touch HP at all.

`DealDamage` and `HealFor` carry the raw text the GM typed:
either a plain integer (`"28"`) applied as-is, or a dice
formula (`"8d6"`) rolled at apply time.

`HalfFailDamage` is a success-side sentinel — the Update layer
resolves the fail's raw text (rolling if it's a formula) and
halves the resulting integer.

-}
type HpEffect
    = NoHpEffect
    | DealDamage String
    | HealFor String
    | HalfFailDamage


{-| Bare chain used as the modal's starting point when the GM
hits "+ New". Wisdom is the most-common save ability across
the spell list; picking it as the default saves a click on the
common case.
-}
empty : SaveChain
empty =
    { name = ""
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = emptyOutcome
    , onSuccess = emptyOutcome
    , immunity = Nothing
    }


emptyOutcome : SaveOutcome
emptyOutcome =
    { hp = NoHpEffect
    , effects = []
    }


{-| Bare effect used as the initial value when the "+ Add
effect" button pushes a new row onto an outcome's list.
-}
emptyEffect : EffectApply
emptyEffect =
    { name = "", note = "", duration = LastsUntilRemoved, saveToEnd = Nothing }


{-| True iff a chain has no effects on either side. Used by
the modal to grey out the Apply buttons — clicking a chain
that literally does nothing is almost always a mistake.
-}
isEffectivelyEmpty : SaveChain -> Bool
isEffectivelyEmpty chain =
    isOutcomeEmpty chain.onFail && isOutcomeEmpty chain.onSuccess


isOutcomeEmpty : SaveOutcome -> Bool
isOutcomeEmpty o =
    hpEffectIsEmpty o.hp
        && List.all effectIsBlank o.effects


effectIsBlank : EffectApply -> Bool
effectIsBlank e =
    String.isEmpty (String.trim e.name)


{-| True iff an effect on either side opts into Save-to-end. Such
a chain needs a DC before it can be applied: without one the
effect would land as a plain condition and never roll.
-}
needsDc : SaveChain -> Bool
needsDc chain =
    List.any (\e -> e.saveToEnd /= Nothing)
        (chain.onFail.effects ++ chain.onSuccess.effects)


hpEffectIsEmpty : HpEffect -> Bool
hpEffectIsEmpty h =
    case h of
        NoHpEffect ->
            True

        DealDamage s ->
            String.isEmpty (String.trim s)

        HealFor s ->
            String.isEmpty (String.trim s)

        HalfFailDamage ->
            False


{-| Extract the raw amount text (or `""`) for the parse-and-
resolve step in the Update layer.
-}
rawAmount : HpEffect -> String
rawAmount h =
    case h of
        NoHpEffect ->
            ""

        DealDamage s ->
            s

        HealFor s ->
            s

        HalfFailDamage ->
            ""


{-| Apply an already-resolved HP amount to a target creature.
The Update layer parses `outcome.hp`'s raw text (rolling if
it's a dice formula), then hands the resulting integer here.
Composes through the shared `HpChange` engine so bloodied
recomputation + death-save clearing behave identically to the
Manage HP modal.

`NoHpEffect` is a no-op. `HalfFailDamage` is treated the same
as `DealDamage` (both apply damage); the caller has already
halved the fail amount by the time it lands here.

-}
applyResolvedHp :
    HpEffect
    -> Int
    -> String
    -> Encounter.Encounter
    -> Encounter.Encounter
applyResolvedHp hp amount target enc =
    case hp of
        NoHpEffect ->
            enc

        HealFor _ ->
            Encounter.mapCreature target
                (HpChange.apply (HpChange.Heal amount))
                enc

        DealDamage _ ->
            Encounter.mapCreature target
                (HpChange.apply (HpChange.Damage amount))
                enc

        HalfFailDamage ->
            Encounter.mapCreature target
                (HpChange.apply (HpChange.Damage amount))
                enc


{-| Apply every effect on an outcome to a target creature,
walking left-to-right through the list. Each non-blank entry
becomes a fresh `ConditionDraft`; blank names are skipped so an
editor row left half-filled doesn't leak in.
-}
applyEffects :
    EffectContext
    -> SaveOutcome
    -> String
    -> Encounter.Encounter
    -> Encounter.Encounter
applyEffects ctx outcome target enc =
    List.foldl (applyEffect ctx target) enc outcome.effects


{-| The update layer's per-apply context supplied to the
domain: the chain's save ability (as an uppercase string
matching the Condition modal's `saveToEnd.ability`), an
optional DC, a per-target save-bonus resolver, and the active
creature's name, which an "until the active creature's turn"
duration resolves against. When the chain has no DC
(`saveDc = Nothing`) the domain refuses to build a `SaveToEnd`
even if the effect opts in — better to skip silently than
attach a DC-less save-to-end that would never resolve.
-}
type alias EffectContext =
    { saveAbility : String
    , saveDc : Maybe Int
    , bonusFor : String -> Int
    , activeName : String
    }


applyEffect :
    EffectContext
    -> String
    -> EffectApply
    -> Encounter.Encounter
    -> Encounter.Encounter
applyEffect ctx target effect enc =
    let
        trimmedName =
            String.trim effect.name
    in
    if String.isEmpty trimmedName then
        enc

    else
        Encounter.addCondition target
            { name = trimmedName
            , note = String.trim effect.note
            , duration = resolveDuration ctx.activeName target effect.duration
            , saveToEnd = resolveSaveToEnd ctx target effect
            }
            enc


resolveSaveToEnd :
    EffectContext
    -> String
    -> EffectApply
    -> Maybe Encounter.SaveToEnd
resolveSaveToEnd ctx target effect =
    case ( effect.saveToEnd, ctx.saveDc ) of
        ( Just save, Just dc ) ->
            Just
                { ability = ctx.saveAbility
                , dc = dc
                , bonus = ctx.bonusFor target
                , autoRoll = save.autoRoll
                , onFail = save.onFail
                }

        _ ->
            Nothing


{-| Settle a preset's duration against the creatures at hand —
the bearer the effect lands on and whoever is active — into the
concrete duration the card tracks. An "until turn" watched on
the active creature's own end of turn means its next one, not
the one about to end; a countdown ticking at the end of the
bearer's own turn skips the end that is moments away. Both are
the Condition editor's rules.
-}
resolveDuration : String -> String -> EffectDuration -> Encounter.Duration
resolveDuration activeName bearer duration =
    case duration of
        LastsUntilRemoved ->
            Encounter.DurationManual

        LastsUntilTurn phase ref ->
            let
                name =
                    case ref of
                        TurnOfBearer ->
                            bearer

                        TurnOfActive ->
                            if String.isEmpty activeName then
                                bearer

                            else
                                activeName

                        TurnOf named ->
                            named

                target =
                    if name == activeName && phase == Encounter.AtEnd then
                        Encounter.OnNextTurn

                    else
                        Encounter.OnCurrentTurn
            in
            Encounter.DurationUntilTurn phase target name

        LastsForTurns phase turns ->
            Encounter.DurationCountdown phase turns (skipsFirstTick activeName bearer phase)

        LastsOneMinute ->
            Encounter.DurationCountdown Encounter.AtEnd 10 (skipsFirstTick activeName bearer Encounter.AtEnd)


skipsFirstTick : String -> String -> Encounter.TurnPhase -> Bool
skipsFirstTick activeName bearer phase =
    phase == Encounter.AtEnd && bearer == activeName


{-| The condition a granted immunity lives on as, named for the
chain so the chain can find it again.
-}
immunityName : SaveChain -> String
immunityName chain =
    "Immune: "
        ++ (if String.isEmpty (String.trim chain.name) then
                "this effect"

            else
                String.trim chain.name
           )


{-| True iff the named creature carries this chain's immunity.
-}
isImmune : SaveChain -> String -> Encounter.Encounter -> Bool
isImmune chain target enc =
    enc.creatures
        |> List.any
            (\c ->
                c.name
                    == target
                    && List.any (\cond -> cond.name == immunityName chain) c.conditions
            )


{-| Grant the chain's immunity, if it has one, to a creature that
just succeeded on the save.
-}
grantImmunity : String -> SaveChain -> String -> Encounter.Encounter -> Encounter.Encounter
grantImmunity activeName chain target enc =
    case chain.immunity of
        Just duration ->
            Encounter.addCondition target
                { name = immunityName chain
                , note = ""
                , duration = resolveDuration activeName target duration
                , saveToEnd = Nothing
                }
                enc

        Nothing ->
            enc


{-| Compute "half fail damage, rounded down" the same way 5e
does for save-for-half spells.
-}
halfFailDamage : Int -> Int
halfFailDamage n =
    Basics.max 0 (n // 2)
