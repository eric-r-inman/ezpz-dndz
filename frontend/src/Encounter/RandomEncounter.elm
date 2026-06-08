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
  - Build a slot queue from the Scale + selected types:
    ScaleOne = 1 slot; ScaleFew = 2–3; ScaleMany = 3–4. When
    multiple types are selected the queue cycles through them
    so each chosen type contributes at least one species.
  - Fill each slot in turn, picking a creature whose XP suits
    the slot's share of the budget. Already-picked species are
    excluded so the result always contains distinct creatures.
  - For the **minion** group (if on), pick one low-XP species
    (xp ≤ 100, ≈ CR ½ or less) that wasn't already used and
    stuff 2–6 of them into the minion budget.

That's enough to produce believable encounters with real
variety — multi-type selections actually surface multiple
types, and a Few/Many roll on one type still mixes species —
without the full 2024 DMG composition-template model. No
`Html`, no `Msg` — same discipline as `Encounter.Difficulty`.

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
  - `excludedIds` — creature ids the GM has banned from the
    roll. Filtered out of both the main pick and the minion
    pick. The exclusion only applies to the random fill;
    pinned creatures take precedence and still appear even if
    their id ends up in the list.

-}
type alias GenParams =
    { budget : Int
    , habitat : Maybe Habitat
    , creatureTypes : List String
    , scale : Scale
    , includeMinions : Bool
    , pinned : List ( Creature, Int )
    , excludedIds : List String
    }


{-| What the generator produces:

  - `groups` — every `(creature, count)` to show in the result
    panel, in display order (pinned → main → minions).
    Empty means the filtered pool was empty.
  - `minionIds` — creature ids that came from the minion pick
    so the view can mark those rows visually. The minion rows
    are still part of `groups`; this list just identifies
    which ones they are.

-}
type alias RollResult =
    { groups : List ( Creature, Int )
    , minionIds : List String
    }


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
                |> List.filter (\c -> not (List.member c.id params.excludedIds))

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
        Random.constant
            { groups = params.pinned, minionIds = [] }

    else
        let
            pinnedIds =
                List.map (\( c, _ ) -> c.id) params.pinned
        in
        pickMainGroups params.scale params.creatureTypes mainBudget filtered pinnedIds
            |> Random.andThen
                (\main ->
                    let
                        mainSpent =
                            List.foldl
                                (\( c, n ) acc -> acc + c.xp * n)
                                0
                                main

                        afterMainIds =
                            pinnedIds ++ List.map (\( c, _ ) -> c.id) main
                    in
                    topUp (mainBudget - mainSpent) filtered afterMainIds
                        |> Random.andThen
                            (\extras ->
                                let
                                    filled =
                                        main ++ extras

                                    afterExtrasIds =
                                        afterMainIds
                                            ++ List.map (\( c, _ ) -> c.id) extras
                                in
                                if params.includeMinions then
                                    pickMinions minionBudget filtered afterExtrasIds
                                        |> Random.map
                                            (\minions ->
                                                { groups = params.pinned ++ filled ++ minions
                                                , minionIds =
                                                    List.map (\( c, _ ) -> c.id) minions
                                                }
                                            )

                                else
                                    Random.constant
                                        { groups = params.pinned ++ filled
                                        , minionIds = []
                                        }
                            )
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


{-| Pick the main encounter groups. The encounter is built as a
sequence of "slots" rather than a single greedy fill, so a roll
contains multiple species and reflects every selected type:

  - **ScaleOne** → 1 slot, count 1 (the boss).
  - **ScaleFew** → 2–3 slots. With multiple selected types,
    the slot count equals the type count (capped at 3) so each
    type contributes a species; with one or zero types, the
    slots still produce 2 distinct species for variety.
  - **ScaleMany** → 3–4 slots, same cycling logic.

For multi-type selections the slot queue cycles through the
chosen types in order (`[Dragon, Fiend]` with 3 slots →
`[Dragon, Fiend, Dragon]`), guaranteeing each type appears.
Already-picked species are excluded so a Few/Many roll never
produces two identical groups.

Per-slot count is scaled down by the slot count so the total
creature count still feels right for the Scale knob — a
ScaleMany roll spread across 3 slots fills each slot with a
"few-ish" group, totalling many creatures.

-}
pickMainGroups :
    Scale
    -> List String
    -> Int
    -> List Creature
    -> List String
    -> Generator (List ( Creature, Int ))
pickMainGroups scale creatureTypes totalBudget pool pinnedIds =
    let
        sources =
            if List.isEmpty creatureTypes then
                [ "" ]

            else
                creatureTypes

        slotCount =
            case scale of
                ScaleOne ->
                    1

                ScaleFew ->
                    max 2 (min 3 (List.length sources))

                ScaleMany ->
                    max 3 (min 4 (List.length sources))

        queue =
            cycleTake slotCount sources

        cap =
            perSlotCap scale slotCount
    in
    fillSlots scale cap queue totalBudget pool pinnedIds []


{-| Per-slot count cap derived from the Scale's _total_ target
range divided across the slot count. Without this the
generator could produce far more creatures than the Scale
implies — Few with 2 slots and a per-slot cap of 3 would yield
up to 6, even though "Few" should mean 2–4 total.

  - ScaleOne → always 1.
  - ScaleFew → roughly ⌈4 / slots⌉ per slot, total ≤ ~4.
  - ScaleMany → roughly ⌈18 / slots⌉ per slot, total ≤ ~18.
    The ScaleMany ceiling is intentionally generous so a roll
    of small creatures (Wyrmlings, goblinoids, etc.) can
    actually use the party's XP budget — capping it lower
    leaves high-budget rolls with most of the budget unspent.

A slot can still drop below this cap if its budget can't
afford it; this only sets the ceiling.

-}
perSlotCap : Scale -> Int -> Int
perSlotCap scale slots =
    let
        slotsSafe =
            max 1 slots

        ceilDiv num =
            (num + slotsSafe - 1) // slotsSafe
    in
    case scale of
        ScaleOne ->
            1

        ScaleFew ->
            max 1 (ceilDiv 4)

        ScaleMany ->
            max 4 (ceilDiv 18)


{-| Recursively walk the slot queue, picking one species per
slot from the type-filtered pool. Each pick deducts from the
remaining budget; species already picked (including pinned
ones) are excluded so every slot contributes a different
creature. If a slot has no eligible species, it's skipped and
its share of the budget flows to the next slot.
-}
fillSlots :
    Scale
    -> Int
    -> List String
    -> Int
    -> List Creature
    -> List String
    -> List ( Creature, Int )
    -> Generator (List ( Creature, Int ))
fillSlots scale cap queue budgetLeft pool excludedIds acc =
    case queue of
        [] ->
            Random.constant (List.reverse acc)

        currentType :: rest ->
            let
                slotsLeft =
                    List.length queue

                budgetThisSlot =
                    max 1 (budgetLeft // slotsLeft)

                inType c =
                    currentType == "" || c.race == currentType

                eligible =
                    pool
                        |> List.filter inType
                        |> List.filter (\c -> not (List.member c.id excludedIds))

                affordable =
                    List.filter (\c -> c.xp <= budgetLeft) eligible
            in
            case affordable of
                [] ->
                    fillSlots scale cap rest budgetLeft pool excludedIds acc

                first :: more ->
                    pickSlotCreature scale cap budgetThisSlot ( first, more )
                        |> Random.andThen
                            (\( creature, count ) ->
                                fillSlots scale
                                    cap
                                    rest
                                    (budgetLeft - count * creature.xp)
                                    pool
                                    (creature.id :: excludedIds)
                                    (( creature, count ) :: acc)
                            )


{-| Pick one creature for a slot. Prefers creatures whose XP
sits near `slotBudget / target` so the slot's count lands in
the Scale's per-slot range; falls back to any affordable
creature when no sweet-spot match exists. The caller hands in
a guaranteed-non-empty `(head, tail)` so the result is total.
-}
pickSlotCreature :
    Scale
    -> Int
    -> Int
    -> ( Creature, List Creature )
    -> Generator ( Creature, Int )
pickSlotCreature scale cap slotBudget ( first, more ) =
    let
        affordable =
            first :: more

        -- Budget-aware floor: at `cap` copies, a creature at
        -- the floor would fill a meaningful fraction of the
        -- slot.  Scale-dependent so the floor stays loose for
        -- ScaleMany (allowing small swarms at any level) and
        -- tighter for ScaleOne (boss intent — pick a creature
        -- whose XP is at least half the slot budget).
        --
        -- Without this, the previous "no floor" pick would
        -- grab a 25-XP Kobold for a 7,000-XP slot, capping
        -- spend at `cap * 25` ≈ 100 XP and wasting 99% of the
        -- budget.  When the floor screens everything out the
        -- fallback below picks from the unfiltered affordable
        -- list — kobolds still appear at low budgets because
        -- the floor itself is low there.
        floor_ =
            case scale of
                ScaleOne ->
                    slotBudget // 2

                ScaleFew ->
                    slotBudget // (max 1 cap * 3)

                ScaleMany ->
                    slotBudget // (max 1 cap * 4)

        sweetSpot =
            List.filter (\c -> c.xp >= floor_) affordable

        pickGen =
            case sweetSpot of
                a :: rest ->
                    Random.uniform a rest

                [] ->
                    Random.uniform first more
    in
    pickGen
        |> Random.map (\c -> ( c, slotCountFor cap slotBudget c ))


{-| Per-slot count: budget // xp, clamped to the pre-computed
`cap` (from `perSlotCap`). The cap is set so that the sum of
caps across all slots stays within the Scale's intended total
count range.
-}
slotCountFor : Int -> Int -> Creature -> Int
slotCountFor cap slotBudget creature =
    let
        affordable =
            slotBudget // max 1 creature.xp
    in
    max 1 (min cap affordable)


{-| Repeat `items` in order until `n` elements have been taken.
`cycleTake 5 ["a", "b"] = ["a", "b", "a", "b", "a"]`.
-}
cycleTake : Int -> List a -> List a
cycleTake n items =
    case items of
        [] ->
            []

        _ ->
            let
                len =
                    List.length items

                fullCycles =
                    n // len

                remainder =
                    modBy len n
            in
            (List.repeat fullCycles items |> List.concat)
                ++ List.take remainder items


{-| Top-up pass. The main slot fill is sized for variety
(per-slot budget capped by `cap`) which tends to leave a chunk
of budget unspent — especially with ScaleFew at high party
levels where one Wyvern fills only a fraction of the slot.
This pass picks ONE extra species sized to land the total
encounter close to (or slightly over) the original budget.

  - Skip entirely if `remaining` is small (< 15% of the
    pre-fill budget) — close enough; another group would
    push noticeably over.
  - Otherwise enumerate the eligible pool (habitat + type
    filters, no excluded species) and keep only candidates
    whose `xp × count` lands in `[0.7 × remaining,
    1.2 × remaining]` — i.e. fills most of the gap without
    busting it by more than 20%.
  - Pick one such candidate uniformly. Count is whatever made
    it qualify (single creature when one fits cleanly;
    2–6 when a smaller species needs a count).
  - Empty result is fine — the main fill stands on its own.

It's easier for the GM to drop a creature from the roster
than to hunt the compendium for one to add, so this favours
"slightly over" over "noticeably under" as the user requested.

-}
topUp : Int -> List Creature -> List String -> Generator (List ( Creature, Int ))
topUp remaining pool excludedIds =
    let
        eligible =
            pool
                |> List.filter (\c -> c.xp > 0)
                |> List.filter (\c -> not (List.member c.id excludedIds))

        overTolerance =
            remaining * 12 // 10

        underTolerance =
            remaining * 7 // 10

        bestCount c =
            let
                affordable =
                    overTolerance // max 1 c.xp
            in
            clamp 1 6 affordable

        score c =
            ( c, bestCount c )

        candidate ( c, n ) =
            let
                spent =
                    c.xp * n
            in
            spent >= underTolerance && spent <= overTolerance

        candidates =
            eligible
                |> List.map score
                |> List.filter candidate
    in
    -- Tiny remaining → don't bother; the main fill is close
    -- enough to budget that another group would over-shoot
    -- the encounter's intent rather than help it.
    if remaining <= 0 then
        Random.constant []

    else
        case candidates of
            first :: rest ->
                Random.uniform first rest
                    |> Random.map (\pick -> [ pick ])

            [] ->
                Random.constant []


{-| Pick a minion group from the low end of the pool. XP ≤ 100
covers CR 0 through CR ½, which is the canonical "minion"
range. We pick one species and stuff 2–6 of them into the
minion budget. Returns `[]` if the pool has no low-XP species
or the minion budget is too small to afford even one — the
roll just lacks minions, it doesn't fail.

Excludes species already chosen by the main fill (and pinned)
so the minion group always introduces a new creature instead
of doubling up.

-}
pickMinions : Int -> List Creature -> List String -> Generator (List ( Creature, Int ))
pickMinions budget pool excludedIds =
    let
        minionPool =
            pool
                |> List.filter (\c -> c.xp > 0 && c.xp <= 100)
                |> List.filter (\c -> c.xp <= budget)
                |> List.filter (\c -> not (List.member c.id excludedIds))
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
