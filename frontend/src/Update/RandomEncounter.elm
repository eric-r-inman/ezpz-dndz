module Update.RandomEncounter exposing
    ( open, close
    , difficultySet, scaleSet, habitatSet, creatureTypeAt, minionsToggle
    , pinSearchChanged, pinAdd, pinDecrement, pinRemove
    , generate, rolled
    , addToEncounter
    )

{-| Update handlers for the Random Encounter modal.

The party (`model.party`) is shared with the CR Calculator —
opening the random-encounter modal seeds a default party if
none exists, mirroring `Update.CrCalculator.open`. Difficulty
and habitat live on the modal substate so they reset on close.

Generation goes through `Random.generate` so the entropy comes
from the runtime; we don't carry a seed. Re-rolling is just
"fire `generate` again with the same params".

@docs open, close
@docs difficultySet, scaleSet, habitatSet, creatureTypeAt, minionsToggle
@docs pinSearchChanged, pinAdd, pinDecrement, pinRemove
@docs generate, rolled
@docs addToEncounter

-}

import Compendium exposing (Creature)
import Encounter
import Encounter.RandomEncounter as RE exposing (Scale(..), TargetDifficulty(..))
import Encounter.Roster
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Random
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.RandomEncounter as Ui exposing (RollState(..))
import Ui.Toast exposing (ToastKind(..))
import Update.Toast



-- ── OPEN / CLOSE ─────────────────────────────────────────────────────────────


open : Model -> ( Model, Cmd Msg )
open model =
    let
        seeded =
            if List.isEmpty model.party then
                let
                    members =
                        List.range 1 4
                            |> List.map (\i -> { id = i, level = 1 })
                in
                { model | party = members, nextPartyMemberId = 5 }

            else
                model
    in
    ( { seeded | modal = Just (ModalRandomEncounter Ui.fresh) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )



-- ── PARAM SETTERS ────────────────────────────────────────────────────────────


{-| Map the wire token from the difficulty <select> to the
ADT. The view sends raw values ("low" / "moderate" / "high");
anything else is ignored as defensive handling against a stale
DOM element.

Changing difficulty clears any previous roll so the GM doesn't
think "this roll matches what I just selected" — it doesn't,
until they hit Generate again.

-}
difficultySet : String -> Model -> ( Model, Cmd Msg )
difficultySet raw model =
    let
        decoded =
            case raw of
                "low" ->
                    Just Low

                "moderate" ->
                    Just Moderate

                "high" ->
                    Just High

                _ ->
                    Nothing
    in
    case decoded of
        Just d ->
            ( Model.mapModal Model.randomEncounterLens
                (\ui -> { ui | difficulty = d, roll = RollIdle })
                model
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


{-| `""` is the "Any habitat" wildcard; everything else goes
through `Compendium.habitatFromWire`. As with difficulty,
clear the previous roll so the result panel never
out-of-syncs with the controls.
-}
habitatSet : String -> Model -> ( Model, Cmd Msg )
habitatSet raw model =
    let
        habitat =
            if raw == "" then
                Nothing

            else
                Compendium.habitatFromWire raw
    in
    ( Model.mapModal Model.randomEncounterLens
        (\ui -> { ui | habitat = habitat, roll = RollIdle })
        model
    , Cmd.none
    )


{-| Scale picker wire — "one" / "few" / "many" map via
`RE.scaleFromWire`. Same reset-roll discipline.
-}
scaleSet : String -> Model -> ( Model, Cmd Msg )
scaleSet raw model =
    case RE.scaleFromWire raw of
        Just s ->
            ( Model.mapModal Model.randomEncounterLens
                (\ui -> { ui | scale = s, roll = RollIdle })
                model
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


{-| Set or remove a creature-type filter at a specific slot in
the OR-of-types list. The view renders N+1 <select>s where
N is the current length of `creatureTypes`; the final slot is
the "add another" picker.

  - `index < length` + `raw == ""` → drop that slot.
  - `index < length` + `raw /= ""` → replace at that slot.
  - `index == length` + `raw /= ""` → append.
  - `index == length` + `raw == ""` → no-op (the trailing
    blank stays blank).
  - Out-of-range indices are ignored as a defence against a
    stale DOM dispatching a Msg the model can no longer
    interpret.

-}
creatureTypeAt : Int -> String -> Model -> ( Model, Cmd Msg )
creatureTypeAt index raw model =
    ( Model.mapModal Model.randomEncounterLens
        (\ui ->
            { ui
                | creatureTypes = updateTypeSlot index raw ui.creatureTypes
                , roll = RollIdle
            }
        )
        model
    , Cmd.none
    )


updateTypeSlot : Int -> String -> List String -> List String
updateTypeSlot index raw types =
    let
        len =
            List.length types
    in
    if index < 0 || index > len then
        types

    else if index == len then
        if raw == "" then
            types

        else
            types ++ [ raw ]

    else if raw == "" then
        List.indexedMap Tuple.pair types
            |> List.filter (\( i, _ ) -> i /= index)
            |> List.map Tuple.second

    else
        List.indexedMap
            (\i v ->
                if i == index then
                    raw

                else
                    v
            )
            types


{-| Flip the include-minions checkbox. Same reset-roll
discipline as the other param setters.
-}
minionsToggle : Model -> ( Model, Cmd Msg )
minionsToggle model =
    ( Model.mapModal Model.randomEncounterLens
        (\ui ->
            { ui
                | includeMinions = not ui.includeMinions
                , roll = RollIdle
            }
        )
        model
    , Cmd.none
    )



-- ── PIN PICKER ───────────────────────────────────────────────────────────────


{-| Search text edits update in real time; the view re-filters
on every keystroke. We DON'T reset the roll here because
changing the search doesn't change the pinned set — only adding
or removing a pin does.
-}
pinSearchChanged : String -> Model -> ( Model, Cmd Msg )
pinSearchChanged raw model =
    ( Model.mapModal Model.randomEncounterLens
        (\ui -> { ui | pinSearch = raw })
        model
    , Cmd.none
    )


{-| Pin a creature by id. If it's already pinned, bump its
count; otherwise append a new entry with count 1. The id lookup
goes through `model.compendium.db` so a stale id silently no-ops
rather than producing a phantom entry.

Clears the search field after pinning so the next add starts
fresh.

-}
pinAdd : String -> Model -> ( Model, Cmd Msg )
pinAdd id model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            case Compendium.find id db of
                Just creature ->
                    ( Model.mapModal Model.randomEncounterLens
                        (\ui ->
                            { ui
                                | pinned = bumpPin creature ui.pinned
                                , pinSearch = ""
                                , roll = RollIdle
                            }
                        )
                        model
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


bumpPin :
    Creature
    -> List ( Creature, Int )
    -> List ( Creature, Int )
bumpPin creature pinned =
    let
        ( bumped, found ) =
            List.foldr
                (\( c, n ) ( acc, alreadyFound ) ->
                    if c.id == creature.id then
                        ( ( c, n + 1 ) :: acc, True )

                    else
                        ( ( c, n ) :: acc, alreadyFound )
                )
                ( [], False )
                pinned
    in
    if found then
        bumped

    else
        pinned ++ [ ( creature, 1 ) ]


{-| Nudge a pin's count down by one, clamped at 1. To zero out
an entry the GM uses `pinRemove` (the × button on the row);
this handler exists so the `−` button never triggers a
surprise "row disappeared" jump.
-}
pinDecrement : String -> Model -> ( Model, Cmd Msg )
pinDecrement id model =
    ( Model.mapModal Model.randomEncounterLens
        (\ui ->
            { ui
                | pinned =
                    List.map
                        (\( c, n ) ->
                            if c.id == id then
                                ( c, max 1 (n - 1) )

                            else
                                ( c, n )
                        )
                        ui.pinned
                , roll = RollIdle
            }
        )
        model
    , Cmd.none
    )


{-| Remove a pin entirely regardless of its current count.
-}
pinRemove : String -> Model -> ( Model, Cmd Msg )
pinRemove id model =
    ( Model.mapModal Model.randomEncounterLens
        (\ui ->
            { ui
                | pinned = List.filter (\( c, _ ) -> c.id /= id) ui.pinned
                , roll = RollIdle
            }
        )
        model
    , Cmd.none
    )



-- ── GENERATE / ROLLED ────────────────────────────────────────────────────────


{-| Fire the generator. Reads the loaded compendium pool from
`model.compendium.db`; if the compendium isn't loaded yet
(network in flight, or an HTTP failure during boot) we no-op
quietly — the view's button is gated on the same condition so
this is defensive belt-and-suspenders.
-}
generate : Model -> ( Model, Cmd Msg )
generate model =
    case ( model.modal, model.compendium.db ) of
        ( Just (ModalRandomEncounter ui), CompendiumDbLoaded db ) ->
            let
                budget =
                    RE.budgetFor model.party ui.difficulty

                gen =
                    RE.generator
                        { budget = budget
                        , habitat = ui.habitat
                        , creatureTypes = ui.creatureTypes
                        , scale = ui.scale
                        , includeMinions = ui.includeMinions
                        , pinned = ui.pinned
                        }
                        (Compendium.toList db)
            in
            ( model, Random.generate RandomEncounterRolled gen )

        _ ->
            ( model, Cmd.none )


{-| Continuation: the result lands here. Empty list signals the
pool was empty (no creatures matched the filters at the chosen
budget); store the distinct state so the view can render a
"no matches" notice instead of a stale previous roll.
-}
rolled : List ( Creature, Int ) -> Model -> ( Model, Cmd Msg )
rolled result model =
    let
        next =
            if List.isEmpty result then
                RollEmptyPool

            else
                RollOk result
    in
    ( Model.mapModal Model.randomEncounterLens
        (\ui -> { ui | roll = next })
        model
    , Cmd.none
    )



-- ── ADD TO ENCOUNTER ─────────────────────────────────────────────────────────


{-| Materialise the current roll into encounter instances and
append them to the queue. Uses the same `draftToInstance` +
`uniqueInstanceName` path as the Compendium browser's bulk-add
so a roll of 3 Goblins becomes Goblin, Goblin 2, Goblin 3 — no
collisions, no surprises.

Initiative is set to 0 for every spawn; the GM rolls per-card
once the encounter starts. This matches the established
single-add / bulk-add convention.

The modal closes after adding; a toast confirms the count.

-}
addToEncounter : Model -> ( Model, Cmd Msg )
addToEncounter model =
    case model.modal of
        Just (ModalRandomEncounter ui) ->
            case ui.roll of
                RollOk groups ->
                    let
                        instances =
                            buildInstances model.encounter.creatures groups

                        count =
                            List.length instances

                        updated =
                            { model
                                | encounter =
                                    Encounter.Roster.appendCreatures
                                        instances
                                        model.encounter
                                , modal = Nothing
                            }
                    in
                    if count == 0 then
                        ( model, Cmd.none )

                    else
                        updated
                            |> Update.Toast.push ToastSuccess
                                ("Rolled an encounter: "
                                    ++ String.fromInt count
                                    ++ " "
                                    ++ pluralize "creature" "creatures" count
                                    ++ " added"
                                )

                _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Walk every `(creature, count)` group, spawning `count`
instances with unique display names. Threaded `takenNames`
list keeps `Encounter.Roster.uniqueInstanceName` honest across
both the existing queue AND the in-progress spawn batch.
-}
buildInstances :
    List { a | name : String }
    -> List ( Creature, Int )
    -> List Encounter.Creature
buildInstances existing groups =
    let
        seedNames =
            List.map .name existing

        ( instancesRev, _ ) =
            List.foldl spawnGroup ( [], seedNames ) groups
    in
    List.reverse instancesRev


spawnGroup :
    ( Creature, Int )
    -> ( List Encounter.Creature, List String )
    -> ( List Encounter.Creature, List String )
spawnGroup ( source, count ) ( acc0, taken0 ) =
    List.range 1 count
        |> List.foldl
            (\_ ( acc, taken ) ->
                let
                    name =
                        Encounter.Roster.uniqueInstanceName source.name taken

                    inst =
                        Compendium.draftToInstance
                            { displayName = name, initiativeRoll = 0 }
                            source
                in
                ( inst :: acc, name :: taken )
            )
            ( acc0, taken0 )


pluralize : String -> String -> Int -> String
pluralize singular plural n =
    if n == 1 then
        singular

    else
        plural
