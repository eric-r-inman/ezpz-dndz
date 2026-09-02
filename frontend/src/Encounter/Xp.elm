module Encounter.Xp exposing
    ( Totals, XpScope(..)
    , formatThousands, totalsFor
    )

{-| XP totals for the encounter. Pure rules code — what XP each
creature is worth and how the GM's chosen scope filters them.
No `Html`, no `Msg`.

`XpScope` lives here rather than in `Msg.elm` because it is a
domain concept (a filter over the creature queue), not a message
shape. `Msg` re-exposes it for the `XpScopeSet` Msg constructor.

@docs Totals, XpScope
@docs formatThousands, totalsFor

-}

import Compendium exposing (Db)
import Encounter exposing (Creature, Encounter)


{-| The four GM-pickable scopes for the XP readout.

  - `ScopeXpEnemiesAndNpcs` — every non-Player creature. Default.
  - `ScopeXpEnemiesOnly` — Enemy-tagged creatures only.
  - `ScopeXpNpcsOnly` — NPC-tagged creatures only.
  - `ScopeXpSelectedOnly` — whichever creatures the GM has ticked.

-}
type XpScope
    = ScopeXpEnemiesAndNpcs
    | ScopeXpEnemiesOnly
    | ScopeXpNpcsOnly
    | ScopeXpSelectedOnly


{-| Pair of XP totals across the encounter, filtered by `scope`.

  - `total` — sum of every in-scope creature's base `xp`.
  - `lairTotal` — sum of `xpInLair` if non-zero, otherwise `xp`,
    so a mixed party (some with lair XP, some without) sums
    correctly. Equal to `total` when nothing in scope has a
    lair-XP variant, which is how the view knows to leave the
    in-lair figure out.

-}
type alias Totals =
    { total : Int
    , lairTotal : Int
    }


{-| Sum the base + lair XP for every creature in the encounter
that the chosen scope picks out. Resolves XP through each
creature's `creatureId` against the compendium so the
source-of-truth value comes from the compendium entry, not from
duplicated state on the live-encounter creature.
-}
totalsFor : XpScope -> Encounter -> Db -> Totals
totalsFor scope enc db =
    enc.creatures
        |> List.filterMap (xpForCreature scope db)
        |> List.foldl
            (\( base, lair ) acc ->
                { total = acc.total + base
                , lairTotal = acc.lairTotal + lair
                }
            )
            { total = 0, lairTotal = 0 }


xpForCreature : XpScope -> Db -> Creature -> Maybe ( Int, Int )
xpForCreature scope db ec =
    ec.creatureId
        |> Maybe.andThen (\id -> Compendium.find id db)
        |> Maybe.andThen
            (\source ->
                if source.kind == Compendium.Player then
                    Nothing

                else if matchesScope scope source.kind ec then
                    let
                        lair =
                            if source.xpInLair > 0 then
                                source.xpInLair

                            else
                                source.xp
                    in
                    Just ( source.xp, lair )

                else
                    Nothing
            )


matchesScope : XpScope -> Compendium.CreatureKind -> Creature -> Bool
matchesScope scope kind ec =
    case scope of
        ScopeXpEnemiesAndNpcs ->
            kind == Compendium.Enemy || kind == Compendium.Npc

        ScopeXpEnemiesOnly ->
            kind == Compendium.Enemy

        ScopeXpNpcsOnly ->
            kind == Compendium.Npc

        ScopeXpSelectedOnly ->
            ec.selected


{-| Pretty-print an integer with thousand separators, matching
the source-side D&D Beyond convention (e.g. `15,000 XP`). Negative
values keep their sign on the left.
-}
formatThousands : Int -> String
formatThousands n =
    let
        digits =
            String.fromInt (Basics.abs n)

        head =
            modBy 3 (String.length digits)

        firstChunk =
            String.left head digits

        rest =
            String.dropLeft head digits

        chunks =
            chunk3 rest

        joined =
            if String.isEmpty firstChunk then
                String.join "," chunks

            else
                String.join "," (firstChunk :: chunks)
    in
    if n < 0 then
        "-" ++ joined

    else
        joined


chunk3 : String -> List String
chunk3 s =
    if String.isEmpty s then
        []

    else if String.length s <= 3 then
        [ s ]

    else
        String.left 3 s :: chunk3 (String.dropLeft 3 s)
