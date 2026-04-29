module HpChange exposing
    ( Change(..), DamageSpec
    , apply, describe
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

-}

import Encounter exposing (Creature)



-- TYPES


{-| One unit of HP change to apply to a creature. The amount is
treated as already-resolved; if you wanted to roll for it, do that
upstream and pass the integer total.

  - `Damage` follows 5e order-of-operations: temp HP absorbs first
    (unless `ignoreTemp` is set, which models effects like force
    damage to a temporary-HP-granting spell that bypasses the buffer),
    then the remainder reduces `currentHp`. Current HP is clamped at
    0; we don't auto-flip `inDeathSaves` because the JS app didn't
    either — the user toggles death-save tracking manually via the
    row 2 ○/💀 slots.

  - `Heal` adds to `currentHp`, capped at `maxHp`. Doesn't touch
    `tempHp` (5e: temp HP is its own pool). If healing brings a
    creature from 0 HP to positive, also clears `inDeathSaves` and
    the three death-save slots — matches the JS app's behavior and
    saves the GM a couple of clicks at the table.

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
heal.
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
0 because of this heal, also clear the three death-save slots and
the `inDeathSaves` flag — they're meaningless once you're conscious.
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
            , inDeathSaves = False
            , deathSaves = ( False, False, False )
        }

    else
        { c | currentHp = afterHp }


{-| Temp HP: replace-if-higher. Never stacks. Negative inputs are
clamped to zero.
-}
applyTempHp : Int -> Creature -> Creature
applyTempHp n c =
    { c | tempHp = Basics.max c.tempHp (Basics.max 0 n) }


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
