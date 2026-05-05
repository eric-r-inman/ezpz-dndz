module HpChange exposing
    ( Change(..), DamageSpec
    , apply, describe
    , setCurrentHp, setMaxHp, setArmorClass
    , restoreHp
    )

{-| HP-change engine.

A single pure entry point — [`apply`](#apply) — that the Damage,
Heal, and Temp HP buttons all funnel through. Centralizing the
arithmetic prevents the three buttons from drifting apart, and gives
us one place to change the rules later (e.g. add resistance /
vulnerability scaling, or auto-toggle the unconscious flag at 0 HP).

The engine is a pure `Change -> Creature -> Creature` transform; it
imports `Encounter` for the `Creature` shape but knows nothing about
how the change was authored (manual amount entry, dice roll, or a
future ongoing-effect tick). Callers resolve any randomness or
prompts upstream and hand the engine a final integer amount.


# Types

@docs Change, DamageSpec


# Apply

@docs apply, describe


# Manual edit helpers

@docs setCurrentHp, setMaxHp, setArmorClass


# Undo

@docs restoreHp

-}

import Encounter exposing (Creature)



-- TYPES


{-| One unit of HP change to apply to a creature. The amount is
treated as already-resolved; if you wanted to roll for it, do that
upstream and pass the integer total.

  - `Damage` follows 5e order-of-operations: temp HP absorbs first
    (unless `ignoreTemp` is set, which models effects like force
    damage to a temporary-HP-granting spell that bypasses the buffer),
    then the remainder reduces `currentHp` (clamped at zero, not
    negative). The death-save tracker shows automatically once
    `currentHp` is 0 (the view code reads that directly), so we
    don't need a side flag here.

  - `Heal` adds to `currentHp`, capped at `maxHp`. Doesn't touch
    `tempHp` (5e: temp HP is its own pool). If healing brings a
    creature from 0 HP to positive, also clears the death-save
    tracker — they're conscious again, so the running counts are
    meaningless.

  - `TempHp` follows 5e's "doesn't stack" rule — the new value
    replaces the existing `tempHp` only if greater. (Negative
    inputs are clamped to 0; we never silently subtract.)

-}
type Change
    = Damage DamageSpec
    | Heal Int
    | TempHp Int


{-| Damage parameters, broken out so the field names self-document
at call sites.

  - `amount` is the final pre-soak damage total.
  - `ignoreTemp` skips the temp-HP buffer when True.

-}
type alias DamageSpec =
    { amount : Int
    , ignoreTemp : Bool
    }



-- APPLY


{-| Apply one `Change` to a creature, returning the updated creature.

After the kind-specific arithmetic runs, the engine derives the
`bloodied` flag automatically: a creature is bloodied when alive
(>0 HP) and below half max HP. This was a manual flag in the seed
data; the JS app auto-tracks it, so we do too. If you want manual
control later, drop the `recomputeBloodied` step.

-}
apply : Change -> Creature -> Creature
apply change c =
    let
        afterChange =
            case change of
                Damage spec ->
                    applyDamage spec c

                Heal n ->
                    applyHeal n c

                TempHp n ->
                    applyTempHp n c
    in
    recomputeBloodied afterChange


{-| Damage: temp HP absorbs first, then current HP. Negative amounts
are clamped to zero so passing in a misparsed roll can't accidentally
heal. The death-save tracker becomes visible automatically once
`currentHp == 0` (handled in view code) — no flag bookkeeping
needed here.
-}
applyDamage : DamageSpec -> Creature -> Creature
applyDamage spec c =
    let
        incoming =
            Basics.max 0 spec.amount

        absorbed =
            if spec.ignoreTemp then
                0

            else
                Basics.min c.tempHp incoming

        remainder =
            incoming - absorbed
    in
    { c
        | tempHp = c.tempHp - absorbed
        , currentHp = Basics.max 0 (c.currentHp - remainder)
    }


{-| Heal: add, cap at maxHp. If a creature was at 0 and lands above
0 because of this heal, also clear the death-save tracker counts
— they're meaningless once you're conscious.
-}
applyHeal : Int -> Creature -> Creature
applyHeal n c =
    let
        amount =
            Basics.max 0 n

        before =
            c.currentHp

        afterHp =
            Basics.min c.maxHp (before + amount)

        revived =
            before <= 0 && afterHp > 0
    in
    if revived then
        { c
            | currentHp = afterHp
            , deathSaves = Encounter.emptyDeathSaves
        }

    else
        { c | currentHp = afterHp }


{-| Temp HP: replace-if-higher. Never stacks. Negative inputs are
clamped to zero.
-}
applyTempHp : Int -> Creature -> Creature
applyTempHp n c =
    { c | tempHp = Basics.max c.tempHp (Basics.max 0 n) }


{-| Manual GM override: write `currentHp` directly, clamped to
0..maxHp. Skips the rule-flavored side effects (no temp-HP soak, no
death-save clearing) — this is the "I just want to set it to 23"
button. Bloodied is still auto-recomputed so the badge stays
honest.
-}
setCurrentHp : Int -> Creature -> Creature
setCurrentHp n c =
    let
        clamped =
            Basics.max 0 (Basics.min c.maxHp n)
    in
    recomputeBloodied { c | currentHp = clamped }


{-| Manual GM override: write `maxHp` directly, clamped to >= 1.
If the new max is below `currentHp`, current follows down so the
invariant `currentHp <= maxHp` holds. Tempo HP is left alone (it's
its own pool).
-}
setMaxHp : Int -> Creature -> Creature
setMaxHp n c =
    let
        newMax =
            Basics.max 1 n
    in
    recomputeBloodied
        { c
            | maxHp = newMax
            , currentHp = Basics.min c.currentHp newMax
        }


{-| Manual GM override: write `armorClass` directly, clamped to
non-negative. Doesn't recompute anything else — AC is purely
descriptive on the card; it doesn't drive bloodied or HP rules.
-}
setArmorClass : Int -> Creature -> Creature
setArmorClass n c =
    { c | armorClass = Basics.max 0 n }


{-| Restore a creature's HP and temp-HP pools from a snapshot.
Used by the HP-change log's undo button — given the
`beforeHp` / `beforeTemp` captured at change-application time,
write them back through `setCurrentHp` (which re-clamps and
recomputes bloodied) so the creature returns to a known-valid
pre-change state.
-}
restoreHp : { hp : Int, tempHp : Int } -> Creature -> Creature
restoreHp before c =
    setCurrentHp before.hp { c | tempHp = Basics.max 0 before.tempHp }


{-| Recompute the bloodied flag from current vs. max HP.

A creature is bloodied iff alive (>0 HP) and at strictly less than
half their max HP. The "alive" gate matters because at 0 HP the
creature is unconscious / dying / dead — calling them "bloodied"
in addition to that would clutter the UI.

-}
recomputeBloodied : Creature -> Creature
recomputeBloodied c =
    { c
        | bloodied =
            c.currentHp
                > 0
                && (c.currentHp * 2 < c.maxHp)
    }



-- DESCRIBE


{-| Render a one-line human-readable summary of what a change did,
for the future event log / toast ("Brakka took 13 damage; 0 absorbed
by temp HP; 14 HP remaining"). Computed from the before/after
creature snapshots so it never disagrees with the actual mutation.

Not currently consumed by the UI but kept here so the engine owns
its own descriptions when we add a combat log.

-}
describe : Change -> Creature -> Creature -> String
describe change before after =
    case change of
        Damage spec ->
            let
                tempLost =
                    before.tempHp - after.tempHp

                hpLost =
                    before.currentHp - after.currentHp

                stem =
                    before.name
                        ++ " took "
                        ++ String.fromInt (Basics.max 0 spec.amount)
                        ++ " damage"

                tempPart =
                    if tempLost > 0 then
                        "; " ++ String.fromInt tempLost ++ " absorbed by temp HP"

                    else
                        ""

                outcome =
                    if after.currentHp <= 0 then
                        "; dropped to 0"

                    else if hpLost > 0 then
                        "; "
                            ++ String.fromInt after.currentHp
                            ++ "/"
                            ++ String.fromInt after.maxHp
                            ++ " remaining"

                    else
                        ""
            in
            stem ++ tempPart ++ outcome

        Heal _ ->
            let
                gained =
                    after.currentHp - before.currentHp
            in
            before.name
                ++ " healed "
                ++ String.fromInt gained
                ++ " ("
                ++ String.fromInt after.currentHp
                ++ "/"
                ++ String.fromInt after.maxHp
                ++ ")"

        TempHp _ ->
            let
                gained =
                    after.tempHp - before.tempHp
            in
            if gained > 0 then
                before.name ++ " gained " ++ String.fromInt gained ++ " temp HP (" ++ String.fromInt after.tempHp ++ " total)"

            else
                before.name ++ " kept existing temp HP (" ++ String.fromInt after.tempHp ++ ")"
