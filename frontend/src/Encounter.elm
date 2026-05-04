module Encounter exposing
    ( Cover(..), Creature, DeathSaves, Encounter
    , Condition, ConditionDraft, Duration(..), TurnPhase(..), TurnTarget(..), SaveToEnd
    , AutoRollMode(..)
    , SaveNotice
    , Timer
    , standardConditions
    , empty
    , nextTurn, setActive, activeCreature, sortByInitiative
    , moveUp, moveDown
    , mapCreature, nextCover
    , removeCreature, duplicateCreature
    , appendCreatures, uniqueInstanceName
    , emptyDeathSaves, addDeathSaveSuccesses, addDeathSaveFailures
    , isDeathSaveStable, isDeathSaveDead
    , addCondition, updateCondition, removeCondition, findCondition
    , describeDuration
    , addSaveNotice, removeSaveNotice
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

@docs Cover, Creature, DeathSaves, Encounter
@docs Condition, ConditionDraft, Duration, TurnPhase, TurnTarget, SaveToEnd
@docs AutoRollMode
@docs SaveNotice
@docs Timer
@docs standardConditions


# Initial state

@docs empty


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

@docs mapCreature, nextCover


# Roster mutation

@docs removeCreature, duplicateCreature
@docs appendCreatures, uniqueInstanceName


# Death saves

@docs emptyDeathSaves, addDeathSaveSuccesses, addDeathSaveFailures
@docs isDeathSaveStable, isDeathSaveDead


# Conditions / effects

@docs addCondition, updateCondition, removeCondition, findCondition
@docs describeDuration


# Save notices

@docs addSaveNotice, removeSaveNotice

-}

-- IMPORTS

import Encounter.DeathSaves
import Encounter.SaveNotice
import Set exposing (Set)



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


{-| 5e death-save tracker. Type re-exported from
[`Encounter.DeathSaves`](Encounter-DeathSaves#DeathSaves); see
that module for the full discussion and the per-tracker helpers.
-}
type alias DeathSaves =
    Encounter.DeathSaves.DeathSaves


{-| One condition or effect riding on a creature. The data is shaped
to cover both the standard 5e conditions ("Poisoned", "Frightened",
etc.) and freeform GM-authored effects ("Bardic inspiration", "On
fire from torch").

  - `id` is a per-encounter unique integer assigned at insert. It's
    what edit / delete operations use as the lookup key, since
    `name` isn't unique (you might have two stacks of Exhaustion or
    two custom effects with the same label).
  - `name` is the display label — either one of
    [`standardConditions`](#standardConditions) or the GM's free
    text. The view doesn't care which.
  - `note` is an optional 10-char hint shown next to the chip
    ("from Lyra", "DC 13"); UI enforces the length cap.
  - `duration` is what makes the condition end (manual removal,
    a queue-relative turn phase, or a turn countdown). See
    [`Duration`](#Duration).
  - `saveToEnd` is the optional saving-throw conditional that
    can clear the condition on success. See [`SaveToEnd`](#SaveToEnd).

-}
type alias Condition =
    { id : Int
    , name : String
    , note : String
    , duration : Duration
    , saveToEnd : Maybe SaveToEnd
    }


{-| Same shape as [`Condition`](#Condition) minus the `id` field —
used by [`addCondition`](#addCondition) so callers don't have to
allocate ids themselves. The encounter assigns ids monotonically.
-}
type alias ConditionDraft =
    { name : String
    , note : String
    , duration : Duration
    , saveToEnd : Maybe SaveToEnd
    }


{-| What ends a condition.

  - `DurationManual` — sticks until the GM explicitly removes it.
    This is the "I'll remember when to take this off" path.
  - `DurationUntilTurn phase target creatureName` — removed at the
    begin/end of `creatureName`'s turn, with `target` selecting
    `OnCurrentTurn` (first matching hook fire) vs `OnNextTurn`
    (skip the first match, expire on the second). Maps to 5e
    spell durations like "until the end of your current turn" vs
    "until the end of your next turn".
  - `DurationCountdown phase remaining skipNextTick` — runs for
    `remaining` of the bearer's own turns, ticking at begin/end.
    `skipNextTick` is set when the countdown was created with
    `phase = AtEnd` during the bearer's currently-active turn:
    the bearer's NEXT end-of-turn isn't really a full turn
    elapsed, so we skip that one tick. See the discussion in
    [`nextTurn`](#nextTurn).

-}
type Duration
    = DurationManual
    | DurationUntilTurn TurnPhase TurnTarget String
    | DurationCountdown TurnPhase Int Bool


{-| Which slice of a creature's turn a hook fires on.
-}
type TurnPhase
    = AtBegin
    | AtEnd


{-| Which iteration of the reference creature's turn ends a
DurationUntilTurn condition.

  - `OnCurrentTurn` — expire on the first matching hook fire.
  - `OnNextTurn` — skip the first match (mutating to
    `OnCurrentTurn` in place), expire on the second.

`OnCurrentTurn` paired with `AtBegin` and a reference creature
who is currently active is logically nonsense — the begin of
their current turn already fired when they became active. The
view layer grays out that combination so the GM can't pick it.

-}
type TurnTarget
    = OnCurrentTurn
    | OnNextTurn


{-| Saving-throw conditional for ending a condition.

  - `ability` is a short label like "WIS", "CON" — used for
    display; we don't validate it against a fixed enum so house
    rules can pick any abbreviation.
  - `dc` is the difficulty class.
  - `bonus` is the save bonus to add when rolling.
  - `autoRoll` selects the timing — see [`AutoRollMode`](#AutoRollMode).

-}
type alias SaveToEnd =
    { ability : String
    , dc : Int
    , bonus : Int
    , autoRoll : AutoRollMode
    }


{-| When the save-to-end roll fires.

  - `AutoRollManual` — never fires automatically; the GM clicks
    the 🎲 button on the chip when they want to roll. The chip
    just records the DC / bonus as a reminder.
  - `AutoRollAtBegin` — fires automatically at the start of the
    bearer's turn. Common for "save at start of your turn" 5e
    effects like Hold Person.
  - `AutoRollAtEnd` — fires automatically at the end of the
    bearer's turn. Common for "save at end of your turn" effects
    like the standard Frightened / Charmed reroll path.

In all three cases a successful save (roll.total >= dc) removes
the condition from the bearer.

-}
type AutoRollMode
    = AutoRollManual
    | AutoRollAtBegin
    | AutoRollAtEnd


{-| Save-notice type re-exported from
[`Encounter.SaveNotice`](Encounter-SaveNotice). See that module
for the per-notice helpers. The encounter-level wrappers
(`addSaveNotice`, `removeSaveNotice`) live here because they need
encounter-wide unique-id allocation.
-}
type alias SaveNotice =
    Encounter.SaveNotice.SaveNotice


{-| Card row 3 alarm-clock timer. Ticks down once per matching
turn-phase hook fire on the bearer; rings when it hits 0.

  - `remaining` — current count. Starts wherever the GM set it
    via the timer-setup modal; decrements on each matching tick;
    capped at 0.
  - `phase` — `AtBegin` ticks at the bearer's begin-of-turn,
    `AtEnd` ticks at the bearer's end-of-turn.
  - `ringing` — set the moment `remaining` hits 0. While
    `ringing` is True, no further ticks happen and the card
    shows a flashing "0" with an × button until the GM
    dismisses it. The view layer also mounts an `<audio>`
    element with the ping sound when any timer is ringing.

-}
type alias Timer =
    { remaining : Int
    , phase : TurnPhase
    , ringing : Bool
    }


{-| The 15 standard 5e conditions, in alphabetical order. Used to
populate the radio-button section of the condition modal.

Exhaustion is included as a single entry rather than the six
levels, since the UI's `note` slot is a fine place for "Lvl 2"
shorthand and the rules treat them as a stack on one condition.

-}
standardConditions : List String
standardConditions =
    [ "Blinded"
    , "Charmed"
    , "Deafened"
    , "Exhaustion"
    , "Frightened"
    , "Grappled"
    , "Incapacitated"
    , "Invisible"
    , "Paralyzed"
    , "Petrified"
    , "Poisoned"
    , "Prone"
    , "Restrained"
    , "Stunned"
    , "Unconscious"
    ]


{-| Per-creature state. Identity is by `.name` for now; when we add
real save/load with name collisions we'll switch to a stable id
(probably a UUID seeded into a new field).

The boolean toggle fields each correspond to a button in the card
center column rows 1–3:

  - `surprised` — row 1 face toggle.
  - `cover`, `concentrating`, `hiding`, `flying`, `flyHeight` — row 2.
  - `bloodied`, `deathSaves` — row 2 HP indicators. The death-save
    tracker (see [`DeathSaves`](#DeathSaves)) is rendered exactly
    when `currentHp == 0`; there's no separate visibility flag.
    Healing back above 0 resets the counts via the HP-change
    engine.
  - `holding` — row 3 hold-action toggle.

`note` is a short free-text label edited via the row 1 pencil
button; it surfaces inline next to the creature name when set
(white italics) so the GM can pin a one-liner like "boss" or
"summoned" without spending a whole condition slot.

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
    , conditions : List Condition
    , saveNotices : List SaveNotice
    , selected : Bool
    , surprised : Bool
    , cover : Cover
    , concentrating : Bool
    , hiding : Bool
    , flying : Bool
    , flyHeight : Int
    , bloodied : Bool
    , deathSaves : DeathSaves
    , holding : Bool
    , note : String
    , memo : String
    , timer : Maybe Timer
    , creatureId : Maybe String
    , hasLegendaryActions : Bool
    , legendaryActionsUsed : Set Int
    , hasLegendaryResistance : Bool
    , legendaryResistanceUsed : Set Int
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


{-| The empty encounter the running app boots into. The previous
"`initialEncounter` is a fixed cast" pattern lives on as a TEST
fixture (see `Encounter.Seed.initialEncounter`) — but the running
app starts empty and either loads a persisted encounter from the
server or waits for the user to add creatures from the compendium.
-}
empty : Encounter
empty =
    { creatures = []
    , activeName = ""
    , round = 1
    }



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

Dead creatures (3 failed death saves, see [`isDeathSaveDead`](#isDeathSaveDead))
are also skipped — but unlike surprised, the dead state isn't
cleared. They stay dead, the marker keeps walking past them on
every subsequent Next Turn. The same iteration cap protects the
edge case of an all-dead queue (e.g. a TPK).

Edge cases:

  - Empty queue: returns the encounter unchanged so the update loop
    can no-op safely.
  - One creature: every "next turn" wraps and ticks the round, which
    is the correct behavior for solo combat.
  - `activeName` not in the queue (defensive): we treat it as if we
    were on the last creature so the next click jumps to the first.

In addition to the queue walk, this function fires two condition
hooks once per Next Turn click:

  - End-of-turn for the OUTGOING active creature: tick down their
    `DurationCountdown AtEnd` conditions, expire any
    `DurationUntilTurn AtEnd <name>` across the whole encounter
    where `<name>` matches.
  - Begin-of-turn for the INCOMING active creature (after skips):
    symmetric, but for `AtBegin` durations.

The skip loop runs between the two hooks so a multi-skip click
still only fires hooks for the outgoing-once and the final
incoming-once. Surprised / dead creatures' begin-of-turn hooks
don't fire — their turn doesn't actually happen, so neither
should any of their start-of-turn ticks.

-}
nextTurn : Encounter -> Encounter
nextTurn enc =
    -- Outer loop with an iteration cap so an all-skip queue (every
    -- creature surprised, or every creature dead, or some mix)
    -- can't spin forever. The hooks bracket the skip walk: end-of-
    -- turn for whoever was active before the click, then advance
    -- and skip to the next playable creature, then begin-of-turn
    -- for them.
    enc
        |> applyEndOfTurn enc.activeName
        |> skipUnplayable (List.length enc.creatures)
        |> applyBeginOfTurnHook


skipUnplayable : Int -> Encounter -> Encounter
skipUnplayable budget enc =
    if budget <= 0 then
        enc

    else
        let
            advanced =
                advanceOne enc
        in
        case findByName advanced.activeName advanced.creatures of
            Just c ->
                if isDeathSaveDead c.deathSaves then
                    -- Dead → skip permanently. No state change; the
                    -- marker keeps walking past on every future
                    -- Next Turn click.
                    skipUnplayable (budget - 1) advanced

                else if c.surprised then
                    -- Surprised → skip once and clear the flag so
                    -- the next round's pass actually runs their
                    -- turn.
                    advanced
                        |> mapCreature c.name (\cr -> { cr | surprised = False })
                        |> skipUnplayable (budget - 1)

                else
                    advanced

            Nothing ->
                advanced


{-| Begin-of-turn hook for whoever is currently the active creature
after the queue advance and skips. Wrapper that locates the active
creature and dispatches to [`applyBeginOfTurn`](#applyBeginOfTurn).
-}
applyBeginOfTurnHook : Encounter -> Encounter
applyBeginOfTurnHook enc =
    applyBeginOfTurn enc.activeName enc


{-| End-of-turn hook for the named creature: tick down their own
`DurationCountdown AtEnd` conditions (or clear the skipNextTick
flag), expire any `DurationUntilTurn AtEnd <name>` across the
whole encounter, then drop conditions whose countdown hit 0.
-}
applyEndOfTurn : String -> Encounter -> Encounter
applyEndOfTurn name enc =
    enc
        |> tickCountdownFor name AtEnd
        |> tickSaveNoticesFor name
        |> tickTimerFor name AtEnd
        |> expireUntilTurn AtEnd name


{-| Decrement every `SaveNotice` on the named creature by 1.
Notices whose `turnsRemaining` would drop to 0 are removed.

Notices are only created in response to a successful auto-roll
save (manual chip rolls remove their condition silently), so
under normal play every notice should clear after exactly one
bearer end-of-turn.

-}
tickSaveNoticesFor : String -> Encounter -> Encounter
tickSaveNoticesFor name enc =
    mapCreature name
        (\c -> { c | saveNotices = Encounter.SaveNotice.tickList c.saveNotices })
        enc


{-| Decrement the named creature's `Timer` if its phase matches.
A timer at `remaining = 0` is already ringing, so subsequent
ticks are no-ops; the GM dismisses it via the × button on the
card. Same for "no timer set" (Nothing) and "wrong phase".
-}
tickTimerFor : String -> TurnPhase -> Encounter -> Encounter
tickTimerFor name phase enc =
    mapCreature name
        (\c ->
            case c.timer of
                Just t ->
                    if t.ringing || t.phase /= phase then
                        c

                    else
                        let
                            nextRemaining =
                                t.remaining - 1
                        in
                        if nextRemaining <= 0 then
                            { c | timer = Just { t | remaining = 0, ringing = True } }

                        else
                            { c | timer = Just { t | remaining = nextRemaining } }

                Nothing ->
                    c
        )
        enc


{-| Begin-of-turn hook for the named creature: symmetric to
[`applyEndOfTurn`](#applyEndOfTurn) but for `AtBegin` durations.
Also resets the creature's `legendaryActionsUsed` set so the
LA pip column on the card returns to "all available" — that
mirrors the 5e rule that a legendary creature regains its
expended legendary actions at the start of its turn.
Legendary resistances do NOT reset (they're per long rest), so
`legendaryResistanceUsed` stays untouched.
-}
applyBeginOfTurn : String -> Encounter -> Encounter
applyBeginOfTurn name enc =
    enc
        |> tickCountdownFor name AtBegin
        |> tickTimerFor name AtBegin
        |> expireUntilTurn AtBegin name
        |> resetLegendaryActionsFor name


resetLegendaryActionsFor : String -> Encounter -> Encounter
resetLegendaryActionsFor name enc =
    mapCreature name
        (\c -> { c | legendaryActionsUsed = Set.empty })
        enc


{-| Tick down the named creature's `DurationCountdown` conditions
that match `phase`. The skipNextTick flag is consumed (cleared)
without decrementing if it was set; otherwise we decrement the
remaining count. Conditions whose count would drop to 0 are
removed in the same step.
-}
tickCountdownFor : String -> TurnPhase -> Encounter -> Encounter
tickCountdownFor name phase enc =
    mapCreature name (\c -> { c | conditions = List.filterMap (tickCondition phase) c.conditions }) enc


tickCondition : TurnPhase -> Condition -> Maybe Condition
tickCondition phase cond =
    case cond.duration of
        DurationCountdown condPhase remaining skipNextTick ->
            if condPhase /= phase then
                Just cond

            else if skipNextTick then
                Just { cond | duration = DurationCountdown condPhase remaining False }

            else
                let
                    next =
                        remaining - 1
                in
                if next <= 0 then
                    Nothing

                else
                    Just { cond | duration = DurationCountdown condPhase next False }

        _ ->
            Just cond


{-| Walk every creature's condition list and advance any whose
`DurationUntilTurn` matches the phase / creature pair we just
hit.

`target = OnCurrentTurn` → expire (drop the condition).
`target = OnNextTurn` → keep the condition but mutate the
target to `OnCurrentTurn`, so the next matching hook fire will
expire it.

This implements "until end of Lyra's NEXT turn" as exactly two
end-of-Lyra hook fires: first one flips next→current, second one
expires.

-}
expireUntilTurn : TurnPhase -> String -> Encounter -> Encounter
expireUntilTurn phase name enc =
    { enc
        | creatures =
            List.map
                (\c ->
                    { c | conditions = List.filterMap (advanceUntilTurn phase name) c.conditions }
                )
                enc.creatures
    }


advanceUntilTurn : TurnPhase -> String -> Condition -> Maybe Condition
advanceUntilTurn phase name cond =
    case cond.duration of
        DurationUntilTurn condPhase target ref ->
            if condPhase == phase && ref == name then
                case target of
                    OnCurrentTurn ->
                        Nothing

                    OnNextTurn ->
                        Just { cond | duration = DurationUntilTurn condPhase OnCurrentTurn ref }

            else
                Just cond

        _ ->
            Just cond


{-| Advance the marker by exactly one slot, no surprise handling.
The wrap-detection / round-bump logic that used to live in
`nextTurn` itself; pulled out so the skip loop and hook composition
can call it on each iteration.
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


{-| Remove the named creature from the queue.

If the named creature was the active one, advance the marker to
their successor (the next creature in queue order, or the first
if they were last). When the queue empties as a result,
`activeName` becomes the empty string; the title bar's `Maybe`-
aware rendering already handles that case.

No-op when the named creature isn't in the queue.

-}
removeCreature : String -> Encounter -> Encounter
removeCreature name enc =
    if List.any (\c -> c.name == name) enc.creatures then
        let
            successorName =
                findNext name enc.creatures
                    |> Maybe.withDefault
                        (case enc.creatures of
                            first :: _ ->
                                first.name

                            [] ->
                                ""
                        )

            newCreatures =
                List.filter (\c -> c.name /= name) enc.creatures

            newActive =
                if enc.activeName == name then
                    if List.any (\c -> c.name == successorName) newCreatures then
                        successorName

                    else
                        case newCreatures of
                            first :: _ ->
                                first.name

                            [] ->
                                ""

                else
                    enc.activeName
        in
        { enc | creatures = newCreatures, activeName = newActive }

    else
        enc


{-| Duplicate the named creature, inserting the copy immediately
after the source in the queue order.

The copy is a literal clone — same HP, same stats, same
conditions / save notices / timer state — except:

  - `name` gets a `(copy)` / `(copy 2)` / `(copy 3)` suffix so
    the encounter's name-based identity stays unique.
  - `selected` is forced to `False` so a multi-target action
    after duplication doesn't accidentally splatter both copies.
  - Any `conditions` and `saveNotices` carried over get fresh
    encounter-wide unique ids — otherwise edits / removes on the
    source's chips would clobber the duplicate's chips and vice
    versa.

No-op when the named creature isn't in the queue.

-}
duplicateCreature : String -> Encounter -> Encounter
duplicateCreature name enc =
    case findByName name enc.creatures of
        Nothing ->
            enc

        Just src ->
            let
                existingNames =
                    List.map .name enc.creatures

                newName =
                    uniqueCopyName src.name existingNames

                conditionIdStart =
                    (allConditionIds enc
                        |> List.maximum
                        |> Maybe.withDefault 0
                    )
                        + 1

                noticeIdStart =
                    (allSaveNoticeIds enc
                        |> List.maximum
                        |> Maybe.withDefault 0
                    )
                        + 1

                reIdConditions =
                    List.indexedMap
                        (\i cond -> { cond | id = conditionIdStart + i })
                        src.conditions

                reIdNotices =
                    List.indexedMap
                        (\i n -> { n | id = noticeIdStart + i })
                        src.saveNotices

                copy =
                    { src
                        | name = newName
                        , selected = False
                        , conditions = reIdConditions
                        , saveNotices = reIdNotices
                    }
            in
            { enc | creatures = insertAfter name copy enc.creatures }


{-| Generate a unique "<name> (copy)" / "<name> (copy 2)" /
"<name> (copy 3)" form by walking N upward until the candidate
isn't already in `existingNames`.
-}
uniqueCopyName : String -> List String -> String
uniqueCopyName base existingNames =
    let
        candidate i =
            if i == 1 then
                base ++ " (copy)"

            else
                base ++ " (copy " ++ String.fromInt i ++ ")"

        loop i =
            if List.member (candidate i) existingNames then
                loop (i + 1)

            else
                candidate i
    in
    loop 1


{-| Insert `newCreature` immediately after the creature with the
given name. If the anchor name isn't found, the new creature is
appended at the end so the duplicate still ends up in the queue.
-}
insertAfter : String -> Creature -> List Creature -> List Creature
insertAfter anchorName newCreature creatures =
    case creatures of
        [] ->
            [ newCreature ]

        c :: rest ->
            if c.name == anchorName then
                c :: newCreature :: rest

            else
                c :: insertAfter anchorName newCreature rest


{-| Compute the unique display name for a fresh instance of `base`.

The pattern: first instance keeps the bare name, second is
`base ++ " 2"`, third is `base ++ " 3"`, and so on. So adding
three Goblins to a fresh encounter yields
`Goblin / Goblin 2 / Goblin 3`. Adding three more (with the
first three still alive) yields `Goblin 4 / Goblin 5 / Goblin 6`.
This is distinct from `uniqueCopyName`, which uses `(copy)`
suffixes for the right-rail duplicate button.

-}
uniqueInstanceName : String -> List String -> String
uniqueInstanceName base existingNames =
    let
        candidate i =
            if i == 1 then
                base

            else
                base ++ " " ++ String.fromInt i

        loop i =
            if List.member (candidate i) existingNames then
                loop (i + 1)

            else
                candidate i
    in
    loop 1


{-| Append a batch of creatures to the queue, then re-sort by
initiative. Used by the Compendium → queue handoff after the
batch initiative rolls land. `activeName` is preserved so adding
creatures mid-combat doesn't reset whose turn it is.
-}
appendCreatures : List Creature -> Encounter -> Encounter
appendCreatures newcomers enc =
    { enc | creatures = enc.creatures ++ newcomers }
        |> sortByInitiative


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


{-| Death-save helpers re-exported from the dedicated submodule.
The actual implementations and per-helper docs live in
[`Encounter.DeathSaves`](Encounter-DeathSaves). These thin
wrappers exist so existing call sites importing from `Encounter`
keep compiling while we migrate.
-}
emptyDeathSaves : DeathSaves
emptyDeathSaves =
    Encounter.DeathSaves.empty


addDeathSaveSuccesses : Int -> DeathSaves -> DeathSaves
addDeathSaveSuccesses =
    Encounter.DeathSaves.addSuccesses


addDeathSaveFailures : Int -> DeathSaves -> DeathSaves
addDeathSaveFailures =
    Encounter.DeathSaves.addFailures


isDeathSaveStable : DeathSaves -> Bool
isDeathSaveStable =
    Encounter.DeathSaves.isStable


isDeathSaveDead : DeathSaves -> Bool
isDeathSaveDead =
    Encounter.DeathSaves.isDead



-- CONDITIONS / EFFECTS


{-| Append a new condition to the named creature's conditions list.
The id is allocated as one-past-the-current-max across the whole
encounter so it's stable across edits and renames.

If the target creature isn't in the queue this is a no-op (matches
the contract of [`mapCreature`](#mapCreature)).

-}
addCondition : String -> ConditionDraft -> Encounter -> Encounter
addCondition target draft enc =
    let
        nextId =
            allConditionIds enc
                |> List.maximum
                |> Maybe.withDefault 0
                |> (+) 1

        newCondition =
            { id = nextId
            , name = draft.name
            , note = draft.note
            , duration = draft.duration
            , saveToEnd = draft.saveToEnd
            }
    in
    mapCreature target (\c -> { c | conditions = c.conditions ++ [ newCondition ] }) enc


{-| Apply `fn` to one specific condition, identified by its id, on
the named creature. Useful for in-place edits from the modal:
"the user changed the DC; update only this condition."
-}
updateCondition : String -> Int -> (Condition -> Condition) -> Encounter -> Encounter
updateCondition target id fn enc =
    mapCreature target
        (\c ->
            { c
                | conditions =
                    List.map
                        (\cond ->
                            if cond.id == id then
                                fn cond

                            else
                                cond
                        )
                        c.conditions
            }
        )
        enc


{-| Drop the condition with the given id from the named creature's
list. No-op if the creature or condition isn't found.
-}
removeCondition : String -> Int -> Encounter -> Encounter
removeCondition target id enc =
    mapCreature target
        (\c -> { c | conditions = List.filter (\cond -> cond.id /= id) c.conditions })
        enc


{-| Look up a condition by `(creatureName, conditionId)`. Returns
the (creature, condition) pair so callers can act on both — e.g.
"open the modal pre-filled with this existing condition."
-}
findCondition : String -> Int -> Encounter -> Maybe ( Creature, Condition )
findCondition target id enc =
    findByName target enc.creatures
        |> Maybe.andThen
            (\c ->
                c.conditions
                    |> List.filter (\cond -> cond.id == id)
                    |> List.head
                    |> Maybe.map (\cond -> ( c, cond ))
            )


{-| Render a one-line human-readable description of a duration
("Until end of Lyra's turn", "3 turns (begin)", "Manual"). Used by
condition chips on cards and by the modal's preview.
-}
describeDuration : Duration -> String
describeDuration duration =
    case duration of
        DurationManual ->
            "Manual"

        DurationUntilTurn phase target name ->
            let
                phaseWord =
                    case phase of
                        AtBegin ->
                            "start"

                        AtEnd ->
                            "end"

                targetWord =
                    case target of
                        OnCurrentTurn ->
                            "current"

                        OnNextTurn ->
                            "next"
            in
            "Until " ++ phaseWord ++ " of " ++ name ++ "'s " ++ targetWord ++ " turn"

        DurationCountdown AtBegin n _ ->
            String.fromInt n ++ " " ++ pluralizeTurns n ++ " (start)"

        DurationCountdown AtEnd n _ ->
            String.fromInt n ++ " " ++ pluralizeTurns n ++ " (end)"


pluralizeTurns : Int -> String
pluralizeTurns n =
    if n == 1 then
        "turn"

    else
        "turns"


allConditionIds : Encounter -> List Int
allConditionIds enc =
    List.concatMap (\c -> List.map .id c.conditions) enc.creatures



-- SAVE NOTICES


{-| Append a "Saved: <Condition>" notice to the named creature.
Allocated id is one-past-current-max across the encounter so it's
stable for view diffing and explicit removal.

The notice starts at `turnsRemaining = 1`, so the next time the
bearer's end-of-turn hook fires it ticks to 0 and the notice
clears. The GM can dismiss it earlier via the × button.

-}
addSaveNotice : String -> String -> Encounter -> Encounter
addSaveNotice target conditionName enc =
    let
        nextId =
            allSaveNoticeIds enc
                |> List.maximum
                |> Maybe.withDefault 0
                |> (+) 1
    in
    mapCreature target
        (\c -> { c | saveNotices = c.saveNotices ++ [ Encounter.SaveNotice.create nextId conditionName ] })
        enc


{-| Drop the save notice with the given id from the named
creature's list. No-op if the creature or notice isn't found.
-}
removeSaveNotice : String -> Int -> Encounter -> Encounter
removeSaveNotice target id enc =
    mapCreature target
        (\c -> { c | saveNotices = List.filter (\n -> n.id /= id) c.saveNotices })
        enc


allSaveNoticeIds : Encounter -> List Int
allSaveNoticeIds enc =
    List.concatMap (\c -> List.map .id c.saveNotices) enc.creatures
