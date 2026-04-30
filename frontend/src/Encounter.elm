module Encounter exposing
    ( Cover(..), Creature, Encounter
    , initialEncounter
    , nextTurn, setActive, activeCreature, sortByInitiative
    , moveUp, moveDown
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

@docs nextTurn, setActive, activeCreature, sortByInitiative


# Manual queue reordering

@docs moveUp, moveDown


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
    , initiativeBonus : Int
    , currentHp : Int
    , maxHp : Int
    , tempHp : Int
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
      , initiativeBonus = 5
      , currentHp = 38
      , maxHp = 42
      , tempHp = 0
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
      , initiativeBonus = -1
      , currentHp = 27
      , maxHp = 59
      , tempHp = 0
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
      , initiativeBonus = 2
      , currentHp = 34
      , maxHp = 65
      , tempHp = 0
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
      , initiativeBonus = 2
      , currentHp = 7
      , maxHp = 7
      , tempHp = 0
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
      , initiativeBonus = 2
      , currentHp = 21
      , maxHp = 21
      , tempHp = 0
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
      , initiativeBonus = 1
      , currentHp = 4
      , maxHp = 27
      , tempHp = 0
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
      , initiativeBonus = -1
      , currentHp = 78
      , maxHp = 78
      , tempHp = 0
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
      , initiativeBonus = 3
      , currentHp = 12
      , maxHp = 18
      , tempHp = 0
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


{-| Swap a creature with its predecessor in the queue. No-op when
the named creature is already at the top, or isn't in the queue at
all.

This is purely a queue-position move — initiative isn't touched.
A subsequent `sortByInitiative` will re-order the queue back to
initiative order, which is the documented contract: manual moves
are temporary, and the next sort wipes them.

-}
moveUp : String -> Encounter -> Encounter
moveUp name enc =
    { enc | creatures = swapWithPrev name enc.creatures }


swapWithPrev : String -> List Creature -> List Creature
swapWithPrev name creatures =
    case creatures of
        a :: b :: rest ->
            if b.name == name then
                b :: a :: rest

            else
                a :: swapWithPrev name (b :: rest)

        _ ->
            creatures


{-| Swap a creature with its successor in the queue. No-op when the
named creature is already at the bottom, or isn't in the queue.
Same caveat as [`moveUp`](#moveUp): pure position move, no
initiative change.
-}
moveDown : String -> Encounter -> Encounter
moveDown name enc =
    { enc | creatures = swapWithNext name enc.creatures }


swapWithNext : String -> List Creature -> List Creature
swapWithNext name creatures =
    case creatures of
        a :: b :: rest ->
            if a.name == name then
                b :: a :: rest

            else
                a :: swapWithNext name (b :: rest)

        _ ->
            creatures


{-| Re-order the encounter queue by descending initiative.

5e ties are normally broken by Dexterity score; we use the recorded
`initiativeBonus` as a stand-in (it's effectively the modifier the
roll added). If both are equal we fall back to creature name for a
stable, alphabetic tiebreaker — better than letting `List.sortBy`
pick an arbitrary ordering on a re-render.

`activeName` is preserved across the sort, so a re-sort mid-combat
doesn't reset whose turn it is.

-}
sortByInitiative : Encounter -> Encounter
sortByInitiative enc =
    let
        sortKey c =
            ( negate c.initiative, negate c.initiativeBonus, c.name )
    in
    { enc | creatures = List.sortBy sortKey enc.creatures }


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

**Surprised skipping** (5e surprise rules): when the queue would
make a creature with `surprised = True` active, that creature is
skipped — their `surprised` flag is cleared (so their next turn
happens normally) and the marker advances past them in the same
step. A run of consecutive surprised creatures all get skipped on
one Next Turn click, with each iteration potentially incrementing
`round` if it wraps. A defensive iteration cap of `length creatures`
prevents an all-surprised queue from spinning indefinitely; if the
cap is hit we leave the marker wherever it landed with everyone's
surprised flag now clear.

Edge cases:

  - Empty queue: returns the encounter unchanged so the update loop
    can no-op safely.
  - One creature: every "next turn" wraps and ticks the round, which
    is the correct behavior for solo combat.
  - `activeName` not in the queue (defensive): we treat it as if we
    were on the last creature so the next click jumps to the first.

This function only updates the turn marker (and the surprise side
effect). Other phase-specific effects (begin / end / off / on)
will live in their own functions; the update loop will compose
them around `nextTurn` when those features land.

-}
nextTurn : Encounter -> Encounter
nextTurn enc =
    -- Outer loop with an iteration cap so an all-surprised queue
    -- can't spin forever. Each iteration is one queue advance plus
    -- a possible surprised-clear; the cap is set to the queue
    -- length, which is the most slots we could possibly skip
    -- through before reaching every creature.
    skipSurprised (List.length enc.creatures) enc


skipSurprised : Int -> Encounter -> Encounter
skipSurprised budget enc =
    if budget <= 0 then
        enc

    else
        let
            advanced =
                advanceOne enc
        in
        case findByName advanced.activeName advanced.creatures of
            Just c ->
                if c.surprised then
                    advanced
                        |> mapCreature c.name (\cr -> { cr | surprised = False })
                        |> skipSurprised (budget - 1)

                else
                    advanced

            Nothing ->
                advanced


{-| Advance the marker by exactly one slot, no surprise handling.
The wrap-detection / round-bump logic that used to live in
`nextTurn` itself; pulled out so `skipSurprised` can call it on
each iteration of the skip loop.
-}
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
