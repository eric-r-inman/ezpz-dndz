module Encounter.DeathSaves exposing
    ( DeathSaves
    , empty
    , addSuccesses, addFailures
    , isStable, isDead
    )

{-| 5e death-save tracker. Self-contained value object: carries no
reference to the parent `Creature` or `Encounter`, so the helpers
here are pure transformations on the running counts. The
encounter-level wiring (auto-trigger when `currentHp == 0`,
auto-clear on heal-to-positive) lives in `HpChange.elm` and the
view layer.


# Type

@docs DeathSaves


# Constructors

@docs empty


# Mutations (clamped to 0..3)

@docs addSuccesses, addFailures


# Derived states

@docs isStable, isDead

-}


{-| Running counts of successful and failed death saves.

Three successes → stable (still at 0 HP, but no more rolls).
Three failures → dead.

5e d20 resolution:

  - 10+ → success
  - 9 or less → failure
  - natural 20 → revive at 1 HP (handled outside this type, in
    the HP-change engine)
  - natural 1 → counts as two failures

-}
type alias DeathSaves =
    { successes : Int
    , failures : Int
    }


{-| Fresh tracker — zero successes, zero failures. Used to reset
on heal-to-positive, on revive (nat 20), and as the default for
new combatants.
-}
empty : DeathSaves
empty =
    { successes = 0, failures = 0 }


{-| Add `n` successes (negative `n` removes). Clamped to 0..3 so
the pip group never overflows or goes negative.
-}
addSuccesses : Int -> DeathSaves -> DeathSaves
addSuccesses n ds =
    { ds | successes = clampPip (ds.successes + n) }


{-| Add `n` failures (negative `n` removes). Clamped to 0..3.
A natural-1 d20 in 5e adds 2 — pass `n = 2` for that.
-}
addFailures : Int -> DeathSaves -> DeathSaves
addFailures n ds =
    { ds | failures = clampPip (ds.failures + n) }


{-| Three successes → stabilized. Still unconscious at 0 HP, but
no more death rolls. The view code uses this to grey out the
pip group and show a "Stable" badge.
-}
isStable : DeathSaves -> Bool
isStable ds =
    ds.successes >= 3 && ds.failures < 3


{-| Three failures → dead. The view shows a skull badge and
disables further automated interaction; a heal still revives via
the HP-change engine (PCs do come back from "dead" if a player
has a revivify spell scroll, etc., so we don't lock the heal
path).
-}
isDead : DeathSaves -> Bool
isDead ds =
    ds.failures >= 3


clampPip : Int -> Int
clampPip n =
    Basics.max 0 (Basics.min 3 n)
