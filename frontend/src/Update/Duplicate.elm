module Update.Duplicate exposing (apply, applySelected, close, modeSet, open)

{-| Update branches for the Duplicate editor.

Five flavors, applied to the active creature or the selection:

  - **Exact** — clone with all current state (HP, conditions,
    notes, etc.). Delegates to `Encounter.Roster.duplicateCreature`.
  - **Fresh** — re-instance from the compendium with unmodified
    state, preserving the source's initiative roll.
  - **Minion (½ max hp)** — Fresh, then halve max HP and match
    current to the new max.
  - **Minion (1 hp)** — Fresh, then set max HP to 1 and match
    current to it.
  - **Pudding** — split into two half-HP copies and remove the
    original.

Fresh-family flavors fall back to Exact for any creature without
a `creatureId` or whose compendium source has been deleted.

-}

import Compendium
import Encounter exposing (Creature)
import Encounter.Roster
import Model exposing (Model, Surface(..))
import Msg exposing (DuplicateMode(..), Msg)
import Set
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Duplicate as DuplicateUi exposing (DuplicateUi)


{-| The editor's own drawer entry, in the `Maybe Surface`
shape the pattern matches below were written against.
-}
drawerSurface : Model -> Maybe Surface
drawerSurface model =
    Model.drawerGet Model.duplicateLens model
        |> Maybe.map SurfaceDuplicate


{-| Opening is a toggle: clicking the column's Duplicate button
while the editor is already open for the same target closes it.
-}
open : String -> Model -> ( Model, Cmd Msg )
open target model =
    ( case drawerSurface model of
        Just (SurfaceDuplicate ui) ->
            if ui.target == target then
                Model.closeDrawer Model.duplicateLens model

            else
                Model.openDrawer Model.duplicateLens (DuplicateUi.fresh target) model

        _ ->
            Model.openDrawer Model.duplicateLens (DuplicateUi.fresh target) model
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( Model.closeDrawer Model.duplicateLens model, Cmd.none )


withUi : (DuplicateUi -> DuplicateUi) -> Model -> Model
withUi =
    Model.mapSurface Model.duplicateLens


modeSet : DuplicateMode -> Model -> ( Model, Cmd Msg )
modeSet mode model =
    ( withUi (\u -> { u | mode = mode }) model, Cmd.none )


{-| Apply the chosen flavor to the editor's target.
-}
apply : Model -> ( Model, Cmd Msg )
apply model =
    case drawerSurface model of
        Just (SurfaceDuplicate ui) ->
            applyTo [ ui.target ] model

        _ ->
            ( model, Cmd.none )


{-| Apply the chosen flavor to every selected creature.
-}
applySelected : Model -> ( Model, Cmd Msg )
applySelected model =
    applyTo
        (model.encounter.creatures
            |> List.filter .selected
            |> List.map .name
        )
        model


{-| Apply the chosen flavor to every named target, log one entry
naming the copies that appeared, and leave the editor open for
the next application.
-}
applyTo : List String -> Model -> ( Model, Cmd Msg )
applyTo targets model =
    case drawerSurface model of
        Just (SurfaceDuplicate ui) ->
            let
                before =
                    Set.fromList (List.map .name model.encounter.creatures)

                afterModel =
                    List.foldl (applyModeTo ui.mode) model targets

                created =
                    afterModel.encounter.creatures
                        |> List.map .name
                        |> List.filter (\n -> not (Set.member n before))

                entry =
                    { modeLabel = modeLabel ui.mode
                    , sources = targets
                    , created = created
                    }
            in
            ( if List.isEmpty created then
                afterModel

              else
                { afterModel
                    | duplicateLog =
                        entry
                            :: List.take
                                (DuplicateUi.maxDuplicateLogEntries - 1)
                                afterModel.duplicateLog
                }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


modeLabel : DuplicateMode -> String
modeLabel mode =
    case mode of
        DupExact ->
            "Exact"

        DupFresh ->
            "Fresh"

        DupMinionHalf ->
            "Minion (½)"

        DupMinionOne ->
            "Minion (1 hp)"

        DupPudding ->
            "Pudding"


applyModeTo : DuplicateMode -> String -> Model -> Model
applyModeTo mode name model =
    case mode of
        DupExact ->
            exactFor name model

        DupFresh ->
            freshLikeFor InstanceName identity name model

        DupMinionHalf ->
            freshLikeFor MinionName
                (\c ->
                    let
                        halved =
                            max 1 (c.maxHp // 2)
                    in
                    { c | maxHp = halved, originalMaxHp = halved, currentHp = halved }
                )
                name
                model

        DupMinionOne ->
            freshLikeFor MinionName
                (\c -> { c | maxHp = 1, originalMaxHp = 1, currentHp = 1 })
                name
                model

        DupPudding ->
            puddingFor name model


{-| Exact mode: full clone via the existing Roster helper.
-}
exactFor : String -> Model -> Model
exactFor name model =
    { model | encounter = Encounter.Roster.duplicateCreature name model.encounter }


{-| Pudding split: replace the source with two new instances,
each carrying half the source's current and max HP (rounded
down). Conditions, save notices, and posture statuses are
cleared on both halves; initiative is preserved so they act in
the same slot of the queue.
-}
puddingFor : String -> Model -> Model
puddingFor name model =
    case findCreature name model.encounter.creatures of
        Nothing ->
            model

        Just src ->
            let
                ( copyA, copyB ) =
                    puddingPair src model.encounter

                afterFirst =
                    Encounter.Roster.insertCopyAfter name copyA model.encounter

                afterSecond =
                    Encounter.Roster.insertCopyAfter copyA.name copyB afterFirst
            in
            { model | encounter = Encounter.Roster.removeCreature name afterSecond }


{-| Build the two pudding halves from the source. Each gets
unique-name'd against the existing queue (the second's name is
threaded against an existing-list that already includes the
first), HP halved, and every condition / save notice / posture
flag reset to a clean slate.

Naming follows the minion convention (`<base> Minion N`) so
pudding splits and minion duplicates share a single visual
series in the queue.

-}
puddingPair : Creature -> Encounter.Encounter -> ( Creature, Creature )
puddingPair src enc =
    let
        existingNames =
            List.map .name enc.creatures

        nameA =
            Encounter.Roster.uniqueMinionName src.name existingNames

        nameB =
            Encounter.Roster.uniqueMinionName src.name (nameA :: existingNames)

        half =
            puddingHalf src
    in
    ( { half | name = nameA }
    , { half | name = nameB }
    )


{-| One pudding half, sans final name. Source's HP halved
(rounded down via integer divide), conditions / notices /
posture / death-save / legendary-pip state all cleared. Note
and memo are preserved — they're identity, not status.
-}
puddingHalf : Creature -> Creature
puddingHalf src =
    { src
        | currentHp = src.currentHp // 2
        , maxHp = src.maxHp // 2
        , originalMaxHp = src.maxHp // 2
        , tempHp = 0
        , conditions = []
        , saveNotices = []
        , concentrating = False
        , hiding = False
        , dodging = False
        , flying = False
        , flyHeight = 0
        , bloodied = False
        , deathSaves = Encounter.emptyDeathSaves
        , acceptingDeathSaves = False
        , reactionUsed = False
        , rechargeAbilities = []
        , readied = False
        , inactive = False
        , timer = Nothing
        , selected = False
        , legendaryActionsUsed = Set.empty
        , legendaryResistanceUsed = Set.empty
        , specialReactionsUsed = Set.empty
    }



-- ── INTERNAL ─────────────────────────────────────────────────────────────


{-| Naming strategy for a freshLike copy. `InstanceName` keeps
the bare-instance series (`Skeleton`, `Skeleton 2`, …) and is
used by the plain Fresh path. `MinionName` switches to the
`<base> Minion N` series shared by both minion variants and the
pudding split.
-}
type NameMode
    = InstanceName
    | MinionName


{-| Shared engine for Fresh / Minion variants: look up the source
creature in the queue + the compendium, build a fresh instance
preserving the source's initiative, apply `tweak`, and insert
after the source. Falls back to Exact when any lookup fails.
-}
freshLikeFor : NameMode -> (Creature -> Creature) -> String -> Model -> Model
freshLikeFor nameMode tweak name model =
    case ( findCreature name model.encounter.creatures, compendiumDb model ) of
        ( Just src, Just db ) ->
            case Maybe.andThen (\id -> Compendium.find id db) src.creatureId of
                Just source ->
                    let
                        existingNames =
                            List.map .name model.encounter.creatures

                        newName =
                            case nameMode of
                                InstanceName ->
                                    Encounter.Roster.uniqueInstanceName
                                        (Encounter.Roster.instanceBaseName src.name)
                                        existingNames

                                MinionName ->
                                    Encounter.Roster.uniqueMinionName
                                        src.name
                                        existingNames

                        copy =
                            Compendium.draftToInstance
                                { displayName = newName
                                , initiativeRoll = src.initiative
                                }
                                source
                                |> tweak
                    in
                    { model
                        | encounter =
                            Encounter.Roster.insertCopyAfter name copy model.encounter
                    }

                Nothing ->
                    -- Compendium source is gone (deleted / never
                    -- had an id); fall back to Exact.
                    exactFor name model

        ( Just _, _ ) ->
            exactFor name model

        _ ->
            model


findCreature : String -> List Creature -> Maybe Creature
findCreature name =
    List.filter (\c -> c.name == name) >> List.head


compendiumDb : Model -> Maybe Compendium.Db
compendiumDb model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            Just db

        _ ->
            Nothing
