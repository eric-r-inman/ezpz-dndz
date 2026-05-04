module Update.Encounter exposing
    ( adjustFlyHeight
    , cycleCover
    , duplicateCreature
    , moveCreatureDown
    , moveCreatureUp
    , nextTurn
    , removeCreature
    , setActive
    , shiftToggleSelected
    , toggleConcentration
    , toggleFlying
    , toggleHiding
    , toggleHolding
    , toggleSelected
    , toggleSurprised
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

import Effects
import Encounter exposing (Encounter)
import Encounter.Lifecycle
import Encounter.Roster
import Model exposing (Model)
import Msg exposing (Msg)


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
    in
    ( { model | encounter = newEnc }
    , Cmd.batch
        (Effects.scrollActiveIntoView newEnc.activeName
            :: endRolls
            ++ beginRolls
        )
    )


{-| Manual jump (the right-arrow button on a card). Distinct from
`nextTurn`: no round bump, no turn-progression hooks. Scroll-into-view
still runs so the GM sees the card they just promoted.
-}
setActive : String -> Model -> ( Model, Cmd Msg )
setActive name model =
    ( withEncounter (Encounter.setActive name) model
    , Effects.scrollActiveIntoView name
    )


toggleSurprised : String -> Model -> ( Model, Cmd Msg )
toggleSurprised name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | surprised = not c.surprised })) model
    , Cmd.none
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


toggleHolding : String -> Model -> ( Model, Cmd Msg )
toggleHolding name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | holding = not c.holding })) model
    , Cmd.none
    )


toggleSelected : String -> Model -> ( Model, Cmd Msg )
toggleSelected name model =
    ( withEncounter (Encounter.mapCreature name (\c -> { c | selected = not c.selected })) model
    , Cmd.none
    )


{-| Bulk: if every creature is already selected, deselect all;
otherwise select all. The clicked creature ends up in the resulting
bulk state regardless of where it started.
-}
shiftToggleSelected : Model -> ( Model, Cmd Msg )
shiftToggleSelected model =
    let
        allSelected =
            List.all .selected model.encounter.creatures

        newValue =
            not allSelected
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


duplicateCreature : String -> Model -> ( Model, Cmd Msg )
duplicateCreature name model =
    ( withEncounter (Encounter.Roster.duplicateCreature name) model, Cmd.none )
