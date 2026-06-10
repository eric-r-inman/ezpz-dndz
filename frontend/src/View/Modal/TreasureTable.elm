module View.Modal.TreasureTable exposing (view)

{-| Editor for the singular per-user Treasure Table.

Five top-level groups, each broken down by bracket / tier /
table letter:

  - Individual treasure rows (4 brackets, read-only)
  - Hoard rows (4 brackets, read-only)
  - Gem name lists (6 tiers, editable)
  - Art-object name lists (5 tiers, editable)
  - Magic-item name lists (9 SRD tables, editable)

Each subsection is a collapsible accordion. The bundled SRD
default is the starting point for every new user; a single
"Reset to bundled" button reverts to that default.

-}

import Encounter.Treasure as Treasure
    exposing
        ( TreasureTable
        )
import Encounter.Treasure.Tables as Tables
    exposing
        ( ArtTier(..)
        , GemTier(..)
        , HoardEntry
        , IndividualEntry
        , MagicTable(..)
        )
import Html
    exposing
        ( Html
        , button
        , div
        , input
        , li
        , p
        , section
        , span
        , text
        , ul
        )
import Html.Attributes as Attr
    exposing
        ( attribute
        , class
        , placeholder
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Set exposing (Set)
import View.Modal


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalTreasureTable ui) ->
            let
                table =
                    Maybe.withDefault Treasure.bundledTable model.userTreasureTable
            in
            View.Modal.view
                { close = TreasureTableClose
                , noOp = NoOp
                , title = "📜 Treasure Table"
                , extraClass = "modal--treasure-table"
                , chrome = model.modalChrome
                , body = body table ui.expanded
                }

        _ ->
            text ""


body : TreasureTable -> Set String -> List (Html Msg)
body table expanded =
    [ blurb
    , individualGroup table expanded
    , hoardGroup table expanded
    , gemGroup table expanded
    , artGroup table expanded
    , magicGroup table expanded
    , resetRow
    ]


blurb : Html Msg
blurb =
    p [ class "treasure-table__blurb" ]
        [ text
            ("This is your treasure table — bundled with the full SRD 5.1 "
                ++ "defaults out of the box.  Editing the gem / art / magic name "
                ++ "lists below changes what rolls land on; coin formulas and "
                ++ "weighted-row probabilities are visible but read-only for now."
            )
        ]



-- ── INDIVIDUAL / HOARD ROWS (read-only display) ─────────────────────────────


individualGroup : TreasureTable -> Set String -> Html Msg
individualGroup table expanded =
    bracketGroup
        { title = "Individual treasure (by CR bracket)"
        , kind = "individual"
        , expanded = expanded
        , brackets = Treasure.bracketOptions
        , bracketLabel = Treasure.bracketLabel
        , bracketKey = Treasure.bracketWire
        , rowsFor = \b -> Treasure.individualRowsFor b table
        , renderRow = individualRowView
        }


hoardGroup : TreasureTable -> Set String -> Html Msg
hoardGroup table expanded =
    bracketGroup
        { title = "Hoard treasure (by CR bracket)"
        , kind = "hoard"
        , expanded = expanded
        , brackets = Treasure.bracketOptions
        , bracketLabel = Treasure.bracketLabel
        , bracketKey = Treasure.bracketWire
        , rowsFor = \b -> Treasure.hoardRowsFor b table
        , renderRow = hoardRowView
        }


bracketGroup :
    { title : String
    , kind : String
    , expanded : Set String
    , brackets : List Treasure.Bracket
    , bracketLabel : Treasure.Bracket -> String
    , bracketKey : Treasure.Bracket -> String
    , rowsFor : Treasure.Bracket -> List row
    , renderRow : row -> Html Msg
    }
    -> Html Msg
bracketGroup cfg =
    section [ class "treasure-table__group" ]
        [ p [ class "treasure-table__group-title" ] [ text cfg.title ]
        , div [ class "treasure-table__sections" ]
            (List.map
                (\bracket ->
                    let
                        key =
                            cfg.bracketKey bracket

                        isOpen =
                            Set.member (cfg.kind ++ ":" ++ key) cfg.expanded

                        rows =
                            cfg.rowsFor bracket
                    in
                    collapsible
                        { kind = cfg.kind
                        , key = key
                        , label = cfg.bracketLabel bracket
                        , count = String.fromInt (List.length rows) ++ " rows"
                        , isOpen = isOpen
                        , content =
                            if isOpen then
                                ul [ class "treasure-table__row-list" ]
                                    (List.map (\r -> li [ class "treasure-table__data-row" ] [ cfg.renderRow r ]) rows)

                            else
                                text ""
                        }
                )
                cfg.brackets
            )
        ]


individualRowView : IndividualEntry -> Html Msg
individualRowView row =
    span [ class "treasure-table__row-summary" ]
        [ text ("weight " ++ String.fromInt row.weight ++ " · ")
        , text (formulaSummary "cp" row.copper "")
        , text (formulaSummary "sp" row.silver " · ")
        , text (formulaSummary "ep" row.electrum " · ")
        , text (formulaSummary "gp" row.gold " · ")
        , text (formulaSummary "pp" row.platinum " · ")
        ]


hoardRowView : HoardEntry -> Html Msg
hoardRowView row =
    span [ class "treasure-table__row-summary" ]
        [ text ("weight " ++ String.fromInt row.weight ++ " · ")
        , text (formulaSummary "cp" row.copper "")
        , text (formulaSummary "sp" row.silver " · ")
        , text (formulaSummary "ep" row.electrum " · ")
        , text (formulaSummary "gp" row.gold " · ")
        , text (formulaSummary "pp" row.platinum " · ")
        , text (subRollSummary "gems" row.gems gemTierGp " · ")
        , text (subRollSummary "art" row.art artTierGp " · ")
        , text (subRollSummary "magic" row.magic magicTableLetter " · ")
        ]


formulaSummary : String -> Maybe ( Int, Int, Int ) -> String -> String
formulaSummary label mFormula sep =
    case mFormula of
        Nothing ->
            ""

        Just ( count, faces, mult ) ->
            let
                multSuffix =
                    if mult == 1 then
                        ""

                    else
                        " × " ++ String.fromInt mult
            in
            sep ++ String.fromInt count ++ "d" ++ String.fromInt faces ++ multSuffix ++ " " ++ label


subRollSummary : String -> Maybe ( Int, Int, tier ) -> (tier -> String) -> String -> String
subRollSummary label mSpec tierLabel sep =
    case mSpec of
        Nothing ->
            ""

        Just ( count, faces, tier ) ->
            sep ++ String.fromInt count ++ "d" ++ String.fromInt faces ++ " " ++ tierLabel tier ++ " " ++ label


gemTierGp : GemTier -> String
gemTierGp t =
    case t of
        Gem10gp ->
            "10gp"

        Gem50gp ->
            "50gp"

        Gem100gp ->
            "100gp"

        Gem500gp ->
            "500gp"

        Gem1000gp ->
            "1000gp"

        Gem5000gp ->
            "5000gp"


artTierGp : ArtTier -> String
artTierGp t =
    case t of
        Art25gp ->
            "25gp"

        Art250gp ->
            "250gp"

        Art750gp ->
            "750gp"

        Art2500gp ->
            "2500gp"

        Art7500gp ->
            "7500gp"


magicTableLetter : MagicTable -> String
magicTableLetter =
    Tables.magicTableLabel



-- ── GEM / ART / MAGIC NAME LISTS (editable) ─────────────────────────────────


gemGroup : TreasureTable -> Set String -> Html Msg
gemGroup table expanded =
    nameListGroup
        { title = "Gem names by value tier"
        , kind = "gem"
        , expanded = expanded
        , entries =
            List.map
                (\( key, label ) ->
                    ( key, label, Treasure.gemNamesFor (gemTierFromKey key) table )
                )
                gemTierEntries
        , addMsg = TreasureTableGemAdd
        , editMsg = TreasureTableGemEdit
        , removeMsg = TreasureTableGemRemoveItem
        }


artGroup : TreasureTable -> Set String -> Html Msg
artGroup table expanded =
    nameListGroup
        { title = "Art objects by value tier"
        , kind = "art"
        , expanded = expanded
        , entries =
            List.map
                (\( key, label ) ->
                    ( key, label, Treasure.artNamesFor (artTierFromKey key) table )
                )
                artTierEntries
        , addMsg = TreasureTableArtAdd
        , editMsg = TreasureTableArtEdit
        , removeMsg = TreasureTableArtRemoveItem
        }


magicGroup : TreasureTable -> Set String -> Html Msg
magicGroup table expanded =
    nameListGroup
        { title = "Magic items by SRD table"
        , kind = "magic"
        , expanded = expanded
        , entries =
            List.map
                (\( key, label ) ->
                    ( key, label, Treasure.magicNamesFor (magicTableFromKey key) table )
                )
                magicTableEntries
        , addMsg = TreasureTableMagicAdd
        , editMsg = TreasureTableMagicEdit
        , removeMsg = TreasureTableMagicRemoveItem
        }


nameListGroup :
    { title : String
    , kind : String
    , expanded : Set String
    , entries : List ( String, String, List String )
    , addMsg : String -> Msg
    , editMsg : String -> Int -> String -> Msg
    , removeMsg : String -> Int -> Msg
    }
    -> Html Msg
nameListGroup cfg =
    section [ class "treasure-table__group" ]
        [ p [ class "treasure-table__group-title" ] [ text cfg.title ]
        , div [ class "treasure-table__sections" ]
            (List.map
                (\( key, label, names ) ->
                    let
                        isOpen =
                            Set.member (cfg.kind ++ ":" ++ key) cfg.expanded
                    in
                    collapsible
                        { kind = cfg.kind
                        , key = key
                        , label = label
                        , count = String.fromInt (List.length names) ++ " entries"
                        , isOpen = isOpen
                        , content =
                            if isOpen then
                                nameListEditor key names cfg

                            else
                                text ""
                        }
                )
                cfg.entries
            )
        ]


nameListEditor :
    String
    -> List String
    ->
        { c
            | kind : String
            , addMsg : String -> Msg
            , editMsg : String -> Int -> String -> Msg
            , removeMsg : String -> Int -> Msg
        }
    -> Html Msg
nameListEditor key names cfg =
    div [ class "treasure-table__name-editor" ]
        [ ul [ class "treasure-table__name-list" ]
            (List.indexedMap (nameRow key cfg) names)
        , button
            [ class "treasure-table__name-add"
            , onClick (cfg.addMsg key)
            ]
            [ text "+ Add entry" ]
        ]


nameRow :
    String
    ->
        { c
            | editMsg : String -> Int -> String -> Msg
            , removeMsg : String -> Int -> Msg
        }
    -> Int
    -> String
    -> Html Msg
nameRow key cfg idx name =
    li [ class "treasure-table__name-row" ]
        [ input
            [ class "treasure-table__name-input"
            , type_ "text"
            , value name
            , placeholder "New entry"
            , onInput (cfg.editMsg key idx)
            ]
            []
        , button
            [ class "treasure-table__row-remove"
            , type_ "button"
            , onClick (cfg.removeMsg key idx)
            , attribute "aria-label" "Remove this entry"
            , attribute "title" "Remove"
            ]
            [ text "✕" ]
        ]



-- ── TIER ENTRY TABLES ──────────────────────────────────────────────────────


gemTierEntries : List ( String, String )
gemTierEntries =
    [ ( "10gp", "10gp gems" )
    , ( "50gp", "50gp gems" )
    , ( "100gp", "100gp gems" )
    , ( "500gp", "500gp gems" )
    , ( "1000gp", "1000gp gems" )
    , ( "5000gp", "5000gp gems" )
    ]


artTierEntries : List ( String, String )
artTierEntries =
    [ ( "25gp", "25gp art objects" )
    , ( "250gp", "250gp art objects" )
    , ( "750gp", "750gp art objects" )
    , ( "2500gp", "2500gp art objects" )
    , ( "7500gp", "7500gp art objects" )
    ]


magicTableEntries : List ( String, String )
magicTableEntries =
    [ ( "A", "Table A — Common consumables" )
    , ( "B", "Table B — Uncommon consumables" )
    , ( "C", "Table C — Rare consumables" )
    , ( "D", "Table D — Very Rare consumables" )
    , ( "E", "Table E — Legendary consumables" )
    , ( "F", "Table F — Uncommon permanents" )
    , ( "G", "Table G — Rare permanents" )
    , ( "H", "Table H — Very Rare permanents" )
    , ( "I", "Table I — Legendary permanents" )
    ]


gemTierFromKey : String -> GemTier
gemTierFromKey key =
    case key of
        "10gp" ->
            Gem10gp

        "50gp" ->
            Gem50gp

        "100gp" ->
            Gem100gp

        "500gp" ->
            Gem500gp

        "1000gp" ->
            Gem1000gp

        _ ->
            Gem5000gp


artTierFromKey : String -> ArtTier
artTierFromKey key =
    case key of
        "25gp" ->
            Art25gp

        "250gp" ->
            Art250gp

        "750gp" ->
            Art750gp

        "2500gp" ->
            Art2500gp

        _ ->
            Art7500gp


magicTableFromKey : String -> MagicTable
magicTableFromKey key =
    case key of
        "A" ->
            TableA

        "B" ->
            TableB

        "C" ->
            TableC

        "D" ->
            TableD

        "E" ->
            TableE

        "F" ->
            TableF

        "G" ->
            TableG

        "H" ->
            TableH

        _ ->
            TableI



-- ── COLLAPSIBLE PRIMITIVE ──────────────────────────────────────────────────


collapsible :
    { kind : String
    , key : String
    , label : String
    , count : String
    , isOpen : Bool
    , content : Html Msg
    }
    -> Html Msg
collapsible cfg =
    div [ class "treasure-table__section" ]
        [ button
            [ class
                ("treasure-table__section-toggle"
                    ++ (if cfg.isOpen then
                            " treasure-table__section-toggle--open"

                        else
                            ""
                       )
                )
            , type_ "button"
            , onClick (TreasureTableToggleSection cfg.kind cfg.key)
            , attribute "aria-expanded"
                (if cfg.isOpen then
                    "true"

                 else
                    "false"
                )
            ]
            [ span [ class "treasure-table__section-caret" ]
                [ text
                    (if cfg.isOpen then
                        "▾"

                     else
                        "▸"
                    )
                ]
            , span [ class "treasure-table__section-label" ] [ text cfg.label ]
            , span [ class "treasure-table__section-count" ] [ text cfg.count ]
            ]
        , cfg.content
        ]



-- ── RESET ──────────────────────────────────────────────────────────────────


resetRow : Html Msg
resetRow =
    div [ class "treasure-table__reset-row" ]
        [ button
            [ class "treasure-table__reset"
            , type_ "button"
            , onClick TreasureTableResetToBundled
            , attribute "title" "Replace your table with the bundled SRD default"
            ]
            [ text "↺ Reset to bundled defaults" ]
        ]
