module Encounter exposing
    ( Cover(..), Creature, DeathSaves, Encounter
    , Condition, ConditionDraft, Duration(..), TurnPhase(..), TurnTarget(..), SaveToEnd
    , AutoRollMode(..)
    , SaveNotice
    , Timer
    , standardConditions
    , empty
    , run
    , setActive, activeCreature
    , mapCreature, nextCover
    , emptyDeathSaves, addDeathSaveSuccesses, addDeathSaveFailures
    , isDeathSaveStable, isDeathSaveDead
    , addCondition, updateCondition, removeCondition, findCondition
    , describeDuration
    , addSaveNotice, removeSaveNotice
    , RechargeAbility, rosterDirty
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


# Combat startup

`round = 0` is the pre-combat sentinel: the queue is set up
but no one has taken a turn. [`run`](#run) flips the encounter
into round 1 and picks the first creature as active.

@docs run


# Turn marker

`setActive` is the manual scrub: move the marker to a specific
creature without counting as turn progression. The full
turn-progression walk (`nextTurn` + begin/end-of-turn hooks)
lives in [`Encounter.Lifecycle`](Encounter-Lifecycle). Queue
mutation (move, sort, remove, duplicate, append) lives in
[`Encounter.Roster`](Encounter-Roster).

@docs setActive, activeCreature


# State helpers

@docs mapCreature, nextCover


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
import Encounter.Treasure
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


{-| One recharge-style ability tracked on an in-encounter creature
instance. Seeded at spawn time from any compendium feature whose
`Usage` is `Recharge { low, high }` — typical examples are dragon
Breath Weapons ("Recharge 5–6").

The GM-facing flow: while `ready = True`, the chip is green and
clicking marks it spent. Once spent, nothing happens until the
START of the creature's next turn — at that point the begin-of-
turn lifecycle hook flips `awaitingRoll = True`, the card's chip
splits into a blinking 🎲 (roll d6) + ability-name (mark ready
without rolling), and the GM resolves the recharge themselves.
Rolling resets `awaitingRoll = False` regardless of outcome, so
a failed roll doesn't keep re-prompting on the same turn — the
GM gets one attempt per turn, just like RAW.

The `awaitingRoll` flag is what makes the "wait until next turn"
behaviour work: spending the ability mid-turn does NOT set it,
so the dice doesn't appear on the same turn it was spent.

The compendium captures other Usage kinds (`PerDay`,
`PerShortRest`, `PerLongRest`, `AtWill`) but those don't fit the
"recharge each round" model; they're tracked elsewhere (or
manually) and don't live in this list.

-}
type alias RechargeAbility =
    { name : String
    , low : Int
    , high : Int
    , ready : Bool
    , awaitingRoll : Bool
    }


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
    , note : String
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

  - `cover`, `concentrating`, `hiding`, `dodging`, `flying`,
    `flyHeight` — row 2.
  - `bloodied`, `deathSaves` — row 2 HP indicators. The death-save
    tracker (see [`DeathSaves`](#DeathSaves)) is gated on a separate
    `acceptingDeathSaves` opt-in toggle so that a creature dropped
    to 0 HP shows a single "Death Saves" button by default — most of
    the time the GM doesn't want a downed enemy to make saves, and
    revealing the pip strip eagerly is noise. Clicking the button
    flips the toggle and the pips become visible. Healing back above
    0 resets BOTH the counts and the toggle via the HP-change engine.
  - `readied` — row 3 readied-action toggle.

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
    , cover : Cover
    , concentrating : Bool
    , hiding : Bool
    , dodging : Bool
    , flying : Bool
    , flyHeight : Int
    , bloodied : Bool
    , deathSaves : DeathSaves
    , acceptingDeathSaves : Bool
    , reactionUsed : Bool
    , rechargeAbilities : List RechargeAbility
    , readied : Bool
    , inactive : Bool
    , note : String
    , memo : String
    , timer : Maybe Timer
    , creatureId : Maybe String

    -- Legendary Actions: how many pips show on the card.
    -- `legendaryActionsCount` is the base count from the stat
    -- block (e.g. 3 for most legendary creatures); `lairBonus`
    -- is the extra pips that appear with a slightly larger
    -- gap, labeled "Lair bonus" on hover.  A count of 0 means
    -- the creature has no LA — the column doesn't render.
    , legendaryActionsCount : Int
    , legendaryActionsLairBonus : Int
    , legendaryActionsUsed : Set Int

    -- Legendary Resistance: same shape as LA but parsed from
    -- the creature's "Legendary Resistance (N/Day, or M/Day
    -- in Lair)" trait name.  Unlike LA, the column doesn't
    -- auto-reset at turn start — LR is per long rest in 5e
    -- and the GM controls it manually.
    , legendaryResistanceCount : Int
    , legendaryResistanceLairBonus : Int
    , legendaryResistanceUsed : Set Int
    , isPlaceholder : Bool

    -- Structured identity badges separate from the legacy
    -- `kind` field (which still holds the combined "Race,
    -- Alignment" descriptor for back-compat / wire payloads).
    -- `creatureKind` is one of "player" / "enemy" / "npc";
    -- `race` and `alignment` are free-form strings rendered as
    -- their own badges by the Custom Card renderer.
    , creatureKind : String
    , race : String
    , alignment : String

    -- 5e Surprised: cleared automatically at the end of the
    -- creature's first turn (handled by Encounter.Lifecycle).
    -- A surprised creature renders a small icon next to its name
    -- on the card + active-creature header and is excluded from
    -- the legendary-action availability banner because the rule
    -- bars LA use while surprised.
    , surprised : Bool

    -- "Special reaction mechanics" hint copied from the
    -- compendium source.  When True, the card's reaction pip
    -- swaps its lightning glyph for a bold yellow `!` and the
    -- hover text points the GM at the stat block — Hydra's
    -- Reactive Heads, Marilith's Reactive, Vampire's Misty
    -- Escape, mephit Death Bursts, and assorted notable named
    -- reactions all need a GM heads-up that the standard
    -- "one reaction per round" UX doesn't cover.
    , hasSpecialReactions : Bool
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
    , treasure : Maybe Encounter.Treasure.TreasureRoll
    , treasureSettings : Encounter.Treasure.TreasureSettings
    }



-- INITIAL STATE


{-| The empty encounter the running app boots into. The previous
"`initialEncounter` is a fixed cast" pattern lives on as a TEST
fixture (see `Encounter.Seed.initialEncounter`) — but the running
app starts empty and either loads a persisted encounter from the
server or waits for the user to add creatures from the compendium.

`round = 0` is the pre-combat sentinel — see [`run`](#run).

-}
empty : Encounter
empty =
    { creatures = []
    , activeName = ""
    , round = 0
    , treasure = Nothing
    , treasureSettings = Encounter.Treasure.defaultSettings
    }


{-| Begin combat: bump round from 0 to 1 and pick the first
creature in the queue as active. The queue is in initiative
order, so "first" is the highest-initiative combatant.

This is the "Run Encounter" half of the round-0 sentinel: the
GM lays out the encounter pre-combat (round 0, no one active),
then clicks Run to begin and the queue starts ticking.

-}
run : Encounter -> Encounter
run enc =
    let
        firstActiveName =
            case List.head enc.creatures of
                Just c ->
                    c.name

                Nothing ->
                    ""
    in
    { enc | round = 1, activeName = firstActiveName }


{-| `True` when the current encounter's roster differs from the
last-saved snapshot — i.e. a creature has been added or removed
since the last Save (or Load). Compared by the _set_ of creature
names (sorted before comparison), so reordering the initiative
queue does NOT count as dirty, and neither does HP / condition /
position drift inside an unchanged roster.

A `Nothing` snapshot (the app has never been saved nor loaded) is
treated as an empty roster, so a fresh queue with creatures shows
dirty until the first save.

The Save button uses this to surface a yellow outline cue when
the encounter has unsaved roster changes.

-}
rosterDirty : Encounter -> Maybe Encounter -> Bool
rosterDirty current snapshot =
    let
        currentNames =
            List.sort (List.map .name current.creatures)

        snapshotNames =
            case snapshot of
                Just snap ->
                    List.sort (List.map .name snap.creatures)

                Nothing ->
                    []
    in
    currentNames /= snapshotNames



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



-- STATE HELPERS


{-| Apply `fn` to whichever creature in the encounter has `name`; pass
through all other creatures (and the rest of the encounter) unchanged.
Used by every per-creature toggle (cover, concentrating, hiding,
dodging, flying, fly-height, death-save slots, readied action).

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

        DurationUntilTurn phase _ name ->
            -- The TurnTarget discriminator is no longer surfaced to
            -- the GM; from their perspective, every "until-turn"
            -- condition expires when the named creature's turn
            -- next comes up.  The Current/Next bit is now a purely
            -- internal "skip first fire?" detail computed at submit
            -- time.
            let
                phaseWord =
                    case phase of
                        AtBegin ->
                            "start"

                        AtEnd ->
                            "end"
            in
            "Until " ++ phaseWord ++ " of " ++ name ++ "'s next turn"

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
