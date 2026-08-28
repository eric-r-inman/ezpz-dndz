module Update.Encounter exposing
    ( addPlaceholder
    , adjustFlyHeight
    , controlCancel
    , controlConfirm
    , cycleCover
    , fallDamageLanded
    , moveCreatureDown
    , moveCreatureUp
    , nextTurn
    , rechargeRollLanded
    , removeCreature
    , requestClear
    , requestReset
    , rollFallDamage
    , rollRechargeNow
    , run
    , setActive
    , shiftToggleSelected
    , toggleConcentration
    , toggleDodging
    , toggleFlying
    , toggleHiding
    , toggleInactive
    , toggleReaction
    , toggleReadied
    , toggleRechargeAbility
    , toggleSelected
    )

{-| Update branches that mutate the encounter queue or per-creature
position / posture flags. All branches are dispatcher one-liners in
`Main.update`; the real work is here.

The lifecycle hooks in `nextTurn` (auto-roll saves at end-of-turn /
begin-of-turn, scroll-into-view) are kept in this module rather than
in `Encounter.Lifecycle` because they're effectful — pure rules work
already moved into `Encounter.Lifecycle.nextTurn`, leaving only the
`Cmd Msg` plumbing here.

-}

import Dice
import Effects
import Encounter exposing (Encounter)
import Encounter.Lifecycle
import Encounter.Roster
import Model exposing (Model, PendingControl(..))
import Msg exposing (Msg(..))
import Set


{-| Local lens for `model.encounter`. Kept private to this module —
other Update modules either don't touch the encounter or own their
own narrower lens.
-}
withEncounter : (Encounter -> Encounter) -> Model -> Model
withEncounter fn model =
    { model | encounter = fn model.encounter }


{-| Advance the queue one slot. Domain layer owns the queue walk,
round bookkeeping, and condition lifecycle hooks (begin / end of
turn). The update layer fires the side effects:

  - auto-roll saves at the OUTGOING creature's end-of-turn
    (`AutoRollAtEnd`),
  - auto-roll saves at the INCOMING creature's begin-of-turn
    (`AutoRollAtBegin`),
  - and a viewport check so the active card scrolls into view.

Both auto-roll batches read the post-`nextTurn` encounter so they
see the outgoing creature's conditions AFTER end-of-turn ticks (any
`UntilTurn AtEnd <self>` already expired, so we don't roll for a
condition the engine just removed).

-}
nextTurn : Model -> ( Model, Cmd Msg )
nextTurn model =
    let
        outgoingName =
            model.encounter.activeName

        newEnc =
            Encounter.Lifecycle.nextTurn model.encounter

        endRolls =
            Effects.autoRollCmdsFor Encounter.AutoRollAtEnd outgoingName newEnc

        beginRolls =
            Effects.autoRollCmdsFor Encounter.AutoRollAtBegin newEnc.activeName newEnc

        scrollCmds =
            if model.preferences.autoScrollActiveCard then
                [ Effects.scrollActiveIntoView newEnc.activeName ]

            else
                []
    in
    -- Recharge d6s used to auto-fire here; the card now renders a
    -- blinking dice glyph on the active creature's spent recharge
    -- chip and the GM clicks to roll, so we don't include the
    -- recharge cmds in the turn-advance batch any more.
    ( { model | encounter = newEnc }
    , Cmd.batch (scrollCmds ++ endRolls ++ beginRolls)
    )


{-| Manual jump (the right-arrow button on a card). Distinct from
`nextTurn`: no round bump, no turn-progression hooks. Scroll-into-view
still runs (and ignores the preference) so the GM sees the card
they just promoted — the preference only governs the automatic
end-of-turn scroll, not explicit user-initiated focus changes.
-}
setActive : String -> Model -> ( Model, Cmd Msg )
setActive name model =
    ( withEncounter (Encounter.setActive name) model
    , Effects.scrollActiveIntoView name
    )


cycleCover : String -> Model -> ( Model, Cmd Msg )
cycleCover name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | cover = Encounter.nextCover c.cover })) model
    , Cmd.none
    )


toggleConcentration : String -> Model -> ( Model, Cmd Msg )
toggleConcentration name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | concentrating = not c.concentrating })) model
    , Cmd.none
    )


toggleHiding : String -> Model -> ( Model, Cmd Msg )
toggleHiding name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | hiding = not c.hiding })) model
    , Cmd.none
    )


toggleDodging : String -> Model -> ( Model, Cmd Msg )
toggleDodging name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | dodging = not c.dodging })) model
    , Cmd.none
    )


toggleFlying : String -> Model -> ( Model, Cmd Msg )
toggleFlying name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | flying = not c.flying })) model
    , Cmd.none
    )


adjustFlyHeight : String -> Int -> Model -> ( Model, Cmd Msg )
adjustFlyHeight name delta model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | flyHeight = Basics.max 0 (c.flyHeight + delta) })) model
    , Cmd.none
    )


toggleReadied : String -> Model -> ( Model, Cmd Msg )
toggleReadied name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | readied = not c.readied })) model
    , Cmd.none
    )


{-| Toggle the per-creature reaction pip. Every creature gets one
reaction per round in 5e (opportunity attack, Counterspell,
Shield, Hellish Rebuke…); the pip flips back to "available"
automatically at the start of the creature's next turn — see
`Encounter.Lifecycle.applyBeginOfTurn` for the reset. Click is
also wired manually so the GM can adjust if they need to undo
or pre-spend.
-}
toggleReaction : String -> Model -> ( Model, Cmd Msg )
toggleReaction name model =
    ( withEncounter
        (Encounter.mapCreature name (\c -> { c | reactionUsed = not c.reactionUsed }))
        model
    , Cmd.none
    )


{-| Flip a single recharge ability between ready / expended. Used
when the GM clicks the recharge chip on a creature's card —
useful when the engine's auto-roll outcome is wrong (a homebrew
recharge rule fired, or the GM wants to pre-expend / refund).
No-op if no ability with `abilityName` is found.
-}
toggleRechargeAbility : String -> String -> Model -> ( Model, Cmd Msg )
toggleRechargeAbility creatureName abilityName model =
    ( withEncounter
        (Encounter.mapCreature creatureName
            (\c ->
                { c
                    | rechargeAbilities =
                        List.map
                            (\a ->
                                if a.name == abilityName then
                                    -- Always clear awaitingRoll on toggle:
                                    -- ready→spent shouldn't surface the prompt
                                    -- this turn (it waits for the next begin-
                                    -- of-turn hook), and spent→ready obviously
                                    -- doesn't need the prompt either.
                                    { a | ready = not a.ready, awaitingRoll = False }

                                else
                                    a
                            )
                            c.rechargeAbilities
                }
            )
        )
        model
    , Cmd.none
    )


{-| Fire the recharge d6 for a single ability on demand —
wired to the blinking dice glyph on the spent + active chip.
The roll continuation lands in `rechargeRollLanded` just like
the previous auto-roll path did, so result handling is shared.

A no-op if the ability is already ready (the dice shouldn't be
clickable in that state, but we guard defensively against a
stale click during a transition).

-}
rollRechargeNow : String -> String -> Model -> ( Model, Cmd Msg )
rollRechargeNow creatureName abilityName model =
    let
        ability =
            model.encounter.creatures
                |> List.filter (\c -> c.name == creatureName)
                |> List.concatMap .rechargeAbilities
                |> List.filter (\a -> a.name == abilityName)
                |> List.head
    in
    case ability of
        Just a ->
            case Effects.rechargeRollCmd creatureName a of
                Just cmd ->
                    ( model, cmd )

                Nothing ->
                    ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


{-| Begin-of-turn d6 landed for one recharge ability. If the
total meets the ability's `low` threshold, flip `ready = True`.
Either way, push the roll into the dice history so the GM can
see what was rolled. No-op if the ability is no longer on the
creature (e.g. the GM edited it away between roll fire and
landing).
-}
rechargeRollLanded : String -> String -> Dice.Roll -> Model -> ( Model, Cmd Msg )
rechargeRollLanded creatureName abilityName roll model =
    let
        nextEncounter =
            Encounter.mapCreature creatureName
                (\c ->
                    { c
                        | rechargeAbilities =
                            List.map
                                (\a ->
                                    if a.name == abilityName then
                                        -- Clear awaitingRoll regardless of
                                        -- outcome: a failed roll doesn't get
                                        -- to re-prompt on the same turn
                                        -- (RAW: one recharge attempt per
                                        -- turn).  Next begin-of-turn hook
                                        -- will set it back if still spent.
                                        { a
                                            | ready = roll.total >= a.low
                                            , awaitingRoll = False
                                        }

                                    else
                                        a
                                )
                                c.rechargeAbilities
                    }
                )
                model.encounter

        ( pushed, flashCmd ) =
            Effects.pushDiceRoll roll { model | encounter = nextEncounter }
    in
    ( pushed, flashCmd )


{-| Toggle the per-creature `inactive` flag. An inactive
creature stays in the queue (visible, editable) but is skipped
by `Encounter.Lifecycle.nextTurn` — useful for benched mounts,
NPCs whose turn the GM doesn't want to take, or anyone waiting
to enter combat later. The card view greys the creature out so
the state is visible at a glance.
-}
toggleInactive : String -> Model -> ( Model, Cmd Msg )
toggleInactive name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | inactive = not c.inactive })) model
    , Cmd.none
    )


toggleSelected : String -> Model -> ( Model, Cmd Msg )
toggleSelected name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | selected = not c.selected })) model
    , Cmd.none
    )


{-| Bulk: shift-clicking a selected creature's box clears the
whole selection; shift-clicking an unselected one selects
everyone. The clicked box's own state decides the direction, so
the gesture always inverts what the GM is pointing at.
-}
shiftToggleSelected : String -> Model -> ( Model, Cmd Msg )
shiftToggleSelected name model =
    let
        clickedSelected =
            model.encounter.creatures
                |> List.filter (\c -> c.name == name)
                |> List.head
                |> Maybe.map .selected
                |> Maybe.withDefault False

        newValue =
            not clickedSelected
    in
    ( withEncounter
        (\enc ->
            { enc
                | creatures =
                    List.map (\c -> { c | selected = newValue })
                        enc.creatures
            }
        )
        model
    , Cmd.none
    )


{-| Manual queue reordering (the up/down arrows on each card). Pure
position swaps; initiative isn't touched. A later `sortByInitiative`
wipes the manual order, which matches the documented contract.
-}
moveCreatureUp : String -> Model -> ( Model, Cmd Msg )
moveCreatureUp name model =
    ( withEncounter (Encounter.Roster.moveUp name) model, Cmd.none )


moveCreatureDown : String -> Model -> ( Model, Cmd Msg )
moveCreatureDown name model =
    ( withEncounter (Encounter.Roster.moveDown name) model, Cmd.none )


removeCreature : String -> Model -> ( Model, Cmd Msg )
removeCreature name model =
    ( withEncounter (Encounter.Roster.removeCreature name) model, Cmd.none )


{-| Drop a "Placeholder N" stub at the bottom of the queue. No
sort — see `Encounter.Roster.appendPlaceholder` for the rationale.
-}
addPlaceholder : Model -> ( Model, Cmd Msg )
addPlaceholder model =
    ( withEncounter Encounter.Roster.appendPlaceholder model, Cmd.none )


{-| First click of Reset: stage the pending state so the panel
renders the confirmation banner. The actual revert happens in
[`controlConfirm`](#controlConfirm); this branch is purely
about asking "are you sure?" before touching the encounter.
-}
requestReset : Model -> ( Model, Cmd Msg )
requestReset model =
    ( { model | pendingControl = Just PendingReset }, Cmd.none )


{-| First click of Clear — see [`requestReset`](#requestReset);
the only difference is the pending tag.
-}
requestClear : Model -> ( Model, Cmd Msg )
requestClear model =
    ( { model | pendingControl = Just PendingClear }, Cmd.none )


{-| Apply whichever destructive action is currently staged.

  - `PendingReset` — keep the current roster intact but wipe each
    creature's per-fight state: HP back to full, no temp HP, no
    conditions / save notices / death saves, every status toggle
    off (cover, concentration, hiding, dodging, flying, readied,
    inactive), legendary actions / resistances refilled, timers
    cleared. Identity + combat baselines (name, kind, initiative,
    AC, max HP, note, memo, compendium back-reference) survive
    untouched. Round counter goes back to 0 and `activeName`
    clears so the GM is back in pre-combat mode with the same
    cast.
  - `PendingClear` — drop every creature; force `round = 0`.

In both cases the pending state is cleared so the panel returns
to its normal button grid.

-}
controlConfirm : Model -> ( Model, Cmd Msg )
controlConfirm model =
    case model.pendingControl of
        Just PendingReset ->
            let
                enc =
                    model.encounter

                resetEnc =
                    { enc
                        | creatures = List.map resetCreatureState enc.creatures
                        , round = 0
                        , activeName = ""
                    }
            in
            ( { model | encounter = resetEnc, pendingControl = Nothing }
            , Cmd.none
            )

        Just PendingClear ->
            ( { model
                | encounter = Encounter.empty
                , pendingControl = Nothing
              }
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


{-| Strip a creature back to "round 0" state. Identity + combat
baselines (name, kind, initiative, ability stats, AC, max HP,
note, memo, compendium id, legendary capability flags, selection
checkbox) are preserved; everything that can change mid-fight is
reset.
-}
resetCreatureState : Encounter.Creature -> Encounter.Creature
resetCreatureState c =
    { c
        | currentHp = c.maxHp
        , tempHp = 0
        , conditions = []
        , saveNotices = []
        , cover = Encounter.NoCover
        , concentrating = False
        , hiding = False
        , dodging = False
        , flying = False
        , flyHeight = 0
        , bloodied = False
        , deathSaves = Encounter.emptyDeathSaves
        , acceptingDeathSaves = False
        , reactionUsed = False
        , rechargeAbilities =
            -- Identity-level data: the abilities themselves
            -- persist (they're the creature's stat block, not
            -- per-fight state).  Per-fight state on each — ready
            -- + the begin-of-turn awaiting-roll prompt — resets.
            List.map
                (\a -> { a | ready = True, awaitingRoll = False })
                c.rechargeAbilities
        , readied = False
        , inactive = False
        , timer = Nothing
        , legendaryActionsUsed = Set.empty
        , legendaryResistanceUsed = Set.empty
        , specialReactionsUsed = Set.empty
    }


{-| Calculate falling damage for the named creature and fire it
through the dice history.

5e fall damage: 1d6 per 10 feet fallen, capped at 20d6. Heights
are rounded DOWN to the nearest 10-foot segment, so 26 ft → 2d6.
A creature at 0–9 ft of altitude takes no damage.

The damage isn't auto-applied to the creature's HP — the GM gets
to decide (saving throw / feather fall / etc.). The roll lands
in the shared dice history so the title bar's "latest total"
readout updates and the dice modal can be opened later for the
full breakdown.

The creature's `flying` flag is cleared (and `flyHeight` reset to

1.  regardless of whether any dice were actually rolled — the
    button click means "they hit the ground."

-}
rollFallDamage : String -> Model -> ( Model, Cmd Msg )
rollFallDamage name model =
    let
        flyHeight =
            findFlyHeight name model.encounter

        diceCount =
            Basics.min 20 (flyHeight // 10)

        landedCmd =
            if diceCount > 0 then
                Dice.rollCmd
                    (FallDamageLanded name)
                    { feature = "Fall damage", target = Just name }
                    (fallExpression diceCount)

            else
                Cmd.none

        groundedEnc =
            Encounter.mapCreature name
                (\c -> { c | flying = False, flyHeight = 0 })
                model.encounter
    in
    ( { model | encounter = groundedEnc }, landedCmd )


{-| Push the fall-damage roll into the shared dice history so the
title-bar readout updates and the dice modal sees it on next
open. No HP mutation — see `rollFallDamage`.
-}
fallDamageLanded : String -> Dice.Roll -> Model -> ( Model, Cmd Msg )
fallDamageLanded _ roll model =
    let
        ( pushed, flashCmd ) =
            Effects.pushDiceRoll roll model
    in
    ( pushed
    , Cmd.batch [ Effects.persistDiceRoll roll, flashCmd ]
    )


findFlyHeight : String -> Encounter -> Int
findFlyHeight name enc =
    enc.creatures
        |> List.filter (\c -> c.name == name)
        |> List.head
        |> Maybe.map .flyHeight
        |> Maybe.withDefault 0


fallExpression : Int -> Dice.Expression
fallExpression count =
    { dice = [ { count = count, faces = 6, sign = Dice.Positive } ]
    , constant = 0
    , damageType = Just "bludgeoning"
    }


{-| "Run Encounter": flip the round-0 sentinel to round 1 and
pick the highest-initiative creature as active. Domain rules
live in [`Encounter.run`](Encounter#run); this branch handles
the scroll-into-view side-effect so the new active card is
visible.
-}
run : Model -> ( Model, Cmd Msg )
run model =
    let
        nextEnc =
            Encounter.run model.encounter
    in
    ( { model | encounter = nextEnc }
    , if String.isEmpty nextEnc.activeName then
        Cmd.none

      else
        Effects.scrollActiveIntoView nextEnc.activeName
    )


{-| Drop the staged action without touching the encounter.
-}
controlCancel : Model -> ( Model, Cmd Msg )
controlCancel model =
    ( { model | pendingControl = Nothing }, Cmd.none )
