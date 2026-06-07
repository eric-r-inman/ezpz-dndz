module Encounter.RandomEncounter exposing
    ( TargetDifficulty(..), targetLabel, allTargets
    , Scale(..), scaleLabel, scaleWire, scaleFromWire, allScales
    , allCreatureTypes
    , GenParams, RollResult, generator
    , budgetFor
    )

{-| Random encounter generator.

The GM picks a party (reused from
[`Encounter.Difficulty`](Encounter-Difficulty)), a target
difficulty (Low / Moderate / High), a scale knob, an optional
habitat filter, an optional creature-type filter, and a "include
minions" toggle. This module turns that into a
`Random.Generator` that draws creature groups from the bundled
compendium sized to fit the party's XP budget.

The algorithm:

  - Filter the pool by habitat, creature type, and `xp > 0`.
  - Reserve 20% of the budget for minions if the toggle is on.
  - For the **main** group, pick a "target creatures-per-group"
    midpoint from the chosen Scale; prefer creatures whose XP
    lands within ±50% of `budget / midpoint`. Picked creature's
    count is `budget // xp` clamped to the Scale's range.
  - For the **minion** group (if on), pick one low-XP species
    (xp ≤ 100, ≈ CR ½ or less) and stuff 2–6 of them into the
    minion budget.

That's enough to produce believable encounters across "one big
fight", "a hunting band", and "a swarm of small things" without
the full 2024 DMG composition-template model. No `Html`, no
`Msg` — same discipline as `Encounter.Difficulty`.

@docs TargetDifficulty, targetLabel, allTargets
@docs Scale, scaleLabel, scaleWire, scaleFromWire, allScales
@docs allCreatureTypes
@docs GenParams, RollResult, generator
@docs budgetFor

-}

import Compendium exposing (Creature, Habitat)
import Encounter.Difficulty as Difficulty exposing (PartyMember)
import Random exposing (Generator)


{-| The three difficulty tiers a GM can ask the generator to
target. We deliberately omit `Trivial` (no real fight) and
`BeyondHigh` (no upper bound to aim at) — those exist for
post-hoc classification, not for generation.
-}
type TargetDifficulty
    = Low
    | Moderate
    | High


targetLabel : TargetDifficulty -> String
targetLabel t =
    case t of
        Low ->
            "Low"

        Moderate ->
            "Moderate"

        High ->
            "High"


allTargets : List TargetDifficulty
allTargets =
    [ Low, Moderate, High ]


{-| How chunky the rolled encounter should feel. Roughly:

  - `ScaleOne` — exactly 1 creature (boss / solo)
  - `ScaleFew` — 2–4 creatures (hunting band)
  - `ScaleMany` — 4+ creatures (swarm / mob)

The 4-creature overlap between Few and Many is intentional —
both buckets can land on 4 when the budget naturally fits there,
the difference is the _intent_ the GM expressed.

-}
type Scale
    = ScaleOne
    | ScaleFew
    | ScaleMany


scaleLabel : Scale -> String
scaleLabel s =
    case s of
        ScaleOne ->
            "One"

        ScaleFew ->
            "Few (2-4)"

        ScaleMany ->
            "Many (4+)"


scaleWire : Scale -> String
scaleWire s =
    case s of
        ScaleOne ->
            "one"

        ScaleFew ->
            "few"

        ScaleMany ->
            "many"


scaleFromWire : String -> Maybe Scale
scaleFromWire s =
    case s of
        "one" ->
            Just ScaleOne

        "few" ->
            Just ScaleFew

        "many" ->
            Just ScaleMany

        _ ->
            Nothing


allScales : List Scale
allScales =
    [ ScaleOne, ScaleFew, ScaleMany ]


{-| The 14 canonical 5e creature types. Hard-coded rather than
extracted from the compendium because the list is fixed by the
ruleset — extracting would just produce the same set with a
race condition against the boot fetch.
-}
allCreatureTypes : List String
allCreatureTypes =
    [ "Aberration"
    , "Beast"
    , "Celestial"
    , "Construct"
    , "Dragon"
    , "Elemental"
    , "Fey"
    , "Fiend"
    , "Giant"
    , "Humanoid"
    , "Monstrosity"
    , "Ooze"
    , "Plant"
    , "Undead"
    ]


{-| Look up the target XP for a party at a chosen difficulty.
Defers entirely to [`Encounter.Difficulty.partyBudget`](Encounter-Difficulty#partyBudget)
so a single source of truth governs both the calculator and the
generator.
-}
budgetFor : List PartyMember -> TargetDifficulty -> Int
budgetFor party target =
    let
        b =
            Difficulty.partyBudget party
    in
    case target of
        Low ->
            b.low

        Moderate ->
            b.moderate

        High ->
            b.high


{-| Bundle of generator inputs.

  - `budget` — total XP target derived from the party.
  - `habitat` — `Nothing` is Any (no filter).
  - `creatureTypes` — empty list is Any (no filter). A
    non-empty list restricts the main + minion picks to
    creatures whose race appears in the list (OR-of-types).
  - `scale` — drives the per-group count.
  - `includeMinions` — adds a low-XP species on top of the main
    group, sharing the budget 80/20.
  - `pinned` — `(creature, count)` pairs the GM has chosen to
    lock into the roll. Their combined XP is subtracted from
    the budget before the random fill runs; whatever's left
    is split between main and minions as usual. Pinned
    creatures bypass habitat and type filters because the GM
    explicitly asked for them.

-}
type alias GenParams =
    { budget : Int
    , habitat : Maybe Habitat
    , creatureTypes : List String
    , scale : Scale
    , includeMinions : Bool
    , pinned : List ( Creature, Int )
    }


{-| What the generator produces: a list of `(creature, count)`
groups. Empty list means the filtered pool was empty (no
creatures match the filters at the chosen budget) — the view
should show a "no matches" state rather than silently
generating nothing.
-}
type alias RollResult =
    List ( Creature, Int )


{-| The headline generator. Given params and the full
compendium, returns a `Random.Generator` for one encounter
draw. Re-rolling is "fire the generator again with the same
params"; this module owns no state.
-}
generator : GenParams -> List Creature -> Generator RollResult
generator params pool =
    let
        filtered =
            pool
                |> List.filter (matchesHabitat params.habitat)
                |> List.filter (matchesAnyType params.creatureTypes)
                |> List.filter (\c -> c.xp > 0)

        pinnedXp =
            List.foldl (\( c, n ) acc -> acc + c.xp * n) 0 params.pinned

        remaining =
            max 0 (params.budget - pinnedXp)

        ( mainBudget, minionBudget ) =
            if params.includeMinions then
                ( remaining * 4 // 5, remaining // 5 )

            else
                ( remaining, 0 )
    in
    if remaining == 0 then
        Random.constant params.pinned

    else
        pickMain params.scale mainBudget filtered
            |> Random.andThen
                (\main ->
                    if params.includeMinions then
                        pickMinions minionBudget filtered
                            |> Random.map
                                (\minions -> params.pinned ++ main ++ minions)

                    else
                        Random.constant (params.pinned ++ main)
                )


{-| Habitat match: `Nothing` is the wildcard (any creature
allowed); a `Just h` requires the creature to list `h` among
its habitats. Creatures with empty `habitats` only match the
wildcard — surfacing them as a Forest encounter would be
misleading.
-}
matchesHabitat : Maybe Habitat -> Creature -> Bool
matchesHabitat habitat c =
    case habitat of
        Nothing ->
            True

        Just h ->
            List.member h c.habitats


{-| OR-of-types creature match against the `race` field
(which stores the D&D type — "Dragon", "Fiend", etc.). Empty
list is the wildcard (matches everything); a non-empty list
matches creatures whose race appears in it. The dropdowns
only offer `allCreatureTypes` so case drift can't happen.
-}
matchesAnyType : List String -> Creature -> Bool
matchesAnyType types c =
    List.isEmpty types || List.member c.race types


{-| Pick the main group. Strategy:

  - Roll a target creature count from the Scale's range.
  - Compute desired XP-per-creature ≈ `budget / target`.
  - Prefer creatures within ±50% of that target XP (the
    "sweet spot" pool); fall back to any affordable creature
    if no sweet-spot match exists.
  - The chosen creature's actual count = `budget / xp`,
    clamped to the Scale's range.

-}
pickMain : Scale -> Int -> List Creature -> Generator (List ( Creature, Int ))
pickMain scale budget pool =
    let
        ( minCount, maxCount ) =
            scaleCountRange scale
    in
    scaleTargetCount scale
        |> Random.andThen
            (\target ->
                let
                    desiredXp =
                        budget // max 1 target

                    affordable =
                        List.filter (\c -> c.xp <= budget) pool

                    sweetSpot =
                        List.filter
                            (\c ->
                                c.xp >= desiredXp // 2 && c.xp <= desiredXp * 2
                            )
                            affordable
                in
                case sweetSpot of
                    first :: rest ->
                        Random.uniform first rest
                            |> Random.map (groupFor budget minCount maxCount)

                    [] ->
                        case affordable of
                            first :: rest ->
                                Random.uniform first rest
                                    |> Random.map (groupFor budget minCount maxCount)

                            [] ->
                                Random.constant []
            )


groupFor : Int -> Int -> Int -> Creature -> List ( Creature, Int )
groupFor budget minCount maxCount creature =
    let
        count =
            (budget // max 1 creature.xp) |> clamp minCount maxCount
    in
    [ ( creature, count ) ]


{-| The Scale's count-range bounds. The actual count is clamped
into this range so a tiny-XP creature can't blow up into 200
copies just because the budget is huge.
-}
scaleCountRange : Scale -> ( Int, Int )
scaleCountRange s =
    case s of
        ScaleOne ->
            ( 1, 1 )

        ScaleFew ->
            ( 2, 4 )

        ScaleMany ->
            ( 4, 12 )


{-| The Scale's "target count midpoint" used to compute desired
XP-per-creature. This is a Generator so different rolls land
on different midpoints within the band — keeps successive
rerolls from feeling like the same fight.
-}
scaleTargetCount : Scale -> Generator Int
scaleTargetCount s =
    case s of
        ScaleOne ->
            Random.constant 1

        ScaleFew ->
            Random.int 2 4

        ScaleMany ->
            Random.int 5 8


{-| Pick a minion group from the low end of the pool. XP ≤ 100
covers CR 0 through CR ½, which is the canonical "minion"
range. We pick one species and stuff 2–6 of them into the
minion budget. Returns `[]` if the pool has no low-XP species
or the minion budget is too small to afford even one — the
roll just lacks minions, it doesn't fail.
-}
pickMinions : Int -> List Creature -> Generator (List ( Creature, Int ))
pickMinions budget pool =
    let
        minionPool =
            pool
                |> List.filter (\c -> c.xp > 0 && c.xp <= 100)
                |> List.filter (\c -> c.xp <= budget)
    in
    case minionPool of
        first :: rest ->
            Random.uniform first rest
                |> Random.map
                    (\minion ->
                        let
                            count =
                                (budget // max 1 minion.xp) |> clamp 2 6
                        in
                        [ ( minion, count ) ]
                    )

        [] ->
            Random.constant []
