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
        , Coins
        , CreatureContribution
        , GemItem
        , Kind(..)
        , MagicItem
        )
import Encounter.Treasure.Tables as Tables exposing (Rarity)
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
import Util.Number
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
                , body = body ui model.encounter.treasure
                }

        _ ->
            text ""


body : TreasureUi -> Maybe Treasure.TreasureRoll -> List (Html Msg)
body ui maybeRoll =
    [ controlRow ui
    , case maybeRoll of
        Nothing ->
            emptyState

        Just roll ->
            resultBlock roll
    , case maybeRoll of
        Just roll ->
            contributionsSection ui.contributionsExpanded roll.contributions

        Nothing ->
            text ""
    , editTableLink
    ]


contributionsSection : Bool -> List CreatureContribution -> Html Msg
contributionsSection expanded contributions =
    if List.isEmpty contributions then
        text ""

    else
        section [ class "treasure__contributions" ]
            [ button
                [ class
                    ("treasure__contributions-toggle"
                        ++ (if expanded then
                                " treasure__contributions-toggle--open"

                            else
                                ""
                           )
                    )
                , type_ "button"
                , onClick TreasureContributionsToggle
                , attribute "aria-expanded"
                    (if expanded then
                        "true"

                     else
                        "false"
                    )
                ]
                [ span [ class "treasure__contributions-caret" ]
                    [ text
                        (if expanded then
                            "▾"

                         else
                            "▸"
                        )
                    ]
                , span [ class "treasure__contributions-label" ]
                    [ text "By creature" ]
                , span [ class "treasure__contributions-count" ]
                    [ text (String.fromInt (List.length contributions) ++ " enemies") ]
                ]
            , if expanded then
                ul [ class "treasure__contributions-list" ]
                    (List.map contributionRow contributions)

              else
                text ""
            ]


contributionRow : CreatureContribution -> Html Msg
contributionRow c =
    li [ class "treasure__contributions-row" ]
        [ span [ class "treasure__contributions-name" ]
            [ text c.creatureName
            , span [ class "treasure__contributions-bracket" ]
                [ text (" — " ++ Treasure.bracketLabel c.bracket) ]
            ]
        , span [ class "treasure__contributions-coins" ]
            [ text (coinSummary c.coins) ]
        ]


coinSummary : Coins -> String
coinSummary c =
    let
        parts =
            [ ( c.platinum, "pp" )
            , ( c.gold, "gp" )
            , ( c.electrum, "ep" )
            , ( c.silver, "sp" )
            , ( c.copper, "cp" )
            ]
                |> List.filterMap
                    (\( amount, abbrev ) ->
                        if amount > 0 then
                            Just (formatNumber amount ++ " " ++ abbrev)

                        else
                            Nothing
                    )
    in
    if List.isEmpty parts then
        "—"

    else
        String.join ", " parts


editTableLink : Html Msg
editTableLink =
    div [ class "treasure__edit-table-row" ]
        [ button
            [ class "treasure__edit-table"
            , type_ "button"
            , onClick TreasureTableOpen
            , attribute "title" "View / edit your treasure table"
            ]
            [ text "Edit treasure table…" ]
        ]



-- ── HEADER CONTROLS ──────────────────────────────────────────────────────────


controlRow : TreasureUi -> Html Msg
controlRow ui =
    div [ class "treasure__controls" ]
        [ label [ class "treasure__field" ]
            [ span [ class "treasure__field-label" ] [ text "Roll:" ]
            , select [ class "treasure__select", onInput TreasureKindSet ]
                (List.map (kindOption ui.kind) Treasure.kindOptions)
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



-- ── RESULTS ──────────────────────────────────────────────────────────────────


emptyState : Html Msg
emptyState =
    p [ class "treasure__empty" ]
        [ text "Pick a kind above and hit Roll." ]


resultBlock : Treasure.TreasureRoll -> Html Msg
resultBlock roll =
    div [ class "treasure__results" ]
        [ summaryStrip roll
        , coinsSection roll.coins
        , gemsSection roll.gems
        , artSection roll.art
        , magicSection roll.magic
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
                        (li
                            [ class ("treasure__coin treasure__coin--" ++ name) ]
                            [ span [ class "treasure__coin-text" ]
                                [ text (formatNumber amount ++ " " ++ abbrev) ]
                            , rowRemoveButton (TreasureCoinRemove name)
                            ]
                        )

                else
                    Nothing
            )
        |> emptyMessageWhenEmpty "(no coins)"


{-| Generic × button rendered at the right of every rolled
treasure row. The msg parameter routes the click to the right
per-section remove handler.
-}
rowRemoveButton : Msg -> Html Msg
rowRemoveButton msg =
    button
        [ class "treasure__row-remove"
        , type_ "button"
        , onClick msg
        , attribute "aria-label" "Remove this item"
        , attribute "title" "Remove"
        ]
        [ text "✕" ]



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
            TreasureGemRemove


artSection : List ArtItem -> Html Msg
artSection items =
    if List.isEmpty items then
        text ""

    else
        valuedSection "Art objects"
            Treasure.ArtCategory
            items
            (\a -> ( a.name, a.valueGp ))
            TreasureArtRemove


valuedSection :
    String
    -> Treasure.Category
    -> List a
    -> (a -> ( String, Int ))
    -> (Int -> Msg)
    -> Html Msg
valuedSection title category items project removeMsg =
    section [ class "treasure__section" ]
        [ div [ class "treasure__section-header" ]
            [ span [ class "treasure__section-title" ] [ text title ]
            , rerollCategoryButton category
            ]
        , ul [ class "treasure__list" ]
            (List.indexedMap
                (\idx item ->
                    let
                        ( name, valueGp ) =
                            project item
                    in
                    li [ class "treasure__row" ]
                        [ span [ class "treasure__row-name" ] [ text name ]
                        , span [ class "treasure__row-value" ]
                            [ text (String.fromInt valueGp ++ " gp") ]
                        , rowRemoveButton (removeMsg idx)
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
            , ul [ class "treasure__list" ] (List.indexedMap magicRow items)
            ]


magicRow : Int -> MagicItem -> Html Msg
magicRow idx item =
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
        , rowRemoveButton (TreasureMagicRemove idx)
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



-- ── BITS ─────────────────────────────────────────────────────────────────────


emptyMessageWhenEmpty : String -> List (Html Msg) -> List (Html Msg)
emptyMessageWhenEmpty message items =
    if List.isEmpty items then
        [ li [ class "treasure__coin treasure__coin--empty" ] [ text message ] ]

    else
        items


{-| Local alias for `Util.Number.formatThousands`. Kept around
as a single-word call site for the inline coin renderers.
-}
formatNumber : Int -> String
formatNumber =
    Util.Number.formatThousands
