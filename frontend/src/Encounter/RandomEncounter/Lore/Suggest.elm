module Encounter.RandomEncounter.Lore.Suggest exposing (Suggestion, suggestFor)

{-| Reverse-engineer the Random Encounter generator inputs that
make a given lore group most likely to be selected.

The generator's eligibility check in `groupFits` boils down to:

  - At least one member resolves against the compendium.
  - If the GM set a habitat, at least one resolved member's
    creature lists it.
  - If the GM set creature-types, at least one resolved
    creature's race is in the list.
  - The group's MIN total XP ≤ 1.2× budget.
  - The group's MAX total XP × 2 ≥ budget.

So "most likely to be selected" reduces to:

1.  Pick a habitat that _some_ member supports (Any also works,
    but a specific habitat focuses the bundled pool).
2.  Pick a creature-type that _some_ member supports.
3.  Set the budget squarely in the group's XP sweet spot —
    `midXp = (minXp + maxXp) / 2` lives well inside both
    gates with margin to spare.
4.  Backsolve a party + difficulty whose `partyBudget`
    matches `midXp` closely.

Lore Leaning must be on or the lore-group path doesn't fire
at all; the test panel always surfaces that.

@docs Suggestion, suggestFor

-}

import Compendium exposing (Habitat)
import Encounter.Difficulty as Difficulty
import Encounter.RandomEncounter.Lore as Lore


{-| Concrete recommendation surfaced in the editor's Test panel.

`unresolved` carries the member names that couldn't be matched
against the compendium — usually a typo or a deleted creature.
The generator silently drops these too, so the GM needs to know.

`habitats` / `creatureTypes` are unions across every resolved
member; the panel can list the first few or "Any" if both
budget gates pass without a habitat / type filter.

`minXp` / `maxXp` are the natural XP envelope of the group; the
panel renders them so the GM can sanity-check the budget hint.

-}
type alias Suggestion =
    { unresolved : List String
    , habitats : List Habitat
    , creatureTypes : List String
    , minXp : Int
    , maxXp : Int
    , midXp : Int
    , partyLevel : Int
    , partyCount : Int
    , difficulty : Difficulty.Difficulty
    , budgetAtSuggestion : Int
    }


{-| Build a `Suggestion` for `group` given the live compendium.
Returns a fully-populated record even when no members resolve —
the unresolved list carries the bad names so the panel can warn.
-}
suggestFor : List Compendium.Creature -> Lore.Group -> Suggestion
suggestFor pool group =
    let
        resolved =
            Lore.resolveMembers group pool

        unresolved =
            group.members
                |> List.filter
                    (\m -> not (List.any (\r -> r.slot.name == m.name) resolved))
                |> List.map .name

        memberCreatures =
            List.map .creature resolved

        habitatUnion =
            memberCreatures
                |> List.concatMap .habitats
                |> dedup
                |> List.sortBy Compendium.habitatLabel

        typeUnion =
            memberCreatures
                |> List.map .race
                |> List.filter (not << String.isEmpty)
                |> dedup
                |> List.sort

        minXp =
            List.foldl (\r acc -> acc + r.creature.xp * r.slot.countMin) 0 resolved

        maxXp =
            List.foldl (\r acc -> acc + r.creature.xp * r.slot.countMax) 0 resolved

        midXp =
            (minXp + maxXp) // 2

        ( partyLevel, partyCount, difficulty ) =
            recommendParty midXp

        budgetAtSuggestion =
            partyBudgetXp partyLevel partyCount difficulty
    in
    { unresolved = unresolved
    , habitats = habitatUnion
    , creatureTypes = typeUnion
    , minXp = minXp
    , maxXp = maxXp
    , midXp = midXp
    , partyLevel = partyLevel
    , partyCount = partyCount
    , difficulty = difficulty
    , budgetAtSuggestion = budgetAtSuggestion
    }


{-| Pick a (level, count, difficulty) whose `partyBudget` lands
closest to `targetXp`. Searches a standard party of 4 across
levels 1-20 at Moderate first (the natural difficulty for a
"this is the encounter this group wants" recommendation), then
falls back to Low / High if Moderate can't reach the target.

Default party size of 4 matches the printed table and almost
every group's design intent — varying party count would muddy
the recommendation.

-}
recommendParty : Int -> ( Int, Int, Difficulty.Difficulty )
recommendParty targetXp =
    let
        partyCount =
            4

        difficulties =
            [ Difficulty.ModerateDifficulty
            , Difficulty.LowDifficulty
            , Difficulty.HighDifficulty
            ]

        candidates =
            difficulties
                |> List.concatMap
                    (\d ->
                        List.range 1 20
                            |> List.map
                                (\lvl ->
                                    ( lvl, d, partyBudgetXp lvl partyCount d )
                                )
                    )

        best =
            candidates
                |> List.foldl
                    (\( lvl, d, budget ) acc ->
                        case acc of
                            Nothing ->
                                Just ( lvl, d, abs (budget - targetXp) )

                            Just ( _, _, bestDelta ) ->
                                let
                                    delta =
                                        abs (budget - targetXp)
                                in
                                if delta < bestDelta then
                                    Just ( lvl, d, delta )

                                else
                                    acc
                    )
                    Nothing
    in
    case best of
        Just ( lvl, d, _ ) ->
            ( lvl, partyCount, d )

        Nothing ->
            ( 1, partyCount, Difficulty.ModerateDifficulty )


{-| Compute the XP budget for a uniform party of `count` at
`level` for the given difficulty. Mirrors what the Random
Encounter modal does at roll time.
-}
partyBudgetXp : Int -> Int -> Difficulty.Difficulty -> Int
partyBudgetXp level count difficulty =
    let
        members =
            List.repeat count { id = 0, level = level }

        budget =
            Difficulty.partyBudget members
    in
    case difficulty of
        Difficulty.LowDifficulty ->
            budget.low

        Difficulty.HighDifficulty ->
            budget.high

        _ ->
            budget.moderate


dedup : List a -> List a
dedup =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                acc ++ [ x ]
        )
        []
