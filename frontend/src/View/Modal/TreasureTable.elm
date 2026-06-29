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

import Auth
import Encounter.Treasure as Treasure
    exposing
        ( TreasureTable
        )
import Encounter.Treasure.ScrollSpells as ScrollSpells
    exposing
        ( ScrollLevel
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
        , option
        , p
        , section
        , select
        , span
        , text
        , ul
        )
import Html.Attributes as Attr
    exposing
        ( attribute
        , class
        , placeholder
        , selected
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( CoinField(..)
        , CoinKind(..)
        , FlatCategory(..)
        , Msg(..)
        , RowKind(..)
        , SubKind(..)
        )
import Set exposing (Set)
import Ui.TreasureTable as TreasureTableUi
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalTreasureTable ui) ->
            let
                dirty =
                    TreasureTableUi.isDirty ui

                hasSavedCustom =
                    model.userTreasureTable /= Nothing

                isAuthed =
                    Auth.isAuthenticated model.auth

                titleSuffix =
                    if dirty then
                        " · unsaved changes"

                    else
                        ""
            in
            View.Modal.view
                { close = TreasureTableClose
                , noOp = NoOp
                , title = "📜 Treasure Table" ++ titleSuffix
                , extraClass = "modal--treasure-table"
                , chrome = model.modalChrome
                , body =
                    body ui.draft
                        ui.expanded
                        dirty
                        hasSavedCustom
                        ui.confirmRevert
                        isAuthed
                }

        _ ->
            text ""


body : TreasureTable -> Set String -> Bool -> Bool -> Bool -> Bool -> List (Html Msg)
body table expanded dirty hasSavedCustom confirmRevert isAuthed =
    [ blurb
    , individualGroup table expanded
    , hoardGroup table expanded
    , gemGroup table expanded
    , artGroup table expanded
    , magicGroup table expanded
    , flatGroup "Mundane gear (Adventuring Gear + Artisan's Tools)"
        "mundane"
        FlatMundane
        table.mundane
        expanded
    , flatGroup "Weapons" "weapons" FlatWeapons table.weapons expanded
    , flatGroup "Armor" "armor" FlatArmor table.armor expanded
    , scrollSpellsGroup table expanded
    , resetRow
    , saveRow dirty hasSavedCustom confirmRevert isAuthed
    ]


{-| Editor for the per-level spell-name lists the scroll
post-process draws from. One collapsible per spell level
(cantrip through 9th); each opens a name-only list editor with
the same shape as the gem / art / magic name editors above.
-}
scrollSpellsGroup : TreasureTable -> Set String -> Html Msg
scrollSpellsGroup table expanded =
    section [ class "treasure-table__group" ]
        [ p [ class "treasure-table__group-title" ]
            [ text "Spell scrolls (by level)" ]
        , div [ class "treasure-table__sections" ]
            (List.map (scrollLevelEditor table expanded)
                ScrollSpells.scrollLevelAll
            )
        ]


scrollLevelEditor : TreasureTable -> Set String -> ScrollLevel -> Html Msg
scrollLevelEditor table expanded level =
    let
        levelKey =
            ScrollSpells.scrollLevelWire level

        sectionKey =
            "scroll:" ++ levelKey

        isOpen =
            Set.member sectionKey expanded

        names =
            Treasure.scrollSpellsFor level table

        valueGp =
            ScrollSpells.scrollLevelValueGp level
    in
    collapsible
        { kind = "scroll"
        , key = levelKey
        , label =
            ScrollSpells.scrollLevelLabel level
                ++ "  ("
                ++ String.fromInt valueGp
                ++ " gp)"
        , count = String.fromInt (List.length names) ++ " entries"
        , isOpen = isOpen
        , content =
            if isOpen then
                div [ class "treasure-table__name-editor" ]
                    [ ul [ class "treasure-table__name-list" ]
                        (List.indexedMap (scrollNameRow levelKey) names)
                    , button
                        [ class "treasure-table__name-add"
                        , type_ "button"
                        , onClick (TreasureTableScrollAdd levelKey)
                        ]
                        [ text "+ Add spell" ]
                    ]

            else
                text ""
        }


scrollNameRow : String -> Int -> String -> Html Msg
scrollNameRow levelKey idx name =
    li [ class "treasure-table__name-row" ]
        [ input
            [ class "treasure-table__name-input"
            , type_ "text"
            , value name
            , placeholder "Spell name"
            , onInput (TreasureTableScrollEdit levelKey idx)
            ]
            []
        , button
            [ class "treasure-table__row-remove"
            , type_ "button"
            , onClick (TreasureTableScrollRemove levelKey idx)
            , attribute "aria-label" "Remove this spell"
            , Tooltips.attr "Remove"
            ]
            [ text "🚫" ]
        ]


flatGroup :
    String
    -> String
    -> FlatCategory
    -> List { name : String, valueGp : Int }
    -> Set String
    -> Html Msg
flatGroup title kind cat items expanded =
    let
        sectionKey =
            kind ++ ":list"

        isOpen =
            Set.member sectionKey expanded
    in
    section [ class "treasure-table__group" ]
        [ p [ class "treasure-table__group-title" ] [ text title ]
        , collapsible
            { kind = kind
            , key = "list"
            , label = "Items"
            , count = String.fromInt (List.length items) ++ " entries"
            , isOpen = isOpen
            , content =
                if isOpen then
                    flatEditor cat items

                else
                    text ""
            }
        ]


flatEditor : FlatCategory -> List { name : String, valueGp : Int } -> Html Msg
flatEditor cat items =
    div [ class "treasure-table__flat-editor" ]
        [ ul [ class "treasure-table__flat-list" ]
            (List.indexedMap (flatRow cat) items)
        , button
            [ class "treasure-table__flat-add"
            , type_ "button"
            , onClick (TreasureTableFlatAdd cat)
            ]
            [ text "+ Add item" ]
        ]


flatRow : FlatCategory -> Int -> { name : String, valueGp : Int } -> Html Msg
flatRow cat idx item =
    li [ class "treasure-table__flat-row" ]
        [ input
            [ class "treasure-table__flat-name"
            , type_ "text"
            , value item.name
            , placeholder "Item name"
            , onInput (TreasureTableFlatNameSet cat idx)
            ]
            []
        , input
            [ class "treasure-table__flat-value"
            , type_ "number"
            , Attr.min "0"
            , value (String.fromInt item.valueGp)
            , Tooltips.attr "gp value"
            , onInput (TreasureTableFlatValueSet cat idx)
            ]
            []
        , span [ class "treasure-table__flat-unit" ] [ text "gp" ]
        , button
            [ class "treasure-table__coin-remove"
            , type_ "button"
            , onClick (TreasureTableFlatRemove cat idx)
            , attribute "aria-label" "Remove this entry"
            , Tooltips.attr "Remove"
            ]
            [ text "🚫" ]
        ]


blurb : Html Msg
blurb =
    p [ class "treasure-table__blurb" ]
        [ text
            ("The Treasure roller pulls values from the below value "
                ++ "brackets, with consideration for assigned weights where "
                ++ "relevant.  Use caution when changing the CR tables, as "
                ++ "small adjustments can have a large impact."
            )
        ]



-- ── INDIVIDUAL / HOARD ROWS (field-by-field editor) ─────────────────────────


individualGroup : TreasureTable -> Set String -> Html Msg
individualGroup table expanded =
    section [ class "treasure-table__group" ]
        [ p [ class "treasure-table__group-title" ] [ text "Individual treasure (by CR bracket)" ]
        , div [ class "treasure-table__sections" ]
            (List.map
                (\bracket ->
                    let
                        rows =
                            Treasure.individualRowsFor bracket table
                    in
                    bracketSection
                        { kind = "individual"
                        , bracket = bracket
                        , expanded = expanded
                        , rows = rows
                        , weightSum = List.sum (List.map .weight rows)
                        , renderRow = individualRowEditor (Treasure.bracketWire bracket)
                        , onAdd = TreasureTableRowAdd IndividualRow (Treasure.bracketWire bracket)
                        }
                )
                Treasure.bracketOptions
            )
        ]


hoardGroup : TreasureTable -> Set String -> Html Msg
hoardGroup table expanded =
    section [ class "treasure-table__group" ]
        [ p [ class "treasure-table__group-title" ] [ text "Hoard treasure (by CR bracket)" ]
        , div [ class "treasure-table__sections" ]
            (List.map
                (\bracket ->
                    let
                        rows =
                            Treasure.hoardRowsFor bracket table
                    in
                    bracketSection
                        { kind = "hoard"
                        , bracket = bracket
                        , expanded = expanded
                        , rows = rows
                        , weightSum = List.sum (List.map .weight rows)
                        , renderRow = hoardRowEditor (Treasure.bracketWire bracket)
                        , onAdd = TreasureTableRowAdd HoardRow (Treasure.bracketWire bracket)
                        }
                )
                Treasure.bracketOptions
            )
        ]


{-| Render one bracket: collapsible chrome + the per-row editor
list + a weight-sum summary + an "add row" button. Generic over
the row type so individual and hoard collapse into one path.
-}
bracketSection :
    { kind : String
    , bracket : Treasure.Bracket
    , expanded : Set String
    , rows : List row
    , weightSum : Int
    , renderRow : Int -> row -> Html Msg
    , onAdd : Msg
    }
    -> Html Msg
bracketSection cfg =
    let
        key =
            Treasure.bracketWire cfg.bracket

        isOpen =
            Set.member (cfg.kind ++ ":" ++ key) cfg.expanded
    in
    collapsible
        { kind = cfg.kind
        , key = key
        , label = Treasure.bracketLabel cfg.bracket
        , count = String.fromInt (List.length cfg.rows) ++ " rows"
        , isOpen = isOpen
        , content =
            if isOpen then
                div [ class "treasure-table__bracket-editor" ]
                    [ weightSumBanner cfg.weightSum
                    , ul [ class "treasure-table__row-list" ]
                        (List.indexedMap
                            (\i r -> li [ class "treasure-table__data-row" ] [ cfg.renderRow i r ])
                            cfg.rows
                        )
                    , button
                        [ class "treasure-table__row-add"
                        , type_ "button"
                        , onClick cfg.onAdd
                        ]
                        [ text "+ Add row" ]
                    ]

            else
                text ""
        }


{-| Renders the running "weights sum N · target 100" banner above
the row editor. The d100 picker still works with any total — it
just renormalises proportionally — but 100 is the SRD convention
and any drift from it is usually unintentional, so we surface it
loudly enough to catch typos without blocking the GM who knows
what they're doing.
-}
weightSumBanner : Int -> Html Msg
weightSumBanner total =
    let
        isOff =
            total /= 100

        cls =
            if isOff then
                "treasure-table__weight-sum treasure-table__weight-sum--warn"

            else
                "treasure-table__weight-sum"

        message =
            if total == 0 then
                "no rows will roll"

            else if total == 100 then
                "target 100 ✓"

            else
                "target 100"
    in
    p [ class cls ]
        [ text ("Weights sum: " ++ String.fromInt total ++ " · " ++ message) ]


individualRowEditor : String -> Int -> IndividualEntry -> Html Msg
individualRowEditor bracketKey idx row =
    div [ class "treasure-table__row-editor" ]
        [ rowHeader IndividualRow bracketKey idx row.weight
        , coinGrid IndividualRow bracketKey idx (individualCoins row)
        ]


hoardRowEditor : String -> Int -> HoardEntry -> Html Msg
hoardRowEditor bracketKey idx row =
    div [ class "treasure-table__row-editor" ]
        [ rowHeader HoardRow bracketKey idx row.weight
        , coinGrid HoardRow bracketKey idx (hoardCoins row)
        , subGrid bracketKey idx row
        ]


individualCoins : IndividualEntry -> List ( CoinKind, Maybe ( Int, Int, Int ) )
individualCoins row =
    [ ( CKCopper, row.copper )
    , ( CKSilver, row.silver )
    , ( CKElectrum, row.electrum )
    , ( CKGold, row.gold )
    , ( CKPlatinum, row.platinum )
    ]


hoardCoins : HoardEntry -> List ( CoinKind, Maybe ( Int, Int, Int ) )
hoardCoins row =
    [ ( CKCopper, row.copper )
    , ( CKSilver, row.silver )
    , ( CKElectrum, row.electrum )
    , ( CKGold, row.gold )
    , ( CKPlatinum, row.platinum )
    ]


rowHeader : RowKind -> String -> Int -> Int -> Html Msg
rowHeader kind bracketKey idx weight =
    div [ class "treasure-table__row-header" ]
        [ Html.label [ class "treasure-table__field" ]
            [ span [ class "treasure-table__field-label" ] [ text "Weight" ]
            , input
                [ class (warnClass "treasure-table__field-input" (weight <= 0))
                , type_ "number"
                , Attr.min "0"
                , value (String.fromInt weight)
                , onInput (TreasureTableWeightSet kind bracketKey idx)
                ]
                []
            ]
        , span
            [ class "treasure-table__row-hint"
            , Tooltips.attr
                "Higher weight = more often.  The bracket's roll is weighted by these numbers; 0 means the row never rolls."
            ]
            [ text
                (if weight <= 0 then
                    "(never rolls)"

                 else
                    ""
                )
            ]
        , button
            [ class "treasure-table__row-remove-btn"
            , type_ "button"
            , onClick (TreasureTableRowRemove kind bracketKey idx)
            , Tooltips.attr "Remove this row"
            , attribute "aria-label" "Remove row"
            ]
            [ text "🚫 Row" ]
        ]


coinGrid :
    RowKind
    -> String
    -> Int
    -> List ( CoinKind, Maybe ( Int, Int, Int ) )
    -> Html Msg
coinGrid kind bracketKey idx coins =
    div [ class "treasure-table__coin-grid" ]
        (List.map (coinColumn kind bracketKey idx) coins)


coinColumn :
    RowKind
    -> String
    -> Int
    -> ( CoinKind, Maybe ( Int, Int, Int ) )
    -> Html Msg
coinColumn kind bracketKey idx ( coin, mFormula ) =
    div [ class "treasure-table__coin-column" ]
        [ span [ class "treasure-table__coin-label" ] [ text (coinLabel coin) ]
        , case mFormula of
            Nothing ->
                button
                    [ class "treasure-table__coin-add"
                    , type_ "button"
                    , onClick (TreasureTableCoinAdd kind bracketKey idx coin)
                    , Tooltips.attr ("Add a " ++ coinLabel coin ++ " formula to this row")
                    ]
                    [ text "+" ]

            Just ( c, f, m ) ->
                div [ class "treasure-table__coin-formula" ]
                    [ numField "Count"
                        c
                        1
                        (TreasureTableCoinSet kind bracketKey idx coin CFCount)
                    , span [ class "treasure-table__coin-d" ] [ text "d" ]
                    , numField "Faces"
                        f
                        2
                        (TreasureTableCoinSet kind bracketKey idx coin CFFaces)
                    , span [ class "treasure-table__coin-x" ] [ text "×" ]
                    , numField "Mult"
                        m
                        1
                        (TreasureTableCoinSet kind bracketKey idx coin CFMult)
                    , button
                        [ class "treasure-table__coin-remove"
                        , type_ "button"
                        , onClick (TreasureTableCoinRemove kind bracketKey idx coin)
                        , Tooltips.attr ("Clear " ++ coinLabel coin)
                        , attribute "aria-label" ("Clear " ++ coinLabel coin)
                        ]
                        [ text "🚫" ]
                    ]
        ]


numField : String -> Int -> Int -> (String -> Msg) -> Html Msg
numField title_ current minimum toMsg =
    input
        [ class "treasure-table__num-input"
        , type_ "number"
        , Attr.min (String.fromInt minimum)
        , value (String.fromInt current)
        , Tooltips.attr title_
        , onInput toMsg
        ]
        []


coinLabel : CoinKind -> String
coinLabel c =
    case c of
        CKCopper ->
            "cp"

        CKSilver ->
            "sp"

        CKElectrum ->
            "ep"

        CKGold ->
            "gp"

        CKPlatinum ->
            "pp"


subGrid : String -> Int -> HoardEntry -> Html Msg
subGrid bracketKey idx row =
    div [ class "treasure-table__sub-grid" ]
        [ subColumn bracketKey
            idx
            { kind = SKGems
            , label = "Gems"
            , spec = row.gems
            , tierKey = gemTierGp
            , tierOptions = List.map (\( k, _ ) -> ( k, k )) gemTierEntries
            }
        , subColumn bracketKey
            idx
            { kind = SKArt
            , label = "Art"
            , spec = row.art
            , tierKey = artTierGp
            , tierOptions = List.map (\( k, _ ) -> ( k, k )) artTierEntries
            }
        , subColumn bracketKey
            idx
            { kind = SKMagic
            , label = "Magic"
            , spec = row.magic
            , tierKey = magicTableLetter
            , tierOptions = List.map (\( k, _ ) -> ( k, "Table " ++ k )) magicTableEntries
            }
        ]


subColumn :
    String
    -> Int
    ->
        { kind : SubKind
        , label : String
        , spec : Maybe ( Int, Int, tier )
        , tierKey : tier -> String
        , tierOptions : List ( String, String )
        }
    -> Html Msg
subColumn bracketKey idx cfg =
    div [ class "treasure-table__sub-column" ]
        [ span [ class "treasure-table__coin-label" ] [ text cfg.label ]
        , case cfg.spec of
            Nothing ->
                button
                    [ class "treasure-table__coin-add"
                    , type_ "button"
                    , onClick (TreasureTableSubAdd bracketKey idx cfg.kind)
                    , Tooltips.attr ("Add a " ++ cfg.label ++ " sub-roll to this row")
                    ]
                    [ text "+" ]

            Just ( c, f, t ) ->
                div [ class "treasure-table__coin-formula" ]
                    [ numField (cfg.label ++ " count")
                        c
                        1
                        (TreasureTableSubCountSet bracketKey idx cfg.kind)
                    , span [ class "treasure-table__coin-d" ] [ text "d" ]
                    , numField (cfg.label ++ " faces")
                        f
                        2
                        (TreasureTableSubFacesSet bracketKey idx cfg.kind)
                    , select
                        [ class "treasure-table__sub-tier"
                        , onInput (TreasureTableSubTierSet bracketKey idx cfg.kind)
                        ]
                        (List.map
                            (\( k, label ) ->
                                option
                                    [ value k
                                    , selected (k == cfg.tierKey t)
                                    ]
                                    [ text label ]
                            )
                            cfg.tierOptions
                        )
                    , button
                        [ class "treasure-table__coin-remove"
                        , type_ "button"
                        , onClick (TreasureTableSubRemove bracketKey idx cfg.kind)
                        , Tooltips.attr ("Clear " ++ cfg.label)
                        , attribute "aria-label" ("Clear " ++ cfg.label)
                        ]
                        [ text "🚫" ]
                    ]
        ]


warnClass : String -> Bool -> String
warnClass base shouldWarn =
    if shouldWarn then
        base ++ " " ++ base ++ "--warn"

    else
        base


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
            , Tooltips.attr "Remove"
            ]
            [ text "🚫" ]
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
            , Tooltips.attr "Replace the draft with the bundled SRD default (still requires Save to commit)"
            ]
            [ text "↺ Reset to bundled defaults" ]
        ]



-- ── SAVE / CANCEL FOOTER ───────────────────────────────────────────────────


{-| Footer row with Save + Cancel, and a Revert button (right
of Save) when the user has a persisted custom table. Cancel
discards the draft; Save commits it into
`model.userTreasureTable`, which the persistence hook in
`Main.update` then writes through. Revert is the inverse of
Save — it drops the saved custom table back to the bundled
defaults — and uses an inline two-step confirmation so it can't
fire on a mis-click.

Save is grey-locked for signed-out users (custom tables live
server-side under the account); the button stays clickable in
that state so a click fires the "must sign in" toast rather
than silently doing nothing.

-}
saveRow : Bool -> Bool -> Bool -> Bool -> Html Msg
saveRow dirty hasSavedCustom confirmRevert isAuthed =
    let
        canCommit =
            dirty && isAuthed

        saveClass =
            if canCommit then
                "treasure-table__save treasure-table__save--ready"

            else if dirty && not isAuthed then
                "treasure-table__save treasure-table__save--locked"

            else
                "treasure-table__save"

        saveTitle =
            if not dirty then
                "No changes to save"

            else if not isAuthed then
                "You must be signed in to save edits to the treasure tables."

            else
                "Save your changes and close"
    in
    div [ class "treasure-table__save-row" ]
        [ span [ class "treasure-table__save-status" ]
            [ text
                (if dirty then
                    "Unsaved changes"

                 else
                    "No changes"
                )
            ]
        , button
            [ class "treasure-table__save-cancel"
            , type_ "button"
            , onClick TreasureTableClose
            , Tooltips.attr "Close without saving"
            ]
            [ text "Cancel" ]
        , button
            [ class saveClass
            , type_ "button"
            , onClick TreasureTableSave
            , Attr.disabled (not dirty)
            , Tooltips.attr saveTitle
            ]
            [ text "Save" ]
        , revertControl hasSavedCustom confirmRevert
        ]


{-| Surfaces only when there's actually a saved custom table to
revert. First state is a single "Revert" button; clicking it
swaps the slot for an inline "Revert to bundled? [Cancel][Confirm]" prompt, matching the lore-delete two-step pattern.
-}
revertControl : Bool -> Bool -> Html Msg
revertControl hasSavedCustom confirmRevert =
    if not hasSavedCustom then
        text ""

    else if confirmRevert then
        span [ class "treasure-table__revert-confirm" ]
            [ span [ class "treasure-table__revert-warn" ]
                [ text "Revert to bundled?" ]
            , button
                [ class "treasure-table__revert-cancel"
                , type_ "button"
                , onClick TreasureTableRevertCancel
                , Tooltips.attr "Keep your custom table"
                ]
                [ text "Cancel" ]
            , button
                [ class "treasure-table__revert-go"
                , type_ "button"
                , onClick TreasureTableRevertConfirm
                , Tooltips.attr "Drop the saved custom table and use bundled defaults"
                ]
                [ text "Confirm Revert" ]
            ]

    else
        button
            [ class "treasure-table__revert"
            , type_ "button"
            , onClick TreasureTableRevertRequest
            , Tooltips.attr "Discard your saved custom table and use bundled defaults"
            ]
            [ text "↺ Revert" ]
