module Update.Compendium.AddGroup exposing (addGroup, materialise)

{-| Group → encounter handoff. Mirrors `Update.Compendium.Add`
for the single-creature path, but threads each entry's count and
minion-type overrides into the spawn pipeline, and honours the
group's initiative mode (each-rolls / shared-rolled / shared-manual).

The flow:

1.  `addGroup` looks up the group by id, builds the per-instance
    spawn skeletons (display names disambiguated against the
    current encounter + within the group), and dispatches the
    right initiative-roll Cmd for the chosen mode.
2.  The Cmd's callback assembles a `CompendiumGroupAddMaterialise`
    Msg carrying the fully-resolved spawns + dice rolls to push.
3.  `materialise` writes the encounter, pushes the dice rolls,
    and toasts.

Manual initiative skips the roll entirely and runs the
materialisation inline; shared-rolled fires one `Dice.batchRollCmd`
spec; each-rolls fires N specs.

@docs addGroup, materialise

-}

import Compendium
import Compendium.Group as Group
    exposing
        ( Group
        , GroupSpawn
        , InitiativeMode(..)
        , MinionType(..)
        )
import Dice
import Dict
import Effects
import Encounter exposing (Creature)
import Encounter.Roster
import Model exposing (Model)
import Msg exposing (Msg(..))
import Random
import Task
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Toast exposing (ToastKind(..))
import Update.Initiative
import Update.Toast



-- ── ENTRY POINT ──────────────────────────────────────────────────────────────


addGroup : String -> Model -> ( Model, Cmd Msg )
addGroup groupId model =
    case ( Dict.get groupId model.compendium.groups, model.compendium.db ) of
        ( Just group, CompendiumDbLoaded db ) ->
            let
                skeletons =
                    expandSkeletons group db model
            in
            if List.isEmpty skeletons then
                ( model, Cmd.none )

            else
                ( model, dispatchInitiative group skeletons )

        _ ->
            ( model, Cmd.none )


{-| Materialise the resolved spawns: encode them as Encounter
creatures, append to the encounter, push the dice pool to
history, toast. The Cmd path that produced these spawns has
already disambiguated names, applied minion HP overrides, and
stamped each instance with its initiative — no rules logic
runs here, just plumbing.
-}
materialise :
    List GroupSpawn
    -> List Dice.Roll
    -> Model
    -> ( Model, Cmd Msg )
materialise spawns rolls model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            let
                instances =
                    List.filterMap
                        (\spawn -> spawnToCreature spawn db)
                        spawns

                ( m1, broadcastCmds ) =
                    List.foldl
                        (\r ( m, cs ) ->
                            let
                                ( pushed, broadcastCmd ) =
                                    Effects.pushDiceRoll r m
                            in
                            ( pushed, broadcastCmd :: cs )
                        )
                        ( model, [] )
                        rolls

                count =
                    List.length instances

                toastMessage =
                    "Added group: "
                        ++ String.fromInt count
                        ++ " creature"
                        ++ (if count == 1 then
                                ""

                            else
                                "s"
                           )
            in
            { m1 | encounter = Encounter.Roster.appendCreatures instances m1.encounter }
                |> Update.Toast.pushWith ToastSuccess
                    toastMessage
                    (Cmd.batch
                        (List.map Effects.persistDiceRoll rolls
                            ++ broadcastCmds
                        )
                    )

        _ ->
            ( model, Cmd.none )



-- ── INTERNAL: NAME + SPAWN ASSEMBLY ──────────────────────────────────────────


{-| Per-instance pre-roll state: everything except `initiative`.
A second pass fills `initiative` once rolls (or manual values)
are known.
-}
type alias Skeleton =
    { creatureId : String
    , displayName : String
    , maxHpOverride : Maybe Int
    }


{-| Walk the group's entries. For each entry, spawn `count`
skeletons with unique display names disambiguated against the
encounter's existing roster. Entries pointing at creatures the
compendium can't resolve are silently skipped — a half-loaded
group is better than no group.
-}
expandSkeletons : Group -> Compendium.Db -> Model -> List Skeleton
expandSkeletons group db model =
    let
        existingNames =
            List.map .name model.encounter.creatures

        ( skeletonsRev, _ ) =
            List.foldl
                (\entry ( acc, takenNames ) ->
                    case Compendium.find entry.creatureId db of
                        Just source ->
                            entryToSkeletons entry source takenNames acc

                        Nothing ->
                            ( acc, takenNames )
                )
                ( [], existingNames )
                group.entries
    in
    List.reverse skeletonsRev


entryToSkeletons :
    Group.GroupEntry
    -> Compendium.Creature
    -> List String
    -> List Skeleton
    -> ( List Skeleton, List String )
entryToSkeletons entry source initialTaken initialAcc =
    let
        maxHpOverride =
            case entry.minionType of
                MinionNone ->
                    Nothing

                _ ->
                    Just (Group.maxHpFor entry.minionType source.maxHp)

        instances =
            List.range 1 entry.count
    in
    List.foldl
        (\_ ( acc, takenNames ) ->
            let
                displayName =
                    Encounter.Roster.uniqueInstanceName source.name takenNames

                skeleton =
                    { creatureId = entry.creatureId
                    , displayName = displayName
                    , maxHpOverride = maxHpOverride
                    }
            in
            ( skeleton :: acc, displayName :: takenNames )
        )
        ( initialAcc, initialTaken )
        instances


{-| Pick the right initiative Cmd for the group's mode.

`shared_manual` short-circuits into a `Task.succeed` that fires
`CompendiumGroupAddMaterialise` directly — no dice roll, just
copy the manual value into every spawn's initiative.

`shared_rolled` rolls once with `Dice.batchRollCmd` (single
spec) and the callback fans the result out across every spawn.

`each_rolls` rolls N times — one spec per skeleton — and the
callback zips rolls to skeletons in order.

-}
dispatchInitiative : Group -> List Skeleton -> Cmd Msg
dispatchInitiative group skeletons =
    case group.initiativeMode of
        InitiativeSharedManual value ->
            -- Task.succeed → Task.perform pattern lets us emit a
            -- Msg without a real effect, keeping the materialise
            -- path uniform across all three initiative modes.
            Task.perform
                (\_ ->
                    CompendiumGroupAddMaterialise
                        (List.map (skeletonWithInitiative value) skeletons)
                        []
                )
                (Task.succeed ())

        InitiativeSharedRolled ->
            -- Use the FIRST skeleton's source name as the dice-
            -- history label so the GM can attribute the roll;
            -- everyone else just shares the resulting total.
            case skeletons of
                first :: _ ->
                    Dice.batchRollCmd
                        (\rolls ->
                            case rolls of
                                [ ( _, sharedRoll ) ] ->
                                    let
                                        spawns =
                                            List.map
                                                (skeletonWithInitiative sharedRoll.total)
                                                skeletons
                                    in
                                    CompendiumGroupAddMaterialise spawns [ sharedRoll ]

                                _ ->
                                    -- batchRollCmd with a 1-spec
                                    -- list always yields a 1-elem
                                    -- result; this branch is
                                    -- unreachable.
                                    NoOp
                        )
                        [ ( first.displayName
                          , Update.Initiative.source first.displayName
                          , Dice.generator
                                (Update.Initiative.initiativeExpression 0)
                          )
                        ]

                [] ->
                    Cmd.none

        InitiativeEachRolls ->
            -- One roll per skeleton.  Carry the per-skeleton
            -- initiative bonus by looking up the source creature
            -- on each spec; if the source can't be resolved we
            -- already filtered the skeleton out in expandSkeletons.
            Dice.batchRollCmd
                (\rolls ->
                    let
                        rolledOnly =
                            List.map Tuple.second rolls

                        spawns =
                            List.map2
                                (\skel ( _, roll ) ->
                                    skeletonWithInitiative roll.total skel
                                )
                                skeletons
                                rolls
                    in
                    CompendiumGroupAddMaterialise spawns rolledOnly
                )
                (List.map skeletonSpec skeletons)


skeletonSpec : Skeleton -> ( String, Dice.Source, Random.Generator Dice.Roll )
skeletonSpec skel =
    ( skel.displayName
    , Update.Initiative.source skel.displayName
      -- We don't know the source creature's initiative bonus at
      -- this point without another lookup.  Use 0 as a safe
      -- default — the per-creature add path used `source.initiativeBonus`,
      -- but for groups the GM is usually rolling them as a
      -- coarse cluster so a flat d20 is acceptable for v1.  A
      -- follow-up can plumb the bonus through if it matters.
    , Dice.generator (Update.Initiative.initiativeExpression 0)
    )


skeletonWithInitiative : Int -> Skeleton -> GroupSpawn
skeletonWithInitiative initiative skel =
    { creatureId = skel.creatureId
    , displayName = skel.displayName
    , initiative = initiative
    , maxHpOverride = skel.maxHpOverride
    }


spawnToCreature :
    GroupSpawn
    -> Compendium.Db
    -> Maybe Creature
spawnToCreature spawn db =
    case Compendium.find spawn.creatureId db of
        Just source ->
            let
                instance =
                    Compendium.draftToInstance
                        { displayName = spawn.displayName
                        , initiativeRoll = spawn.initiative
                        }
                        source
            in
            Just (applyMaxHpOverride spawn.maxHpOverride instance)

        Nothing ->
            Nothing


applyMaxHpOverride : Maybe Int -> Creature -> Creature
applyMaxHpOverride override instance =
    case override of
        Nothing ->
            instance

        Just newMax ->
            { instance | maxHp = newMax, currentHp = newMax }
