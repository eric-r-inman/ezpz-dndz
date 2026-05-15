module Compendium.Group exposing
    ( Group, GroupEntry
    , InitiativeMode(..), MinionType(..)
    , initiativeModeKey, initiativeModeFromKey, initiativeModeLabel
    , minionTypeKey, minionTypeFromKey, minionTypeLabel
    , maxHpFor, totalCreatureCount
    , initiativeModeAllValues, minionTypeAllValues
    , GroupSpawn
    )

{-| Pure domain layer for compendium **groups** (a.k.a. Hordes).

A Group bundles one or more compendium creatures into a unit that
adds to the encounter as a whole. Groups solve three problems
that the single-creature add flow can't:

  - Spawning multiple instances of the same creature in one click
    (e.g. five Skeletons).
  - Coordinating initiative across the bundle (shared roll, or a
    GM-typed manual value).
  - Marking creatures as "minions" so their max HP is overridden
    at materialise time (1 HP cannon-fodder or half-HP swarm).

Groups appear in the compendium list as collapsible rows and
must be added atomically — the GM can't pick a single skeleton
out of a "Goblin Patrol" group, because individual selection
would break the multi-instance / shared-initiative semantics.

No `Html`, `Browser`, or `Url` imports — this is the rules-engine
layer matching the discipline of [`Encounter`](Encounter),
[`Compendium`](Compendium), and [`Dice`](Dice). Wire format
helpers live in [`Compendium.GroupWire`](Compendium-GroupWire).

@docs Group, GroupEntry
@docs InitiativeMode, MinionType
@docs initiativeModeKey, initiativeModeFromKey, initiativeModeLabel
@docs minionTypeKey, minionTypeFromKey, minionTypeLabel
@docs maxHpFor, totalCreatureCount
@docs initiativeModeAllValues, minionTypeAllValues

-}

-- ── TYPES ────────────────────────────────────────────────────────────────────


type alias Group =
    { id : String
    , name : String
    , initiativeMode : InitiativeMode
    , entries : List GroupEntry
    , createdAt : Int
    , updatedAt : Int
    }


{-| One row in a Group: a reference to a compendium creature, how
many instances to spawn, and what kind of minion (if any) the
spawned instances should be.

Minion type rewrites max HP at materialise time so the bundled
creature behaves like a glass cannon without polluting the
canonical compendium entry.

-}
type alias GroupEntry =
    { creatureId : String
    , count : Int
    , minionType : MinionType
    }


{-| How initiative is rolled when the group is added to the
encounter.

  - `InitiativeEachRolls` — every spawned instance rolls its own
    initiative (same as the single-creature add path).
  - `InitiativeSharedRolled` — one initiative roll, shared by all
    instances of every entry. Useful for keeping a swarm
    sequenced together.
  - `InitiativeSharedManual n` — the GM types a value; every
    instance gets that exact initiative number. Useful when the
    GM wants the swarm to act in a specific slot.

-}
type InitiativeMode
    = InitiativeEachRolls
    | InitiativeSharedRolled
    | InitiativeSharedManual Int


{-| Fully-resolved instance spec produced when a group is added
to the encounter. Carries everything the materialiser needs to
spawn an `Encounter.Creature` without re-consulting the original
group / entry / initiative-mode shape.

`maxHpOverride` is `Just n` when the entry has a minion type;
the materialiser substitutes `n` for the source creature's
`maxHp`. `Nothing` means use the source's `maxHp` verbatim.

-}
type alias GroupSpawn =
    { creatureId : String
    , displayName : String
    , initiative : Int
    , maxHpOverride : Maybe Int
    }


{-| Optional max-HP override applied to every instance of an
entry at encounter-materialise time.

  - `MinionNone` — use the compendium creature's `maxHp` verbatim.
  - `MinionHalfHp` — divide `maxHp` by 2 (rounded down, minimum 1).
  - `MinionOneHp` — every instance has 1 max HP.

-}
type MinionType
    = MinionNone
    | MinionHalfHp
    | MinionOneHp



-- ── HELPERS ──────────────────────────────────────────────────────────────────


{-| Compute the effective max HP for an entry given the source
creature's max HP. Used by the encounter materialiser; also
useful for the modal preview ("Max HP: 13 → 1").
-}
maxHpFor : MinionType -> Int -> Int
maxHpFor minionType sourceMaxHp =
    case minionType of
        MinionNone ->
            sourceMaxHp

        MinionHalfHp ->
            -- Floor division; ensure at least 1 so a degenerate
            -- 1-HP source doesn't yield 0 (which would mark every
            -- instance as dead on spawn).
            max 1 (sourceMaxHp // 2)

        MinionOneHp ->
            1


totalCreatureCount : Group -> Int
totalCreatureCount group =
    List.sum (List.map .count group.entries)



-- ── ENUM WIRE / FORM HELPERS ─────────────────────────────────────────────────


initiativeModeKey : InitiativeMode -> String
initiativeModeKey mode =
    case mode of
        InitiativeEachRolls ->
            "each_rolls"

        InitiativeSharedRolled ->
            "shared_rolled"

        InitiativeSharedManual _ ->
            "shared_manual"


{-| Parse the radio-button / wire key back into an `InitiativeMode`.
`shared_manual` returns with value `10` so the form has a sane
default the GM can edit.
-}
initiativeModeFromKey : String -> Maybe InitiativeMode
initiativeModeFromKey raw =
    case raw of
        "each_rolls" ->
            Just InitiativeEachRolls

        "shared_rolled" ->
            Just InitiativeSharedRolled

        "shared_manual" ->
            Just (InitiativeSharedManual 10)

        _ ->
            Nothing


initiativeModeLabel : InitiativeMode -> String
initiativeModeLabel mode =
    case mode of
        InitiativeEachRolls ->
            "Each rolls"

        InitiativeSharedRolled ->
            "Shared rolled"

        InitiativeSharedManual _ ->
            "Shared manual"


initiativeModeAllValues : List InitiativeMode
initiativeModeAllValues =
    [ InitiativeEachRolls
    , InitiativeSharedRolled
    , InitiativeSharedManual 10
    ]


minionTypeKey : MinionType -> String
minionTypeKey minionType =
    case minionType of
        MinionNone ->
            "none"

        MinionHalfHp ->
            "half"

        MinionOneHp ->
            "one"


minionTypeFromKey : String -> Maybe MinionType
minionTypeFromKey raw =
    case raw of
        "none" ->
            Just MinionNone

        "half" ->
            Just MinionHalfHp

        "one" ->
            Just MinionOneHp

        _ ->
            Nothing


minionTypeLabel : MinionType -> String
minionTypeLabel minionType =
    case minionType of
        MinionNone ->
            "Normal"

        MinionHalfHp ->
            "Minion (½ HP)"

        MinionOneHp ->
            "Minion (1 HP)"


minionTypeAllValues : List MinionType
minionTypeAllValues =
    [ MinionNone, MinionHalfHp, MinionOneHp ]
