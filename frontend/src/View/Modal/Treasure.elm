module View.Modal.Treasure exposing (view)

{-| Treasure-generator modal.

Layout, top to bottom:

  - Header with the Kind + Bracket selectors and the Roll
    button.
  - Coin row (always shown when a roll exists).
  - Gems list (if the roll produced any).
  - Art-objects list (if the roll produced any).
  - Magic-items list (if the roll produced any).
  - Custom rows (if the GM rolled any user-authored tables).
  - Custom-tables picker — list of the GM's user-authored
    tables with per-table Roll buttons + a "Manage tables…"
    link to the editor.

Each section has a small `↻` icon in its header that re-rolls
just that slice (coins / gems / art / magic) without touching
the others; the main Roll button at the top replaces the
whole roll with a fresh draw.

-}

import Encounter.Treasure as Treasure
    exposing
        ( ArtItem
        , Bracket(..)
        , Coins
        , GemItem
        , Kind(..)
        , MagicItem
        )
import Encounter.Treasure.Tables as Tables exposing (Rarity)
import Encounter.Treasure.UserTable as UserTable exposing (CustomRoll, UserTable)
import Html
    exposing
        ( Html
        , button
        , div
        , label
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
        , disabled
        , selected
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui.ModalChrome exposing (ModalChrome)
import Ui.Treasure exposing (TreasureUi)
import View.Modal


view : ModalChrome -> Model -> Html Msg
view chrome model =
    case model.modal of
        Just (Model.ModalTreasure ui) ->
            View.Modal.view
                { close = TreasureClose
                , noOp = NoOp
                , title = "💰 Treasure"
                , extraClass = "modal--treasure"
                , chrome = chrome
                , body = body ui model.encounter.treasure model.userTreasureTables
                }

        _ ->
            text ""


body : TreasureUi -> Maybe Treasure.TreasureRoll -> List UserTable -> List (Html Msg)
body ui maybeRoll userTables =
    [ controlRow ui
    , case maybeRoll of
        Nothing ->
            emptyState

        Just roll ->
            resultBlock roll
    , userTablesSection userTables
    ]



-- ── HEADER CONTROLS ──────────────────────────────────────────────────────────


controlRow : TreasureUi -> Html Msg
controlRow ui =
    div [ class "treasure__controls" ]
        [ label [ class "treasure__field" ]
            [ span [ class "treasure__field-label" ] [ text "Kind" ]
            , select [ class "treasure__select", onInput TreasureKindSet ]
                (List.map (kindOption ui.kind) Treasure.kindOptions)
            ]
        , label [ class "treasure__field" ]
            [ span [ class "treasure__field-label" ] [ text "CR bracket" ]
            , select [ class "treasure__select", onInput TreasureBracketSet ]
                (List.map (bracketOption ui.bracket) Treasure.bracketOptions)
            ]
        , button
            [ class "action-btn action-btn--green treasure__roll"
            , onClick TreasureRoll
            ]
            [ text "🎲 Roll" ]
        ]


kindOption : Kind -> Kind -> Html Msg
kindOption current k =
    let
        wire =
            case k of
                Individual ->
                    "individual"

                Hoard ->
                    "hoard"
    in
    option [ value wire, selected (k == current) ]
        [ text (Treasure.kindLabel k) ]


bracketOption : Bracket -> Bracket -> Html Msg
bracketOption current b =
    let
        wire =
            case b of
                B1to4 ->
                    "1to4"

                B5to10 ->
                    "5to10"

                B11to16 ->
                    "11to16"

                B17plus ->
                    "17plus"
    in
    option [ value wire, selected (b == current) ]
        [ text (Treasure.bracketLabel b) ]



-- ── RESULTS ──────────────────────────────────────────────────────────────────


emptyState : Html Msg
emptyState =
    p [ class "treasure__empty" ]
        [ text "Pick a kind + bracket above and hit Roll." ]


resultBlock : Treasure.TreasureRoll -> Html Msg
resultBlock roll =
    div [ class "treasure__results" ]
        [ summaryStrip roll
        , coinsSection roll.coins
        , gemsSection roll.gems
        , artSection roll.art
        , magicSection roll.magic
        , customSection roll.custom
        ]


summaryStrip : Treasure.TreasureRoll -> Html Msg
summaryStrip roll =
    let
        coinValue =
            Treasure.totalCoinValueGp roll.coins

        gemValue =
            Treasure.totalGemValue roll.gems

        artValue =
            Treasure.totalArtValue roll.art

        magicCount =
            List.length roll.magic

        total =
            coinValue + gemValue + artValue
    in
    div [ class "treasure__summary" ]
        [ span [ class "treasure__summary-chunk" ]
            [ text ("Coins ≈ " ++ String.fromInt coinValue ++ " gp") ]
        , span [ class "treasure__summary-chunk" ]
            [ text ("Gems ≈ " ++ String.fromInt gemValue ++ " gp") ]
        , span [ class "treasure__summary-chunk" ]
            [ text ("Art ≈ " ++ String.fromInt artValue ++ " gp") ]
        , span [ class "treasure__summary-chunk" ]
            [ text ("Magic items: " ++ String.fromInt magicCount) ]
        , span [ class "treasure__summary-total" ]
            [ text ("Total value ≈ " ++ String.fromInt total ++ " gp") ]
        ]



-- ── COINS ────────────────────────────────────────────────────────────────────


coinsSection : Coins -> Html Msg
coinsSection coins =
    section [ class "treasure__section" ]
        [ div [ class "treasure__section-header" ]
            [ span [ class "treasure__section-title" ] [ text "Coins" ]
            , rerollCategoryButton Treasure.CoinsCategory
            ]
        , ul [ class "treasure__list" ] (coinLines coins)
        ]


rerollCategoryButton : Treasure.Category -> Html Msg
rerollCategoryButton category =
    button
        [ class "treasure__reroll-category"
        , type_ "button"
        , onClick (TreasureRerollCategory category)
        , attribute "aria-label" ("Re-roll " ++ Treasure.categoryLabel category)
        ]
        [ text "↻" ]


coinLines : Coins -> List (Html Msg)
coinLines c =
    [ ( c.platinum, "pp", "platinum" )
    , ( c.gold, "gp", "gold" )
    , ( c.electrum, "ep", "electrum" )
    , ( c.silver, "sp", "silver" )
    , ( c.copper, "cp", "copper" )
    ]
        |> List.filterMap
            (\( amount, abbrev, name ) ->
                if amount > 0 then
                    Just
                        (li [ class ("treasure__coin treasure__coin--" ++ name) ]
                            [ text (formatNumber amount ++ " " ++ abbrev) ]
                        )

                else
                    Nothing
            )
        |> emptyMessageWhenEmpty "(no coins)"



-- ── GEMS / ART ───────────────────────────────────────────────────────────────


gemsSection : List GemItem -> Html Msg
gemsSection items =
    if List.isEmpty items then
        text ""

    else
        valuedSection "Gems"
            Treasure.GemsCategory
            items
            (\g -> ( g.name, g.valueGp ))


artSection : List ArtItem -> Html Msg
artSection items =
    if List.isEmpty items then
        text ""

    else
        valuedSection "Art objects"
            Treasure.ArtCategory
            items
            (\a -> ( a.name, a.valueGp ))


valuedSection :
    String
    -> Treasure.Category
    -> List a
    -> (a -> ( String, Int ))
    -> Html Msg
valuedSection title category items project =
    section [ class "treasure__section" ]
        [ div [ class "treasure__section-header" ]
            [ span [ class "treasure__section-title" ] [ text title ]
            , rerollCategoryButton category
            ]
        , ul [ class "treasure__list" ]
            (List.map
                (\item ->
                    let
                        ( name, valueGp ) =
                            project item
                    in
                    li [ class "treasure__row" ]
                        [ span [ class "treasure__row-name" ] [ text name ]
                        , span [ class "treasure__row-value" ]
                            [ text (String.fromInt valueGp ++ " gp") ]
                        ]
                )
                items
            )
        ]



-- ── MAGIC ITEMS ──────────────────────────────────────────────────────────────


magicSection : List MagicItem -> Html Msg
magicSection items =
    if List.isEmpty items then
        text ""

    else
        section [ class "treasure__section" ]
            [ div [ class "treasure__section-header" ]
                [ span [ class "treasure__section-title" ] [ text "Magic items" ]
                , rerollCategoryButton Treasure.MagicCategory
                ]
            , ul [ class "treasure__list" ] (List.map magicRow items)
            ]


magicRow : MagicItem -> Html Msg
magicRow item =
    li [ class "treasure__row" ]
        [ span [ class "treasure__row-name" ]
            [ text item.name
            , span [ class "treasure__row-source" ]
                [ text (" — Table " ++ Tables.magicTableLabel item.table) ]
            ]
        , span
            [ class
                ("treasure__rarity treasure__rarity--"
                    ++ rarityModifier item.rarity
                )
            ]
            [ text (Tables.rarityLabel item.rarity) ]
        ]


rarityModifier : Rarity -> String
rarityModifier r =
    case r of
        Tables.Common ->
            "common"

        Tables.Uncommon ->
            "uncommon"

        Tables.Rare ->
            "rare"

        Tables.VeryRare ->
            "very-rare"

        Tables.Legendary ->
            "legendary"



-- ── CUSTOM ROWS (rolled from user-authored tables) ──────────────────────────


customSection : List CustomRoll -> Html Msg
customSection rows =
    if List.isEmpty rows then
        text ""

    else
        section [ class "treasure__section treasure__section--custom" ]
            [ div [ class "treasure__section-header" ]
                [ span [ class "treasure__section-title" ] [ text "Custom" ]
                ]
            , ul [ class "treasure__list" ]
                (List.indexedMap customRow rows)
            ]


customRow : Int -> CustomRoll -> Html Msg
customRow idx row_ =
    li [ class "treasure__row" ]
        [ span [ class "treasure__row-name" ]
            [ text row_.label
            , span [ class "treasure__row-source" ]
                [ text (" — " ++ row_.sourceTableName) ]
            ]
        , customMeta row_
        , button
            [ class "treasure__custom-remove"
            , type_ "button"
            , onClick (TreasureCustomRemove idx)
            , attribute "aria-label" "Remove this custom row"
            , attribute "title" "Remove"
            ]
            [ text "✕" ]
        ]


customMeta : CustomRoll -> Html Msg
customMeta row_ =
    case ( row_.gpValue, row_.rarity ) of
        ( Just gp, _ ) ->
            span [ class "treasure__row-value" ]
                [ text (String.fromInt gp ++ " gp") ]

        ( Nothing, Just rarity ) ->
            span
                [ class
                    ("treasure__rarity treasure__rarity--"
                        ++ rarityModifier rarity
                    )
                ]
                [ text (Tables.rarityLabel rarity) ]

        ( Nothing, Nothing ) ->
            text ""



-- ── USER-AUTHORED TABLE PICKER ──────────────────────────────────────────────


userTablesSection : List UserTable -> Html Msg
userTablesSection tables =
    section [ class "treasure__user-tables" ]
        [ div [ class "treasure__user-tables-header" ]
            [ span [ class "treasure__user-tables-title" ]
                [ text "Custom tables" ]
            , button
                [ class "treasure__user-tables-manage"
                , type_ "button"
                , onClick TreasureTableOpen
                ]
                [ text "Manage tables…" ]
            ]
        , if List.isEmpty tables then
            p [ class "treasure__user-tables-empty" ]
                [ text "Author your own tables to roll on them here." ]

          else
            ul [ class "treasure__user-tables-list" ]
                (List.map userTableRow tables)
        ]


userTableRow : UserTable -> Html Msg
userTableRow table =
    let
        entries =
            List.length table.entries

        hasEntries =
            UserTable.totalWeight table > 0
    in
    li [ class "treasure__user-table-row" ]
        [ span [ class "treasure__user-table-name" ]
            [ text
                (if String.isEmpty (String.trim table.name) then
                    "(unnamed)"

                 else
                    table.name
                )
            ]
        , span [ class "treasure__user-table-count" ]
            [ text
                (String.fromInt entries
                    ++ (if entries == 1 then
                            " entry"

                        else
                            " entries"
                       )
                )
            ]
        , button
            [ class "treasure__user-table-roll"
            , type_ "button"
            , onClick (TreasureTableRoll table.id)
            , disabled (not hasEntries)
            , attribute "title"
                (if hasEntries then
                    "Roll on this table"

                 else
                    "This table has no live entries yet"
                )
            ]
            [ text "🎲 Roll" ]
        ]



-- ── BITS ─────────────────────────────────────────────────────────────────────


emptyMessageWhenEmpty : String -> List (Html Msg) -> List (Html Msg)
emptyMessageWhenEmpty message items =
    if List.isEmpty items then
        [ li [ class "treasure__coin treasure__coin--empty" ] [ text message ] ]

    else
        items


{-| Pretty-print an integer with thousands separators. Used for
the GM-facing coin counts so "4,200 gp" reads instantly instead
of "4200gp" — small detail that adds up across a long campaign.
-}
formatNumber : Int -> String
formatNumber n =
    let
        chars =
            n |> abs |> String.fromInt |> String.toList

        grouped =
            chars
                |> List.reverse
                |> List.indexedMap
                    (\i c ->
                        if i > 0 && modBy 3 i == 0 then
                            [ c, ',' ]

                        else
                            [ c ]
                    )
                |> List.concat
                |> List.reverse
                |> String.fromList

        signed =
            if n < 0 then
                "-" ++ grouped

            else
                grouped
    in
    signed
