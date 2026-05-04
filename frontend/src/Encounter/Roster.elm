module Encounter.Roster exposing
    ( moveUp, moveDown
    , sortByInitiative
    , removeCreature, duplicateCreature
    , appendCreatures, uniqueInstanceName
    )

{-| Queue-mutation helpers for the encounter manager.

Pulled out of `Encounter.elm` so the rules-engine root file
holds types + the begin/end-of-turn surface and this submodule
holds operations that change the shape of the queue itself
(reorder, add, remove, duplicate).

Each helper takes an `Encounter` and returns one — same shape as
the lifecycle hooks, so an `update` branch can pipe queue
mutations through these and lifecycle ticks through
`Encounter.Lifecycle` interchangeably.

@docs moveUp, moveDown
@docs sortByInitiative
@docs removeCreature, duplicateCreature
@docs appendCreatures, uniqueInstanceName

-}

import Encounter exposing (Creature, Encounter)


{-| Swap a creature with its predecessor in the queue. No-op
when the named creature is already at the top, or isn't in the
queue at all.

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


{-| Swap a creature with its successor in the queue. No-op when
the named creature is already at the bottom, or isn't in the
queue. Same caveat as `moveUp`: pure position move, no
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

5e ties are normally broken by Dexterity score; we use the
recorded `initiativeBonus` as a stand-in (it's effectively the
modifier the roll added). If both are equal we fall back to
creature name for a stable, alphabetic tiebreaker.

`activeName` is preserved across the sort, so a re-sort
mid-combat doesn't reset whose turn it is.

-}
sortByInitiative : Encounter -> Encounter
sortByInitiative enc =
    let
        sortKey c =
            ( negate c.initiative, negate c.initiativeBonus, c.name )
    in
    { enc | creatures = List.sortBy sortKey enc.creatures }


{-| Remove the named creature from the queue.

If the named creature was the active one, advance the marker to
their successor (the next creature in queue order, or the first
if they were last). When the queue empties as a result,
`activeName` becomes the empty string.

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
after the source in the queue order. The copy is a literal clone
except for: a `(copy)` / `(copy 2)` / `(copy 3)` suffix on the
name, `selected = False`, and fresh encounter-wide unique ids on
its conditions / save notices.

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


{-| Compute the unique display name for a fresh instance of
`base`. First instance keeps the bare name, second is
`base ++ " 2"`, etc.

Distinct from `uniqueCopyName`, which uses `(copy)` suffixes for
the right-rail duplicate button.

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



-- INTERNAL HELPERS (private duplicates of the Encounter.elm copies
-- to keep this submodule import-cycle-free).


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


allConditionIds : Encounter -> List Int
allConditionIds enc =
    List.concatMap (\c -> List.map .id c.conditions) enc.creatures


allSaveNoticeIds : Encounter -> List Int
allSaveNoticeIds enc =
    List.concatMap (\c -> List.map .id c.saveNotices) enc.creatures
