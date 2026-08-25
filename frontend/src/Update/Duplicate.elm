module Update.Duplicate exposing
    ( close, exact, fresh, minionHalf, minionOne, open
    , pudding
    )

{-| Update branches for the creature-card Duplicate picker modal.

The card's ⧉ button now opens this modal instead of duplicating
inline; the modal exposes four options:

  - **Exact** — clone the creature with all current state (HP,
    conditions, notes, etc.). Delegates to the existing
    `Encounter.Roster.duplicateCreature`.
  - **Fresh** — re-instance from the compendium with unmodified
    state. Looks up the source creature's `creatureId` in
    `model.compendium.db` and runs `Compendium.draftToInstance`,
    preserving the source's initiative roll.
  - **Minion (½ max hp)** — Fresh, then halve max HP and match
    current to the new max.
  - **Minion (1 hp)** — Fresh, then set max HP to 1 and match
    current to it.

Falls back to Exact for any creature without a `creatureId` or
whose compendium source has been deleted (defensive — the view
disables the affected buttons but the dispatch path is robust
to a stale modal).

@docs close, exact, fresh, minionHalf, minionOne, open

-}

import Compendium
import Encounter exposing (Creature)
import Encounter.Roster
import Model exposing (Model, Surface(..))
import Msg exposing (Msg)
import Set
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Duplicate as DuplicateUi


open : String -> Model -> ( Model, Cmd Msg )
open creatureName model =
    ( { model | surface = Just (SurfaceDuplicate (DuplicateUi.fresh creatureName)) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | surface = Nothing }, Cmd.none )


{-| Exact mode: full clone via the existing Roster helper.
Picks up current HP / conditions / save notices / cover / etc.
-}
exact : Model -> ( Model, Cmd Msg )
exact model =
    case sourceName model of
        Just name ->
            ( { model
                | surface = Nothing
                , encounter = Encounter.Roster.duplicateCreature name model.encounter
              }
            , Cmd.none
            )

        Nothing ->
            ( { model | surface = Nothing }, Cmd.none )


{-| Fresh mode: build from compendium with unmodified state.
-}
fresh : Model -> ( Model, Cmd Msg )
fresh =
    freshLike InstanceName identity


{-| Minion variant: halve the source's max HP (rounded down) and
match current HP to the new max. Fresh state otherwise.
-}
minionHalf : Model -> ( Model, Cmd Msg )
minionHalf =
    freshLike MinionName
        (\c ->
            let
                halved =
                    max 1 (c.maxHp // 2)
            in
            { c | maxHp = halved, originalMaxHp = halved, currentHp = halved }
        )


{-| Minion variant: max HP locked to 1. Fresh state otherwise.
-}
minionOne : Model -> ( Model, Cmd Msg )
minionOne =
    freshLike MinionName
        (\c -> { c | maxHp = 1, originalMaxHp = 1, currentHp = 1 })


{-| Pudding split: replace the source with two new instances,
each carrying half the source's current and max HP (rounded
down). Conditions, save notices, and posture statuses are
cleared on both halves; initiative is preserved so they act in
the same slot of the queue, immediately after where the source
sat.

If the source has no creatureId we still split — Pudding doesn't
need a compendium reference, just the source's HP values.

-}
pudding : Model -> ( Model, Cmd Msg )
pudding model =
    case sourceName model of
        Nothing ->
            ( { model | surface = Nothing }, Cmd.none )

        Just name ->
            case findCreature name model.encounter.creatures of
                Nothing ->
                    ( { model | surface = Nothing }, Cmd.none )

                Just src ->
                    let
                        ( copyA, copyB ) =
                            puddingPair src model.encounter

                        afterFirst =
                            Encounter.Roster.insertCopyAfter name copyA model.encounter

                        afterSecond =
                            Encounter.Roster.insertCopyAfter copyA.name copyB afterFirst

                        finalEnc =
                            Encounter.Roster.removeCreature name afterSecond
                    in
                    ( { model | surface = Nothing, encounter = finalEnc }
                    , Cmd.none
                    )


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
freshLike : NameMode -> (Creature -> Creature) -> Model -> ( Model, Cmd Msg )
freshLike nameMode tweak model =
    case sourceName model of
        Nothing ->
            ( { model | surface = Nothing }, Cmd.none )

        Just name ->
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
                            ( { model
                                | surface = Nothing
                                , encounter =
                                    Encounter.Roster.insertCopyAfter name copy model.encounter
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            -- Compendium source is gone (deleted /
                            -- never had an id); fall back to Exact.
                            exactInline name model

                ( Just _, _ ) ->
                    exactInline name model

                _ ->
                    ( { model | surface = Nothing }, Cmd.none )


exactInline : String -> Model -> ( Model, Cmd Msg )
exactInline name model =
    ( { model
        | surface = Nothing
        , encounter = Encounter.Roster.duplicateCreature name model.encounter
      }
    , Cmd.none
    )


sourceName : Model -> Maybe String
sourceName model =
    case model.surface of
        Just (SurfaceDuplicate ui) ->
            Just ui.creatureName

        _ ->
            Nothing


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
