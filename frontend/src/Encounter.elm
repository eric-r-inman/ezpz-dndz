module Encounter exposing
    ( Cover(..), Creature, Encounter
    , initialEncounter
    , nextTurn, setActive, activeCreature
    , mapCreature, nextCover, toggleDeathSave
    )

{-| Domain layer for the encounter manager.

This module owns all D&D-flavored game state and the pure functions
that operate on it. It deliberately imports nothing from `Html`,
`Browser`, or any other rendering primitive — the goal is a rules
engine you can reason about without a DOM, and that downstream UI
layouts can swap freely (e.g. a future "simple view" with fewer
controls). If a function in `update` finds itself doing rules work
(walking the queue, picking the next active creature, computing
damage), it belongs here.


# Types

@docs Cover, Creature, Encounter


# Initial state

@docs initialEncounter


# Turn lifecycle

The lifecycle has four phases that downstream features may hook:

  - **beginning of turn** — a creature has just become the active
    creature. Per-turn ability charges reset; conditions tagged
    "start of turn" tick or expire.
  - **on turn** — the creature is currently active. Player-driven
    actions (attacks, casts, moves) happen here.
  - **end of turn** — fired against the OUTGOING creature before
    its successor takes over. Saves against ongoing conditions,
    "end of turn" durations expire.
  - **off turn** — applies to every creature that is _not_ active.
    Reaction triggers (opportunity attacks), passive observation.

`nextTurn` advances the active marker by one slot. It does NOT yet
run any phase hooks; those are pure functions to be added per
feature, with the `update` loop composing them around `nextTurn`.

@docs nextTurn, setActive, activeCreature


# State helpers

@docs mapCreature, nextCover, toggleDeathSave

-}

-- TYPES


{-| Cover state: cycles
NoCover → HalfCover → ThreeQuartersCover → FullCover → NoCover via
[`nextCover`](#nextCover).
-}
type Cover
    = NoCover
    | HalfCover
    | ThreeQuartersCover
    | FullCover


{-| Per-creature state. Identity is by `.name` for now; when we add
real save/load with name collisions we'll switch to a stable id
(probably a UUID seeded into a new field).

The boolean toggle fields each correspond to a button in the card
center column rows 1–3:

  - `surprised` — row 1 face toggle.
  - `cover`, `concentrating`, `hiding`, `flying`, `flyHeight` — row 2.
  - `bloodied`, `inDeathSaves`, `deathSaves` — row 2 HP indicators.
  - `holding` — row 3 hold-action toggle.

`selected` is the row 1 multi-select checkbox; it's independent of
the active creature (which marks who is currently taking their turn).

-}
type alias Creature =
    { name : String
    , kind : String
    , initiative : Int
    , currentHp : Int
    , maxHp : Int
    , armorClass : Int
    , speed : Int
    , conditions : List String
    , selected : Bool
    , surprised : Bool
    , cover : Cover
    , concentrating : Bool
    , hiding : Bool
    , flying : Bool
    , flyHeight : Int
    , bloodied : Bool
    , inDeathSaves : Bool
    , deathSaves : ( Bool, Bool, Bool )
    , holding : Bool
    }


{-| Top-level encounter state. The single source of truth for what
combat is going on right now.

`creatures` is in initiative order (highest first). `activeName`
identifies whose turn it currently is. `round` is 1-indexed and
ticks up each time the turn marker wraps from the last creature
back to the first.

-}
type alias Encounter =
    { creatures : List Creature
    , activeName : String
    , round : Int
    }



-- INITIAL STATE


{-| The encounter the page boots into. Will eventually be replaced
by user-loaded encounters from the monster database / saved files.
For now it's a fixed cast that exercises the various card states
(bloodied, hiding, flying with height, surprised, concentrating,
death saves, holding).
-}
initialEncounter : Encounter
initialEncounter =
    { creatures = seedCreatures
    , activeName = "Brakka, Ogre Brute"
    , round = 1
    }


{-| Hard-coded mock cast. Order is descending initiative.
-}
seedCreatures : List Creature
seedCreatures =
    [ { name = "Lyra Vale (PC)"
      , kind = "Half-elf rogue, lvl 5"
      , initiative = 22
      , currentHp = 38
      , maxHp = 42
      , armorClass = 16
      , speed = 30
      , conditions = [ "Hidden" ]
      , selected = False
      , surprised = False
      , cover = HalfCover
      , concentrating = False
      , hiding = True
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , inDeathSaves = True
      , deathSaves = ( True, False, False )
      , holding = False
      }
    , { name = "Brakka, Ogre Brute"
      , kind = "Large giant, chaotic evil"
      , initiative = 18
      , currentHp = 27
      , maxHp = 59
      , armorClass = 11
      , speed = 40
      , conditions = [ "Bloodied", "Frightened" ]
      , selected = True
      , surprised = True
      , cover = NoCover
      , concentrating = False
      , hiding = False
      , flying = False
      , flyHeight = 0
      , bloodied = True
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
      }
    , { name = "Captain Vex"
      , kind = "Medium humanoid (human), bandit captain"
      , initiative = 17
      , currentHp = 34
      , maxHp = 65
      , armorClass = 15
      , speed = 30
      , conditions = []
      , selected = False
      , surprised = False
      , cover = NoCover
      , concentrating = False
      , hiding = False
      , flying = False
      , flyHeight = 0
      , bloodied = True
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = True
      }
    , { name = "Goblin Skirmisher"
      , kind = "Small humanoid, neutral evil"
      , initiative = 15
      , currentHp = 7
      , maxHp = 7
      , armorClass = 15
      , speed = 30
      , conditions = []
      , selected = False
      , surprised = False
      , cover = ThreeQuartersCover
      , concentrating = False
      , hiding = False
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
      }
    , { name = "Goblin Boss"
      , kind = "Small humanoid, neutral evil"
      , initiative = 12
      , currentHp = 21
      , maxHp = 21
      , armorClass = 17
      , speed = 30
      , conditions = []
      , selected = False
      , surprised = False
      , cover = FullCover
      , concentrating = False
      , hiding = False
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
      }
    , { name = "Thornwhip Shaman"
      , kind = "Small humanoid, druid"
      , initiative = 9
      , currentHp = 4
      , maxHp = 27
      , armorClass = 13
      , speed = 30
      , conditions = [ "Concentrating" ]
      , selected = True
      , surprised = False
      , cover = NoCover
      , concentrating = True
      , hiding = False
      , flying = True
      , flyHeight = 30
      , bloodied = False
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
      }
    , { name = "Stone Sentinel"
      , kind = "Large construct, unaligned"
      , initiative = 8
      , currentHp = 78
      , maxHp = 78
      , armorClass = 18
      , speed = 25
      , conditions = []
      , selected = False
      , surprised = False
      , cover = HalfCover
      , concentrating = False
      , hiding = False
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
      }
    , { name = "Shadow Wisp"
      , kind = "Tiny undead, neutral evil"
      , initiative = 6
      , currentHp = 12
      , maxHp = 18
      , armorClass = 12
      , speed = 0
      , conditions = []
      , selected = False
      , surprised = False
      , cover = NoCover
      , concentrating = False
      , hiding = True
      , flying = True
      , flyHeight = 15
      , bloodied = False
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
      }
    ]



-- TURN LIFECYCLE


{-| Look up the currently-active creature, or `Nothing` if `activeName`
isn't present in the queue. View code uses this to render the title-bar
summary.
-}
activeCreature : Encounter -> Maybe Creature
activeCreature enc =
    findByName enc.activeName enc.creatures


{-| Move the active marker to a specific creature WITHOUT counting it
as turn progression.

Use this when the GM wants to scrub the turn marker manually (the
right-arrow button on each creature card). It deliberately does NOT:

  - increment `round`,
  - run the would-be "end of turn" hooks for the outgoing creature,
  - run the would-be "beginning of turn" hooks for the incoming one.

The contrast with [`nextTurn`](#nextTurn) is exactly that: `nextTurn`
is "advance the clock"; `setActive` is "skip to whoever I picked".
Future per-phase hook composers should branch off `nextTurn` only.

If `name` isn't in the queue, the encounter is returned unchanged so
the call site can no-op safely.

-}
setActive : String -> Encounter -> Encounter
setActive name enc =
    case findByName name enc.creatures of
        Just _ ->
            { enc | activeName = name }

        Nothing ->
            enc


{-| Advance the turn marker by one slot.

In initiative order: the current creature's successor becomes active.
When the marker would step off the end of the queue it wraps back to
the first creature, which marks the start of a new combat round, so
`round` increments. Callers don't need to think about wrap detection;
that's encapsulated here.

Edge cases:

  - Empty queue: returns the encounter unchanged so the update loop
    can no-op safely (nothing to advance).
  - One creature: every "next turn" wraps and ticks the round, which
    is the correct behavior for solo combat.
  - `activeName` not in the queue (defensive): we treat it as if we
    were on the last creature so the next click jumps to the first.

This function only updates the turn marker. Phase-specific effects
(begin / end / off / on) live in their own functions; the update
loop will compose them when those features land.

-}
nextTurn : Encounter -> Encounter
nextTurn enc =
    case enc.creatures of
        [] ->
            enc

        first :: _ ->
            let
                -- Find the next name. `findNext` walks the list once
                -- and stops as soon as it sees the current active
                -- creature, returning whatever comes immediately
                -- after. If we walk off the end we wrap to `first`.
                newActive =
                    findNext enc.activeName enc.creatures
                        |> Maybe.withDefault first.name

                -- A wrap happened iff the OLD active was the last
                -- creature in the queue (or wasn't found at all,
                -- which we collapse to "treat as last" for resilience).
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


{-| Walk the list looking for `currentName`; return the name of the
creature immediately after it, or `Nothing` if `currentName` is the
last (or absent). Single pass, early exit.
-}
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


{-| `True` iff `name` matches the last creature in the queue. Treats
"name not in queue at all" as `True` so wrap-detection in `nextTurn`
defensively triggers a round increment in that (shouldn't-happen) case.
-}
isLastInQueue : String -> List Creature -> Bool
isLastInQueue name creatures =
    case List.reverse creatures of
        [] ->
            False

        last :: _ ->
            -- If the active name isn't in the list, `findByName` returns
            -- Nothing and we say "yes, it's effectively last" so a wrap
            -- happens. That keeps the round counter advancing rather
            -- than getting stuck if state ever drifts.
            last.name == name || findByName name creatures == Nothing



-- STATE HELPERS


{-| Apply `fn` to whichever creature in the encounter has `name`; pass
through all other creatures (and the rest of the encounter) unchanged.
Used by every per-creature toggle (surprised, cover, concentrating,
hiding, flying, fly-height, death-save slots, holding action).

O(n) over the queue. For typical encounter sizes (5–15 combatants)
this is fine and avoids the complexity of indexing or a Dict keyed by
name.

-}
mapCreature : String -> (Creature -> Creature) -> Encounter -> Encounter
mapCreature name fn enc =
    let
        apply c =
            if c.name == name then
                fn c

            else
                c
    in
    { enc | creatures = List.map apply enc.creatures }


{-| Look a creature up by name. Returns `Nothing` if absent.
-}
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


{-| Cycle cover state. Used by the row 2 cover-cycle button.
-}
nextCover : Cover -> Cover
nextCover c =
    case c of
        NoCover ->
            HalfCover

        HalfCover ->
            ThreeQuartersCover

        ThreeQuartersCover ->
            FullCover

        FullCover ->
            NoCover


{-| Flip one of the three death-save slots in the
`(Bool, Bool, Bool)` tuple. Index must be 0, 1, or 2; out-of-range
falls through to slot 2 defensively (better than crashing on bad
input, and the call site only ever passes 0/1/2 anyway).
-}
toggleDeathSave : Int -> ( Bool, Bool, Bool ) -> ( Bool, Bool, Bool )
toggleDeathSave idx ( a, b, c ) =
    case idx of
        0 ->
            ( not a, b, c )

        1 ->
            ( a, not b, c )

        _ ->
            ( a, b, not c )
