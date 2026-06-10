module View.Modal.Treasure exposing (view)

{-| Treasure-generator modal.

Layout, top to bottom:

  - Header with the Kind + Bracket selectors and the Roll
    button.
  - Coin row (always shown when a roll exists).
  - Gems list (if the roll produced any).
  - Art-objects list (if the roll produced any).
  - Magic-items list (if the roll produced any).
  - Footer with the Re-roll button + a "X of N distributed"
    summary.

Each item row has a checkbox that marks the row "distributed"
(i.e., handed to a player). Distributed rows render in a muted
style so the GM can see what's left at a glance.

When the GM hits Re-roll on a list that's got distributed items,
the modal shows a confirm banner before discarding the existing
roll.

-}

import Encounter exposing (TreasureState)
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
import Html
    exposing
        ( Html
        , button
        , div
        , input
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
        , checked
        , class
        , disabled
        , id
        , selected
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Set
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
                , body = body ui model.encounter.treasure
                }

        _ ->
            text ""


body : TreasureUi -> Maybe TreasureState -> List (Html Msg)
body ui maybeState =
    [ controlRow ui
    , confirmBanner ui maybeState
    , case maybeState of
        Nothing ->
            emptyState

        Just state ->
            resultBlock state
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



-- ── CONFIRM BANNER ───────────────────────────────────────────────────────────


confirmBanner : TreasureUi -> Maybe TreasureState -> Html Msg
confirmBanner ui maybeState =
    case ( ui.confirmingRereroll, maybeState ) of
        ( True, Just _ ) ->
            div [ class "treasure__confirm" ]
                [ span [ class "treasure__confirm-msg" ]
                    [ text "Re-roll will discard the current loot, including the distributed marks. Continue?" ]
                , button
                    [ class "action-btn action-btn--blue"
                    , onClick TreasureRerollCancel
                    ]
                    [ text "Cancel" ]
                , button
                    [ class "action-btn action-btn--red"
                    , onClick TreasureRerollConfirm
                    ]
                    [ text "Re-roll anyway" ]
                ]

        _ ->
            text ""



-- ── RESULTS ──────────────────────────────────────────────────────────────────


emptyState : Html Msg
emptyState =
    p [ class "treasure__empty" ]
        [ text "Pick a kind + bracket above and hit Roll." ]


resultBlock : TreasureState -> Html Msg
resultBlock state =
    let
        roll =
            state.roll

        d =
            state.distributed
    in
    div [ class "treasure__results" ]
        [ summaryStrip roll
        , coinsSection roll.coins d
        , gemsSection roll.gems d
        , artSection roll.art d
        , magicSection roll.magic d
        , footerRow state
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


coinsSection : Coins -> Set.Set String -> Html Msg
coinsSection coins distributed =
    let
        slug =
            "coins"

        isDistributed =
            Set.member slug distributed
    in
    section
        [ class
            ("treasure__section "
                ++ (if isDistributed then
                        "treasure__section--distributed"

                    else
                        ""
                   )
            )
        ]
        [ div [ class "treasure__section-header" ]
            [ span [ class "treasure__section-title" ] [ text "Coins" ]
            , rerollCategoryButton Treasure.CoinsCategory
            , distributedCheckbox slug isDistributed
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


gemsSection : List GemItem -> Set.Set String -> Html Msg
gemsSection items distributed =
    if List.isEmpty items then
        text ""

    else
        valuedSection "Gems"
            "gem"
            Treasure.GemsCategory
            items
            distributed
            (\g -> ( g.name, g.valueGp ))


artSection : List ArtItem -> Set.Set String -> Html Msg
artSection items distributed =
    if List.isEmpty items then
        text ""

    else
        valuedSection "Art objects"
            "art"
            Treasure.ArtCategory
            items
            distributed
            (\a -> ( a.name, a.valueGp ))


valuedSection :
    String
    -> String
    -> Treasure.Category
    -> List a
    -> Set.Set String
    -> (a -> ( String, Int ))
    -> Html Msg
valuedSection title slugPrefix category items distributed project =
    section [ class "treasure__section" ]
        [ div [ class "treasure__section-header" ]
            [ span [ class "treasure__section-title" ] [ text title ]
            , rerollCategoryButton category
            ]
        , ul [ class "treasure__list" ]
            (List.indexedMap
                (\idx item ->
                    let
                        slug =
                            slugPrefix ++ ":" ++ String.fromInt idx

                        isDistributed =
                            Set.member slug distributed

                        ( name, valueGp ) =
                            project item
                    in
                    li
                        [ class
                            ("treasure__row"
                                ++ (if isDistributed then
                                        " treasure__row--distributed"

                                    else
                                        ""
                                   )
                            )
                        ]
                        [ distributedCheckbox slug isDistributed
                        , span [ class "treasure__row-name" ] [ text name ]
                        , span [ class "treasure__row-value" ]
                            [ text (String.fromInt valueGp ++ " gp") ]
                        ]
                )
                items
            )
        ]



-- ── MAGIC ITEMS ──────────────────────────────────────────────────────────────


magicSection : List MagicItem -> Set.Set String -> Html Msg
magicSection items distributed =
    if List.isEmpty items then
        text ""

    else
        section [ class "treasure__section" ]
            [ div [ class "treasure__section-header" ]
                [ span [ class "treasure__section-title" ] [ text "Magic items" ]
                , rerollCategoryButton Treasure.MagicCategory
                ]
            , ul [ class "treasure__list" ]
                (List.indexedMap (magicRow distributed) items)
            ]


magicRow : Set.Set String -> Int -> MagicItem -> Html Msg
magicRow distributed idx item =
    let
        slug =
            "magic:" ++ String.fromInt idx

        isDistributed =
            Set.member slug distributed
    in
    li
        [ class
            ("treasure__row"
                ++ (if isDistributed then
                        " treasure__row--distributed"

                    else
                        ""
                   )
            )
        ]
        [ distributedCheckbox slug isDistributed
        , span [ class "treasure__row-name" ]
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



-- ── FOOTER ───────────────────────────────────────────────────────────────────


footerRow : TreasureState -> Html Msg
footerRow state =
    let
        totalRows =
            -- coins counts as 1 row; gems / art / magic each one
            -- row per item.
            1
                + List.length state.roll.gems
                + List.length state.roll.art
                + List.length state.roll.magic

        distributedCount =
            Set.size state.distributed
    in
    div [ class "treasure__footer" ]
        [ span [ class "treasure__footer-summary" ]
            [ text
                (String.fromInt distributedCount
                    ++ " of "
                    ++ String.fromInt totalRows
                    ++ " distributed"
                )
            ]
        , button
            [ class "action-btn action-btn--orange"
            , onClick TreasureRerollRequest
            ]
            [ text "↻ Re-roll" ]
        ]



-- ── BITS ─────────────────────────────────────────────────────────────────────


distributedCheckbox : String -> Bool -> Html Msg
distributedCheckbox slug isDistributed =
    label
        [ class "treasure__distributed"
        , attribute "aria-label" "Mark distributed to a player"
        ]
        [ input
            [ type_ "checkbox"
            , checked isDistributed
            , onClick (TreasureToggleDistributed slug)
            ]
            []
        , span [ class "treasure__distributed-text" ]
            [ text
                (if isDistributed then
                    "Distributed"

                 else
                    "Distribute"
                )
            ]
        ]


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
