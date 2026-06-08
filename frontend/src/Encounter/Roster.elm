module Encounter.Roster exposing
    ( moveUp, moveDown
    , sortByInitiative
    , removeCreature, duplicateCreature, insertCopyAfter
    , appendCreatures, uniqueInstanceName, uniqueMinionName, instanceBaseName
    , appendPlaceholder, renameCreature, replaceCreature, replaceWithPlaceholder
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
@docs removeCreature, duplicateCreature, insertCopyAfter
@docs appendCreatures, uniqueInstanceName, uniqueMinionName, instanceBaseName
@docs appendPlaceholder, renameCreature, replaceCreature, replaceWithPlaceholder

-}

import Encounter exposing (Cover(..), Creature, Encounter)
import Set


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
except for: an incremented `" 2"` / `" 3"` / `" 4"` suffix on the
name, `selected = False`, and fresh encounter-wide unique ids on
its conditions / save notices.

The base for numbering is derived by stripping any trailing
`" <integer>"` from the source's display name, so duplicating
`"Skeleton"` and `"Skeleton 2"` both produce the next free slot
in the `Skeleton, Skeleton 2, Skeleton 3, …` series. This matches
the compendium-add naming via `uniqueInstanceName`.

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
                    uniqueInstanceName (instanceBaseName src.name) existingNames

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


{-| Insert a fully-built `Creature` immediately after the named
source in the queue. No-op when the source isn't present.

The caller is responsible for picking a unique display name
(use [`uniqueInstanceName`](#uniqueInstanceName) +
[`instanceBaseName`](#instanceBaseName)) and for setting any
encounter-unique ids on the copy's conditions / save notices.
This is the building block used by the Duplicate modal's
Fresh / Minion variants where the copy's state diverges from
the source enough that [`duplicateCreature`](#duplicateCreature)
isn't appropriate.

-}
insertCopyAfter : String -> Creature -> Encounter -> Encounter
insertCopyAfter anchorName copy enc =
    { enc | creatures = insertAfter anchorName copy enc.creatures }


{-| Strip a trailing `" <integer>"` from a creature's display name
to get the base used for numbering further duplicates. `"Skeleton"`
and `"Skeleton 2"` both yield `"Skeleton"`. Names whose final
whitespace-separated word isn't a parseable integer pass through
unchanged (so `"Goblin Boss"` stays `"Goblin Boss"`).
-}
instanceBaseName : String -> String
instanceBaseName name =
    case List.reverse (String.words name) of
        last :: rest ->
            case String.toInt last of
                Just _ ->
                    String.join " " (List.reverse rest)

                Nothing ->
                    name

        [] ->
            name


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
`base ++ " 2"`, etc. Used both by the compendium-add path and by
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


{-| Compute a unique `"<base> Minion <n>"` name for a
minion-style or pudding-split duplicate. Always numbers from 1
(unlike [`uniqueInstanceName`](#uniqueInstanceName), where the
first instance is the bare base), so the modal's first minion is
visibly distinct from the original.

Strips a trailing `" N"` and a trailing `" Minion"` from the
source name so repeated minion-of-minion calls stay in a flat
`<base> Minion N` series instead of nesting into
`<base> Minion 2 Minion 1`. `"Skeleton"`, `"Skeleton 2"`,
`"Skeleton Minion"`, and `"Skeleton Minion 3"` all collapse to
the same base of `"Skeleton"`.

-}
uniqueMinionName : String -> List String -> String
uniqueMinionName sourceName existingNames =
    let
        base =
            sourceName
                |> instanceBaseName
                |> stripTrailingMinion

        candidate i =
            base ++ " Minion " ++ String.fromInt i

        loop i =
            if List.member (candidate i) existingNames then
                loop (i + 1)

            else
                candidate i
    in
    loop 1


stripTrailingMinion : String -> String
stripTrailingMinion name =
    case List.reverse (String.words name) of
        "Minion" :: rest ->
            String.join " " (List.reverse rest)

        _ ->
            name


{-| Append a batch of creatures to the queue, then re-sort by
initiative. Used by the Compendium → queue handoff after the
batch initiative rolls land. `activeName` is preserved so adding
creatures mid-combat doesn't reset whose turn it is.
-}
appendCreatures : List Creature -> Encounter -> Encounter
appendCreatures newcomers enc =
    { enc | creatures = enc.creatures ++ newcomers }
        |> sortByInitiative


{-| Append a stub combatant ("Placeholder 1", "Placeholder 2", …)
to the bottom of the queue. Does NOT sort by initiative — the
GM uses this as a quick anonymous marker (often for an NPC the
party hasn't met yet, or an off-camera combatant) and expects it
to land where they clicked, not jump to a different slot.

Defaults: initiative 0, HP 1/1, AC 10, speed 30, no conditions,
no death saves, not active, not bloodied. The numeric suffix
finds the smallest unused integer so re-adding after a removal
fills the gap.

-}
appendPlaceholder : Encounter -> Encounter
appendPlaceholder enc =
    let
        existingNames =
            List.map .name enc.creatures

        name =
            nextPlaceholderName existingNames
    in
    { enc | creatures = enc.creatures ++ [ freshPlaceholder name ] }


nextPlaceholderName : List String -> String
nextPlaceholderName existingNames =
    let
        candidate n =
            "Placeholder " ++ String.fromInt n

        loop n =
            if List.member (candidate n) existingNames then
                loop (n + 1)

            else
                candidate n
    in
    loop 1


{-| Swap a creature's display name in place. Preserves queue
position, initiative, status, conditions — every per-card piece
of state. Also updates `activeName` when the renamed creature
was the one currently taking a turn so the marker doesn't drift
to nobody.

Collisions are resolved via [`uniqueInstanceName`](#uniqueInstanceName)
against the rest of the queue, so renaming "Placeholder 1" to
"Goblin" when there's already a "Goblin" yields "Goblin 2"
rather than two cards sharing a key.

No-op when the source name isn't in the queue, or when the new
name is empty after trimming.

-}
renameCreature : String -> String -> Encounter -> Encounter
renameCreature oldName rawNewName enc =
    let
        trimmed =
            String.trim rawNewName
    in
    if String.isEmpty trimmed || not (List.any (\c -> c.name == oldName) enc.creatures) then
        enc

    else
        let
            otherNames =
                enc.creatures
                    |> List.filter (\c -> c.name /= oldName)
                    |> List.map .name

            resolvedName =
                if trimmed == oldName then
                    oldName

                else
                    uniqueInstanceName (instanceBaseName trimmed) otherNames

            renamed =
                List.map
                    (\c ->
                        if c.name == oldName then
                            { c | name = resolvedName }

                        else
                            c
                    )
                    enc.creatures

            newActive =
                if enc.activeName == oldName then
                    resolvedName

                else
                    enc.activeName
        in
        { enc | creatures = renamed, activeName = newActive }


{-| Swap one creature in the queue for another, in place. The
old creature's initiative VALUE (its rolled position in the
queue) is preserved on the replacement; everything else — kind,
ability scores, HP, AC, conditions, status flags — comes from
the new instance. Queue position and `activeName` are
preserved; the replacement's display name is uniquified against
the rest of the queue so it doesn't collide with another card.

Caller is responsible for building the `newCreature` via the
usual draftToInstance / placeholder construction path. This
helper just plants it.

No-op when `oldName` isn't in the queue.

-}
replaceCreature : String -> Creature -> Encounter -> Encounter
replaceCreature oldName newCreature enc =
    case findByName oldName enc.creatures of
        Nothing ->
            enc

        Just old ->
            let
                otherNames =
                    enc.creatures
                        |> List.filter (\c -> c.name /= oldName)
                        |> List.map .name

                resolvedName =
                    uniqueInstanceName
                        (instanceBaseName newCreature.name)
                        otherNames

                planted =
                    { newCreature
                        | name = resolvedName
                        , initiative = old.initiative
                    }

                swapped =
                    List.map
                        (\c ->
                            if c.name == oldName then
                                planted

                            else
                                c
                        )
                        enc.creatures

                newActive =
                    if enc.activeName == oldName then
                        resolvedName

                    else
                        enc.activeName
            in
            { enc | creatures = swapped, activeName = newActive }


{-| Swap the named creature for a fresh `Placeholder N` stub,
preserving the old creature's initiative position. Used by the
Quick Add modal's "Placeholder" entry when the modal was opened
in replace mode.

No-op when `oldName` isn't in the queue.

-}
replaceWithPlaceholder : String -> Encounter -> Encounter
replaceWithPlaceholder oldName enc =
    let
        otherNames =
            enc.creatures
                |> List.filter (\c -> c.name /= oldName)
                |> List.map .name

        placeholderName =
            nextPlaceholderName otherNames

        stub =
            freshPlaceholder placeholderName
    in
    replaceCreature oldName stub enc


freshPlaceholder : String -> Creature
freshPlaceholder name =
    { name = name
    , kind = ""
    , initiative = 0
    , initiativeBonus = 0
    , currentHp = 1
    , maxHp = 1
    , tempHp = 0
    , armorClass = 10
    , speed = 30
    , conditions = []
    , saveNotices = []
    , selected = False
    , cover = NoCover
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
    , note = ""
    , memo = ""
    , timer = Nothing
    , creatureId = Nothing
    , legendaryActionsCount = 0
    , legendaryActionsLairBonus = 0
    , legendaryActionsUsed = Set.empty
    , legendaryResistanceCount = 0
    , legendaryResistanceLairBonus = 0
    , legendaryResistanceUsed = Set.empty
    , isPlaceholder = True
    , creatureKind = "npc"
    , race = ""
    , alignment = ""
    }



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
