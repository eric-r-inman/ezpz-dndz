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
                , body = body ui model.encounter.treasure model.encounter.treasureSettings
                }

        _ ->
            text ""


body : TreasureUi -> Maybe Treasure.TreasureRoll -> Treasure.TreasureSettings -> List (Html Msg)
body ui maybeRoll settings =
    [ controlRow ui
    , settingsSection ui.settingsExpanded settings
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


{-| Collapsible "Tune your rolls" section: per-class knobs that
multiply dice counts and shift tier values around what the
treasure table itself produces. Default collapsed since most
rolls just use Normal — the section header summarises the
current knobs when not Normal so the GM can see at a glance
that a roll is tuned.
-}
settingsSection : Bool -> Treasure.TreasureSettings -> Html Msg
settingsSection expanded settings =
    let
        nonDefault =
            settingsDelta settings
    in
    section [ class "treasure__settings" ]
        [ button
            [ class
                ("treasure__settings-toggle"
                    ++ (if expanded then
                            " treasure__settings-toggle--open"

                        else
                            ""
                       )
                )
            , type_ "button"
            , onClick TreasureSettingsToggle
            ]
            [ span [ class "treasure__settings-caret" ]
                [ text
                    (if expanded then
                        "▾"

                     else
                        "▸"
                    )
                ]
            , span [ class "treasure__settings-label" ]
                [ text "Tune your rolls" ]
            , span [ class "treasure__settings-delta" ]
                [ text
                    (if String.isEmpty nonDefault then
                        "All Normal"

                     else
                        nonDefault
                    )
                ]
            ]
        , if expanded then
            div [ class "treasure__settings-body" ]
                [ settingsRow "Coins"
                    "coins"
                    (Just settings.coinsCount)
                    Nothing
                , settingsRow "Gems"
                    "gems"
                    (Just settings.gemsCount)
                    (Just settings.gemsValue)
                , settingsRow "Art"
                    "art"
                    (Just settings.artCount)
                    (Just settings.artValue)
                , settingsRow "Magic"
                    "magic"
                    (Just settings.magicCount)
                    (Just settings.magicValue)
                , div [ class "treasure__settings-actions" ]
                    [ button
                        [ class "treasure__settings-reset"
                        , type_ "button"
                        , onClick TreasureSettingsReset
                        , attribute "title" "Return every knob to Normal"
                        ]
                        [ text "↺ Reset to Normal" ]
                    ]
                ]

          else
            text ""
        ]


{-| Brief one-line summary of any knobs that aren't Normal.
Empty string when everything is at default; "Gems: More /
Higher · Art: Fewer" otherwise.
-}
settingsDelta : Treasure.TreasureSettings -> String
settingsDelta s =
    let
        coinsPart =
            knobPair "Coins" s.coinsCount Treasure.ValueNormal

        gemsPart =
            knobPair "Gems" s.gemsCount s.gemsValue

        artPart =
            knobPair "Art" s.artCount s.artValue

        magicPart =
            knobPair "Magic" s.magicCount s.magicValue
    in
    [ coinsPart, gemsPart, artPart, magicPart ]
        |> List.filter (not << String.isEmpty)
        |> String.join " · "


knobPair : String -> Treasure.CountAdjust -> Treasure.ValueAdjust -> String
knobPair label count value =
    let
        parts =
            [ countAdjustLabelSummary count, valueAdjustLabelSummary value ]
                |> List.filter (not << String.isEmpty)
    in
    if List.isEmpty parts then
        ""

    else
        label ++ ": " ++ String.join " / " parts


countAdjustLabelSummary : Treasure.CountAdjust -> String
countAdjustLabelSummary c =
    case c of
        Treasure.CountFewer ->
            "Fewer"

        Treasure.CountNormal ->
            ""

        Treasure.CountMore ->
            "More"


valueAdjustLabelSummary : Treasure.ValueAdjust -> String
valueAdjustLabelSummary v =
    case v of
        Treasure.ValueLower ->
            "Lower"

        Treasure.ValueNormal ->
            ""

        Treasure.ValueHigher ->
            "Higher"


settingsRow :
    String
    -> String
    -> Maybe Treasure.CountAdjust
    -> Maybe Treasure.ValueAdjust
    -> Html Msg
settingsRow label_ itemClass maybeCount maybeValue =
    div [ class "treasure__settings-row" ]
        [ span [ class "treasure__settings-row-label" ] [ text label_ ]
        , case maybeCount of
            Just countValue ->
                countSegmented itemClass countValue

            Nothing ->
                text ""
        , case maybeValue of
            Just valueValue ->
                valueSegmented itemClass valueValue

            Nothing ->
                text ""
        ]


countSegmented : String -> Treasure.CountAdjust -> Html Msg
countSegmented itemClass current =
    let
        countLabel =
            if itemClass == "coins" then
                "Amount"

            else
                "Count"
    in
    div [ class "treasure__settings-segmented" ]
        [ span [ class "treasure__settings-axis" ] [ text countLabel ]
        , segmentedButton itemClass
            current
            Treasure.CountFewer
            "Fewer"
            (TreasureSettingsCountSet itemClass "fewer")
        , segmentedButton itemClass
            current
            Treasure.CountNormal
            "Normal"
            (TreasureSettingsCountSet itemClass "normal")
        , segmentedButton itemClass
            current
            Treasure.CountMore
            "More"
            (TreasureSettingsCountSet itemClass "more")
        ]


valueSegmented : String -> Treasure.ValueAdjust -> Html Msg
valueSegmented itemClass current =
    let
        valueLabel =
            if itemClass == "magic" then
                "Rarity"

            else
                "Value"
    in
    div [ class "treasure__settings-segmented" ]
        [ span [ class "treasure__settings-axis" ] [ text valueLabel ]
        , segmentedButton itemClass
            current
            Treasure.ValueLower
            "Lower"
            (TreasureSettingsValueSet itemClass "lower")
        , segmentedButton itemClass
            current
            Treasure.ValueNormal
            "Normal"
            (TreasureSettingsValueSet itemClass "normal")
        , segmentedButton itemClass
            current
            Treasure.ValueHigher
            "Higher"
            (TreasureSettingsValueSet itemClass "higher")
        ]


{-| Tiny generic segmented-control button. Active when `current
== target`. Stays type-agnostic via Elm's structural typing —
the call sites supply tagged CountAdjust or ValueAdjust values.
-}
segmentedButton : String -> a -> a -> String -> Msg -> Html Msg
segmentedButton _ current target text_ msg =
    button
        [ class
            ("treasure__settings-segment"
                ++ (if current == target then
                        " treasure__settings-segment--active"

                    else
                        ""
                   )
            )
        , type_ "button"
        , onClick msg
        ]
        [ text text_ ]


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
            [ text (contributionSummary c) ]
        ]


contributionSummary : CreatureContribution -> String
contributionSummary c =
    let
        gemPart =
            if List.isEmpty c.gems then
                ""

            else
                " + " ++ String.join ", " (List.map gemLabel c.gems)

        lootPart =
            if List.isEmpty c.loot then
                ""

            else
                " + " ++ String.join ", " c.loot
    in
    coinSummary c.coins ++ gemPart ++ lootPart


gemLabel : GemItem -> String
gemLabel g =
    g.name ++ " (" ++ String.fromInt g.valueGp ++ " gp)"


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
        , lootSection roll.loot
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
    let
        groups =
            groupItems project items
    in
    section [ class "treasure__section" ]
        [ div [ class "treasure__section-header" ]
            [ span [ class "treasure__section-title" ] [ text title ]
            , rerollCategoryButton category
            ]
        , ul [ class "treasure__list" ]
            (List.map
                (\g ->
                    li [ class "treasure__row" ]
                        [ span [ class "treasure__row-name" ]
                            [ text g.name
                            , countSuffix g.count
                            ]
                        , span [ class "treasure__row-value" ]
                            [ text (String.fromInt g.valueGp ++ " gp") ]
                        , rowRemoveButton (removeMsg g.firstIndex)
                        ]
                )
                groups
            )
        ]


type alias ValuedGroup =
    { name : String
    , valueGp : Int
    , count : Int
    , firstIndex : Int
    }


{-| Walk an indexed list and accumulate items into groups keyed
by the projected identity (name + value). Each group records
the first occurrence's index so the × button can remove from
the underlying list and re-render shows the count decremented.
-}
groupItems : (a -> ( String, Int )) -> List a -> List ValuedGroup
groupItems project items =
    items
        |> List.indexedMap Tuple.pair
        |> List.foldl
            (\( idx, item ) acc ->
                let
                    ( name, valueGp ) =
                        project item
                in
                if List.any (\g -> g.name == name && g.valueGp == valueGp) acc then
                    List.map
                        (\g ->
                            if g.name == name && g.valueGp == valueGp then
                                { g | count = g.count + 1 }

                            else
                                g
                        )
                        acc

                else
                    acc
                        ++ [ { name = name
                             , valueGp = valueGp
                             , count = 1
                             , firstIndex = idx
                             }
                           ]
            )
            []


countSuffix : Int -> Html Msg
countSuffix count =
    if count > 1 then
        span [ class "treasure__row-count" ]
            [ text (" × " ++ String.fromInt count) ]

    else
        text ""



-- ── MAGIC ITEMS ──────────────────────────────────────────────────────────────


magicSection : List MagicItem -> Html Msg
magicSection items =
    if List.isEmpty items then
        text ""

    else
        let
            groups =
                groupMagicItems items
        in
        section [ class "treasure__section" ]
            [ div [ class "treasure__section-header" ]
                [ span [ class "treasure__section-title" ] [ text "Magic items" ]
                , rerollCategoryButton Treasure.MagicCategory
                ]
            , ul [ class "treasure__list" ] (List.map magicGroupRow groups)
            ]


type alias MagicGroup =
    { name : String
    , rarity : Rarity
    , table : Tables.MagicTable
    , count : Int
    , firstIndex : Int
    }


{-| Same pattern as `groupItems` but keyed on (name, rarity,
table) since two different "Bag of Holding" rolls from Table A
should display as one grouped row.
-}
groupMagicItems : List MagicItem -> List MagicGroup
groupMagicItems items =
    items
        |> List.indexedMap Tuple.pair
        |> List.foldl
            (\( idx, item ) acc ->
                if List.any (sameMagic item) acc then
                    List.map
                        (\g ->
                            if sameMagic item g then
                                { g | count = g.count + 1 }

                            else
                                g
                        )
                        acc

                else
                    acc
                        ++ [ { name = item.name
                             , rarity = item.rarity
                             , table = item.table
                             , count = 1
                             , firstIndex = idx
                             }
                           ]
            )
            []


sameMagic : MagicItem -> { g | name : String, rarity : Rarity, table : Tables.MagicTable } -> Bool
sameMagic item g =
    g.name == item.name && g.rarity == item.rarity && g.table == item.table


magicGroupRow : MagicGroup -> Html Msg
magicGroupRow g =
    li [ class "treasure__row" ]
        [ span [ class "treasure__row-name" ]
            [ text g.name
            , span [ class "treasure__row-source" ]
                [ text (" — Table " ++ Tables.magicTableLabel g.table) ]
            , countSuffix g.count
            ]
        , span
            [ class
                ("treasure__rarity treasure__rarity--"
                    ++ rarityModifier g.rarity
                )
            ]
            [ text (Tables.rarityLabel g.rarity) ]
        , rowRemoveButton (TreasureMagicRemove g.firstIndex)
        ]


{-| "Loot" section: free-text items the enemies were authored
with on their compendium entries. No gp values, no rarity —
just text descriptions surfaced for the GM to read out.
Duplicate strings collapse into a single row with an "× N"
suffix, matching the gems/art/magic rendering.
-}
lootSection : List String -> Html Msg
lootSection items =
    if List.isEmpty items then
        text ""

    else
        let
            groups =
                groupLootItems items
        in
        section [ class "treasure__section treasure__section--loot" ]
            [ div [ class "treasure__section-header" ]
                [ span [ class "treasure__section-title" ] [ text "Loot" ]
                ]
            , ul [ class "treasure__list" ] (List.map lootGroupRow groups)
            ]


type alias LootGroup =
    { name : String, count : Int }


groupLootItems : List String -> List LootGroup
groupLootItems items =
    items
        |> List.foldl
            (\name acc ->
                if List.any (\g -> g.name == name) acc then
                    List.map
                        (\g ->
                            if g.name == name then
                                { g | count = g.count + 1 }

                            else
                                g
                        )
                        acc

                else
                    acc ++ [ { name = name, count = 1 } ]
            )
            []


lootGroupRow : LootGroup -> Html Msg
lootGroupRow g =
    li [ class "treasure__row" ]
        [ span [ class "treasure__row-name" ]
            [ text g.name
            , countSuffix g.count
            ]
        , span [ class "treasure__rarity treasure__rarity--loot" ]
            [ text "Loot" ]
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
