module Ui.TreasureTable exposing
    ( Section(..)
    , TreasureTableUi
    , fresh
    , toggleSection
    )

{-| UI substate for the (singular) Treasure Table editor.

There's exactly one treasure table per user — bundled by
default, mutated through this editor. The modal renders a
collection of collapsible sections (individual rows by
bracket, hoard rows by bracket, gem name lists by tier, art
lists by tier, magic lists per SRD table letter), so this
substate just tracks which sections are currently expanded
and any in-progress "add new entry" draft for a section.

The treasure-table data itself lives on
`model.userTreasureTable : Maybe TreasureTable`; the editor
mutates that directly, so the modal substate stays small.

-}

import Set exposing (Set)


{-| Discriminator for a collapsible section in the editor.
Each section knows its own key string ("ind:1to4",
"gem:50gp", "magic:A", etc.); rendering iterates the table
data and matches up the expanded set.
-}
type Section
    = IndividualSection String
    | HoardSection String
    | GemSection String
    | ArtSection String
    | MagicSection String


type alias TreasureTableUi =
    { expanded : Set String
    }


fresh : TreasureTableUi
fresh =
    { expanded = Set.empty }


sectionKey : Section -> String
sectionKey s =
    case s of
        IndividualSection k ->
            "ind:" ++ k

        HoardSection k ->
            "hoard:" ++ k

        GemSection k ->
            "gem:" ++ k

        ArtSection k ->
            "art:" ++ k

        MagicSection k ->
            "magic:" ++ k


toggleSection : Section -> TreasureTableUi -> TreasureTableUi
toggleSection section ui =
    let
        key =
            sectionKey section
    in
    if Set.member key ui.expanded then
        { ui | expanded = Set.remove key ui.expanded }

    else
        { ui | expanded = Set.insert key ui.expanded }
