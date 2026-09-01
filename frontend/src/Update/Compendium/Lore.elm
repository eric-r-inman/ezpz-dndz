module Update.Compendium.Lore exposing
    ( sectionToggle, expandToggle, select, delete, add
    , addMaterialise
    )

{-| Handlers for the Lore-groups section in the Compendium
page's browser list.

The Lore section is a peer of the user-Groups section: it has
its own disclosure, its own per-row expand state, and its own
selection axis. Selection drives the right-pane action bar
(Add / Edit / Delete) in `View.Page.Compendium`.

`add` materializes the selected lore group into the encounter
by rolling a count in `[countMin, countMax]` for each member
slot and instantiating those creatures via the standard
`Compendium.AddGroup`-style spawn path.

@docs sectionToggle, expandToggle, select, delete, add

-}

import Compendium
import Encounter
import Encounter.RandomEncounter.Lore as Lore
import Encounter.Roster
import Model exposing (Model)
import Msg exposing (Msg(..))
import Random
import Set
import Ui.Compendium as CompendiumUi
import Ui.Toast exposing (ToastKind(..))
import Update.Compendium.Browser exposing (withCompendium)
import Update.Toast


sectionToggle : Model -> ( Model, Cmd Msg )
sectionToggle model =
    ( withCompendium
        (\ui -> { ui | loreGroupsExpanded = not ui.loreGroupsExpanded })
        model
    , Cmd.none
    )


expandToggle : String -> Model -> ( Model, Cmd Msg )
expandToggle id model =
    ( withCompendium
        (\ui ->
            { ui
                | expandedLoreIds =
                    if Set.member id ui.expandedLoreIds then
                        Set.remove id ui.expandedLoreIds

                    else
                        Set.insert id ui.expandedLoreIds
            }
        )
        model
    , Cmd.none
    )


{-| Select a lore group — clears the creature and regular-group
selections so the right pane reads as the lore detail.
-}
select : String -> Model -> ( Model, Cmd Msg )
select id model =
    ( withCompendium
        (\ui ->
            { ui
                | selectedLoreId = Just id
                , selectedId = Nothing
                , selectedGroupId = Nothing
            }
        )
        model
    , Cmd.none
    )


{-| Delete a user-authored lore group. Bundled lore groups have
their Delete affordance disabled in the view, so we don't expect
this to fire for a bundled id — but guard just in case so we
don't accidentally try to remove a built-in.
-}
delete : String -> Model -> ( Model, Cmd Msg )
delete id model =
    let
        deleting =
            List.any (\g -> g.id == id && g.source == Lore.UserCurated) model.userLoreGroups
    in
    if deleting then
        ( { model
            | userLoreGroups =
                List.filter (\g -> g.id /= id) model.userLoreGroups
            , compendium =
                let
                    c =
                        model.compendium
                in
                { c
                    | selectedLoreId =
                        if c.selectedLoreId == Just id then
                            Nothing

                        else
                            c.selectedLoreId
                }
          }
        , Cmd.none
        )

    else
        ( model, Cmd.none )


{-| Roll counts for each member of the lore group and add the
resulting creatures to the encounter. Mirrors the bundled lore
materialiser the random-encounter generator uses, but with an
unbounded XP budget and max-count cap since the GM clicked
"Add" deliberately (not as part of an encounter target).
-}
add : String -> Model -> ( Model, Cmd Msg )
add id model =
    case findGroup id model of
        Just group ->
            let
                pool =
                    case model.compendium.db of
                        CompendiumUi.CompendiumDbLoaded db ->
                            Compendium.toList db

                        _ ->
                            []

                generator =
                    -- Unbounded budget + count so nothing gets
                    -- scaled down — the GM is explicitly opting
                    -- into "drop this whole group as-rolled".
                    Lore.materialize 1000000000 1000 group pool
            in
            ( model
            , Random.generate (CompendiumLoreAddMaterialise group.name) generator
            )

        Nothing ->
            ( model, Cmd.none )


{-| Continuation after the count-rolls land. Walks the
materialised `(creature, count)` pairs and appends each instance
to the encounter queue with a unique display name. Mirrors the
random-encounter `buildInstances` pipeline; we don't have an
initiative dispatch step here because lore groups don't carry
per-group initiative modes — each card rolls its own when the
GM advances the queue.
-}
addMaterialise : String -> List ( Compendium.Creature, Int ) -> Model -> ( Model, Cmd Msg )
addMaterialise groupName pairs model =
    let
        instances =
            buildInstances model.encounter.creatures pairs

        count =
            List.length instances
    in
    if count == 0 then
        Update.Toast.push ToastError
            ("Couldn't materialise \""
                ++ groupName
                ++ "\" — none of its members resolved against the compendium."
            )
            model

    else
        { model
            | encounter =
                Encounter.Roster.appendCreatures instances model.encounter
        }
            |> Update.Toast.push ToastSuccess
                ("Added "
                    ++ groupName
                    ++ ": "
                    ++ String.fromInt count
                    ++ " "
                    ++ pluralize "creature" "creatures" count
                )


findGroup : String -> Model -> Maybe Lore.Group
findGroup id model =
    (model.userLoreGroups ++ Lore.bundled)
        |> List.filter (\g -> g.id == id)
        |> List.head


buildInstances :
    List { a | name : String }
    -> List ( Compendium.Creature, Int )
    -> List Encounter.Creature
buildInstances existing pairs =
    let
        seedNames =
            List.map .name existing

        ( instancesRev, _ ) =
            List.foldl spawnPair ( [], seedNames ) pairs
    in
    List.reverse instancesRev


spawnPair :
    ( Compendium.Creature, Int )
    -> ( List Encounter.Creature, List String )
    -> ( List Encounter.Creature, List String )
spawnPair ( source, count ) ( acc0, taken0 ) =
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
