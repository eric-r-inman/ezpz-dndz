module View.Panel.Treasure exposing (view)

{-| Treasure-generator panel.

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

import Compendium
import Dict exposing (Dict)
import Encounter
import Encounter.Treasure as Treasure
    exposing
        ( ArtItem
        , Coins
        , CreatureContribution
        , GemItem
        , Kind(..)
        , MagicItem
        )
import Encounter.Treasure.Budget as Budget
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
import Ui.Compendium
import Ui.Treasure exposing (TreasureUi)
import Util.Number
import View.Panel
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.surface of
        Just (Model.SurfaceTreasure ui) ->
            let
                brackets =
                    enemyBrackets model

                expectedGp =
                    expectedGpFor ui.kind brackets
            in
            View.Panel.view
                { close = TreasureClose
                , title = "💰 Treasure"
                , subtitle = Nothing
                , extraClass = "panel-drawer--treasure"
                , body =
                    body ui
                        model.encounter.treasure
                        model.encounter.treasureSettings
                        expectedGp
                        (List.length brackets)
                        model.userTreasureProfiles
                        model.userTreasureProfileNameDraft
                }

        _ ->
            text ""


{-| The enemies' brackets in the encounter, derived the same way
the generator does. Used by the Average hint near Roll.
-}
enemyBrackets : Model -> List Treasure.Bracket
enemyBrackets model =
    let
        db =
            case model.compendium.db of
                Ui.Compendium.CompendiumDbLoaded loaded ->
                    loaded

                _ ->
                    Compendium.fromList []
    in
    model.encounter.creatures
        |> List.filter (\c -> c.creatureKind == "enemy" && not c.isPlaceholder)
        |> List.map (creatureBracket db)


creatureBracket : Compendium.Db -> Encounter.Creature -> Treasure.Bracket
creatureBracket db c =
    c.creatureId
        |> Maybe.andThen (\id -> Compendium.find id db)
        |> Maybe.map (.challengeRating >> Compendium.crToFloat >> Treasure.bracketFor)
        |> Maybe.withDefault Treasure.B1to4


{-| SRD-baseline expected gp for the upcoming roll.

Hoard rolls use the toughest enemy's bracket once. Individual
rolls sum the per-creature baseline across every enemy, since
each rolls its own bracket independently. Returns 0 when there
are no enemies — the roll itself short-circuits to an empty
result, so there's no useful baseline to surface.

-}
expectedGpFor : Kind -> List Treasure.Bracket -> Int
expectedGpFor kind brackets =
    case ( kind, brackets ) of
        ( _, [] ) ->
            0

        ( Hoard, _ ) ->
            Budget.expectedGpFor Hoard (List.foldl maxBracket Treasure.B1to4 brackets)

        ( Individual, _ ) ->
            brackets
                |> List.map (Budget.expectedGpFor Individual)
                |> List.sum


maxBracket : Treasure.Bracket -> Treasure.Bracket -> Treasure.Bracket
maxBracket a b =
    if Treasure.bracketIndex a > Treasure.bracketIndex b then
        a

    else
        b


body : TreasureUi -> Maybe Treasure.TreasureRoll -> Treasure.TreasureSettings -> Int -> Int -> Dict String Treasure.TreasureSettings -> String -> List (Html Msg)
body ui maybeRoll settings expectedGp enemyCount profiles profileDraft =
    [ helpText
    , controlRow ui expectedGp
    , multiplierNotice ui.kind enemyCount (Treasure.togglesFor ui.kind settings)
    , settingsSection ui.kind ui.settingsExpanded settings profiles profileDraft
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
settingsSection : Treasure.Kind -> Bool -> Treasure.TreasureSettings -> Dict String Treasure.TreasureSettings -> String -> Html Msg
settingsSection kind expanded settings profiles profileDraft =
    let
        toggles =
            Treasure.togglesFor kind settings
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
                [ text ("Tune your rolls (" ++ Treasure.kindLabel kind ++ ")") ]
            ]
        , if expanded then
            div [ class "treasure__settings-body" ]
                [ presetRow
                , settingsRow kind
                    "Coins"
                    "coins"
                    (Just settings.coinsCount)
                    Nothing
                    toggles.coinsNone
                , settingsRow kind
                    "Gems"
                    "gems"
                    (Just settings.gemsCount)
                    (Just settings.gemsValue)
                    toggles.gemsNone
                , settingsRow kind
                    "Art"
                    "art"
                    (Just settings.artCount)
                    (Just settings.artValue)
                    toggles.artNone
                , settingsRow kind
                    "Magic"
                    "magic"
                    (Just settings.magicCount)
                    (Just settings.magicValue)
                    toggles.magicNone
                , scrollChanceRow settings.magicScrollChance toggles.magicNone
                , settingsRow kind
                    "Mundane"
                    "mundane"
                    (Just settings.mundaneCount)
                    Nothing
                    toggles.mundaneNone
                , settingsRow kind
                    "Weapons"
                    "weapons"
                    (Just settings.weaponsCount)
                    Nothing
                    toggles.weaponsNone
                , settingsRow kind
                    "Armor"
                    "armor"
                    (Just settings.armorCount)
                    Nothing
                    toggles.armorNone
                , profileRow profiles profileDraft
                , div [ class "treasure__settings-actions" ]
                    [ button
                        [ class "treasure__settings-reset"
                        , type_ "button"
                        , onClick TreasureSettingsReset
                        , Tooltips.attr "Return every knob to Normal"
                        ]
                        [ text "↺ Reset to defaults" ]
                    ]
                ]

          else
            text ""
        ]


{-| One-click presets row that lives at the top of the settings
body. Each chip applies a canned set of toggles to the current
Kind; see `Update.Treasure.presetFor`. Counts + value adjusts
always snap back to Normal so a preset reliably overwrites
previous tuning.
-}
presetRow : Html Msg
presetRow =
    div [ class "treasure__settings-presets" ]
        [ span [ class "treasure__settings-presets-label" ]
            [ text "Presets:" ]
        , presetChip Msg.PresetCoinsOnly
            "Coins only"
            "Just coin yield — pocket money, bounties, salvage."
        , presetChip Msg.PresetCoinsGems
            "+ Gems"
            "Coins plus the encounter's bracket-appropriate gems."
        , presetChip Msg.PresetSrdDefault
            "Full SRD"
            "The classic four — coins, gems, art, magic items."
        , presetChip Msg.PresetWizardLair
            "Wizard's lair"
            "Coins + magic, with a 75% scroll swap so most items land as spell scrolls."
        , presetChip Msg.PresetBanditCamp
            "Bandit camp"
            "Coins + weapons + armor.  No gems, art, or magic."
        ]


presetChip : Msg.TreasurePreset -> String -> String -> Html Msg
presetChip preset label tooltip =
    button
        [ class "treasure__settings-preset-chip"
        , type_ "button"
        , Tooltips.attr tooltip
        , onClick (TreasureSettingsPresetApply preset)
        ]
        [ text label ]


{-| Save / load / delete row for user-named profiles. Lives at
the bottom of the settings body so the GM tunes the settings
above it before saving. Profiles persist server-side when
authed; anonymous sessions get an empty dict (a follow-up could
mirror userTreasureTable's localStorage path).
-}
profileRow : Dict String Treasure.TreasureSettings -> String -> Html Msg
profileRow profiles draft =
    let
        sortedNames =
            Dict.keys profiles |> List.sort
    in
    div [ class "treasure__settings-profile-row" ]
        [ div [ class "treasure__settings-profile-load" ]
            [ span [ class "treasure__settings-profile-label" ]
                [ text "Load profile:" ]
            , if List.isEmpty sortedNames then
                span [ class "treasure__settings-profile-empty" ]
                    [ text "(none saved yet)" ]

              else
                div [ class "treasure__settings-profile-chips" ]
                    (List.map profileChip sortedNames)
            ]
        , div [ class "treasure__settings-profile-save" ]
            [ Html.input
                [ class "treasure__settings-profile-input"
                , type_ "text"
                , value draft
                , Attr.placeholder "Save current as…"
                , onInput TreasureProfileNameChanged
                ]
                []
            , button
                [ class "treasure__settings-profile-save-btn"
                , type_ "button"
                , onClick TreasureProfileSave
                , Attr.disabled (String.isEmpty (String.trim draft))
                ]
                [ text "Save" ]
            ]
        ]


profileChip : String -> Html Msg
profileChip name =
    span [ class "treasure__settings-profile-chip" ]
        [ button
            [ class "treasure__settings-profile-chip-load"
            , type_ "button"
            , Tooltips.attr "Apply this profile to the current settings"
            , onClick (TreasureProfileLoad name)
            ]
            [ text name ]
        , button
            [ class "treasure__settings-profile-chip-delete"
            , type_ "button"
            , Tooltips.attr ("Delete profile '" ++ name ++ "'")
            , onClick (TreasureProfileDelete name)
            ]
            [ text "🚫" ]
        ]


{-| Spell-scroll post-process chance sits as a sub-row under
Magic. Disabled (and visually muted) when Magic itself is
toggled to None, since the post-process only runs on items the
magic roll produces.
-}
scrollChanceRow : Int -> Bool -> Html Msg
scrollChanceRow current magicNone =
    div
        [ class
            ("treasure__settings-row treasure__settings-row--sub"
                ++ (if magicNone then
                        " treasure__settings-row--muted"

                    else
                        ""
                   )
            )
        ]
        [ span [ class "treasure__settings-row-label" ] [ text "↳ Scrolls" ]
        , Html.label [ class "treasure__settings-scroll" ]
            [ span [ class "treasure__settings-axis" ] [ text "Swap chance" ]
            , Html.input
                [ class "treasure__settings-scroll-input"
                , type_ "number"
                , Attr.min "0"
                , Attr.max "100"
                , value (String.fromInt current)
                , Attr.disabled magicNone
                , onInput TreasureSettingsScrollChanceSet
                ]
                []
            , span [ class "treasure__settings-scroll-unit" ] [ text "%" ]
            ]
        , span [ class "treasure__settings-row-spacer" ] []
        , span [ class "treasure__settings-row-spacer" ] []
        ]


settingsRow :
    Treasure.Kind
    -> String
    -> String
    -> Maybe Treasure.CountAdjust
    -> Maybe Treasure.ValueAdjust
    -> Bool
    -> Html Msg
settingsRow kind label_ itemClass maybeCount maybeValue noneOn =
    div [ class "treasure__settings-row" ]
        [ span [ class "treasure__settings-row-label" ] [ text label_ ]
        , case maybeCount of
            Just countValue ->
                countSegmented itemClass countValue noneOn

            Nothing ->
                span [ class "treasure__settings-row-spacer" ] []
        , case maybeValue of
            Just valueValue ->
                valueSegmented itemClass valueValue noneOn

            Nothing ->
                span [ class "treasure__settings-row-spacer" ] []
        , noneToggle kind itemClass noneOn
        ]


{-| Right-edge toggle that suppresses the whole category at
roll time. Stays at the far right of every row regardless of
whether the row has Count, Value, or both knobs to its left.

Rendered as a button (not a native `<input type=checkbox>`)
with a glyph indicator, so the new value is decided explicitly
from `current` rather than read back off the browser's own
checkbox state.

-}
noneToggle : Treasure.Kind -> String -> Bool -> Html Msg
noneToggle kind itemClass current =
    button
        [ class
            ("treasure__settings-none"
                ++ (if current then
                        " treasure__settings-none--on"

                    else
                        ""
                   )
            )
        , type_ "button"
        , onClick (TreasureSettingsNoneSet kind itemClass (not current))
        , attribute "role" "switch"
        , attribute "aria-checked"
            (if current then
                "true"

             else
                "false"
            )
        , Tooltips.attr
            (if current then
                "This category is currently skipped — click to roll it"

             else
                "Skip this category at roll time"
            )
        ]
        [ span [ class "treasure__settings-none-glyph" ]
            [ text
                (if current then
                    "☑"

                 else
                    "☐"
                )
            ]
        , span [ class "treasure__settings-none-label" ] [ text "None" ]
        ]


countSegmented : String -> Treasure.CountAdjust -> Bool -> Html Msg
countSegmented itemClass current disabled =
    let
        countLabel =
            if itemClass == "coins" then
                "Amount"

            else
                "Count"
    in
    div
        [ class
            ("treasure__settings-segmented"
                ++ (if disabled then
                        " treasure__settings-segmented--disabled"

                    else
                        ""
                   )
            )
        ]
        [ span [ class "treasure__settings-axis" ] [ text countLabel ]
        , segmentedButton itemClass
            current
            Treasure.CountFewer
            "Fewer"
            (TreasureSettingsCountSet itemClass "fewer")
            disabled
        , segmentedButton itemClass
            current
            Treasure.CountNormal
            "Normal"
            (TreasureSettingsCountSet itemClass "normal")
            disabled
        , segmentedButton itemClass
            current
            Treasure.CountMore
            "More"
            (TreasureSettingsCountSet itemClass "more")
            disabled
        ]


valueSegmented : String -> Treasure.ValueAdjust -> Bool -> Html Msg
valueSegmented itemClass current disabled =
    let
        valueLabel =
            if itemClass == "magic" then
                "Rarity"

            else
                "Value"
    in
    div
        [ class
            ("treasure__settings-segmented"
                ++ (if disabled then
                        " treasure__settings-segmented--disabled"

                    else
                        ""
                   )
            )
        ]
        [ span [ class "treasure__settings-axis" ] [ text valueLabel ]
        , segmentedButton itemClass
            current
            Treasure.ValueLower
            "Lower"
            (TreasureSettingsValueSet itemClass "lower")
            disabled
        , segmentedButton itemClass
            current
            Treasure.ValueNormal
            "Normal"
            (TreasureSettingsValueSet itemClass "normal")
            disabled
        , segmentedButton itemClass
            current
            Treasure.ValueHigher
            "Higher"
            (TreasureSettingsValueSet itemClass "higher")
            disabled
        ]


{-| Tiny generic segmented-control button. Active when `current
== target`. Stays type-agnostic via Elm's structural typing —
the call sites supply tagged CountAdjust or ValueAdjust values.
-}
segmentedButton : String -> a -> a -> String -> Msg -> Bool -> Html Msg
segmentedButton _ current target text_ msg disabled =
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
        , Attr.disabled disabled
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
        [ div [ class "treasure__contributions-name" ]
            [ text c.creatureName
            , span [ class "treasure__contributions-bracket" ]
                [ text (" — " ++ Treasure.bracketLabel c.bracket) ]
            ]
        , div [ class "treasure__contributions-lines" ]
            (contributionLines c)
        ]


{-| Per-creature non-coin breakdown. Each category that's
present renders as its own labelled line under the creature
name, so a row reads:

    Goblin — CR 0–4
      Coins: 12 gp
      Gems: Bloodstone (50 gp), Quartz (50 gp)
      Magic: Spell Scroll (1st level): Magic Missile

This is the legible-breakdown landing for #5 in the audit
report; the prior single-line summary was hard to parse for
multi-category Individual rolls.

-}
contributionLines : CreatureContribution -> List (Html Msg)
contributionLines c =
    [ ( "Coins", coinSummary c.coins )
    , ( "Gems", joinList (List.map gemLabel c.gems) )
    , ( "Art", joinList (List.map gemLabel c.art) )
    , ( "Magic", joinList (List.map .name c.magic) )
    , ( "Mundane", joinList (List.map flatLabel c.mundane) )
    , ( "Weapons", joinList (List.map flatLabel c.weapons) )
    , ( "Armor", joinList (List.map flatLabel c.armor) )
    , ( "Loot", joinList c.loot )
    ]
        |> List.filterMap
            (\( label_, body_ ) ->
                if String.isEmpty body_ || body_ == "—" then
                    Nothing

                else
                    Just
                        (div [ class "treasure__contributions-line" ]
                            [ span [ class "treasure__contributions-line-label" ]
                                [ text (label_ ++ ": ") ]
                            , span [ class "treasure__contributions-line-body" ]
                                [ text body_ ]
                            ]
                        )
            )


joinList : List String -> String
joinList items =
    if List.isEmpty items then
        ""

    else
        String.join ", " items


gemLabel : { item | name : String, valueGp : Int } -> String
gemLabel g =
    g.name ++ " (" ++ String.fromInt g.valueGp ++ " gp)"


flatLabel : { item | name : String, valueGp : Int } -> String
flatLabel item =
    item.name ++ " (" ++ String.fromInt item.valueGp ++ " gp)"


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
            , Tooltips.attr "View / edit your treasure table"
            ]
            [ text "Edit treasure table…" ]
        ]



-- ── HEADER CONTROLS ──────────────────────────────────────────────────────────


{-| One-paragraph orientation under the title bar. Explains the
two Roll kinds and the post-roll Loot aggregation so first-time
users don't have to guess at the Kind dropdown.
-}
helpText : Html Msg
helpText =
    p [ class "treasure__help" ]
        [ text "Treasure roller for Hoard ('Boss') or Individual ('All') rolls. 'Boss' rolls CR bracket of highest-CR enemy; 'All' rolls for all enemies. Loot is added after the randomized roll (for enemies with Loot in their stat block; you can add Loot via the Creature editor in the Compendium)." ]


{-| Inline notice when the GM is on an Individual roll with
multiple enemies AND has at least one non-coin category opted
in. Each creature rolls those categories independently, so a
5-creature encounter with Gems on produces ~5 hoards' worth of
gems; the warning prevents accidental party-wealth inflation
without blocking the roll.

Silent for Hoard (one roll regardless of count) and for
Individual encounters where all non-coin toggles are off.

-}
multiplierNotice : Kind -> Int -> Treasure.CategoryToggles -> Html Msg
multiplierNotice kind enemyCount toggles =
    let
        anyNonCoinOn =
            not toggles.gemsNone
                || not toggles.artNone
                || not toggles.magicNone
                || not toggles.mundaneNone
                || not toggles.weaponsNone
                || not toggles.armorNone
    in
    if kind == Individual && enemyCount > 3 && anyNonCoinOn then
        p
            [ class "treasure__multiplier-notice"
            , Tooltips.attr
                "On Individual rolls each creature rolls the enabled non-coin categories independently from their bracket's hoard table — so 5 creatures means 5× the per-creature drop."
            ]
            [ text
                ("⚠️  Individual rolls with non-coin toggles fire per creature — "
                    ++ String.fromInt enemyCount
                    ++ " enemies means each enabled category drops "
                    ++ String.fromInt enemyCount
                    ++ "× the per-creature amount."
                )
            ]

    else
        text ""


controlRow : TreasureUi -> Int -> Html Msg
controlRow ui expectedGp =
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
        , budgetHint expectedGp
        ]


{-| Inline SRD-baseline hint next to Roll: "Average ≈ X gp for
this encounter." Shown only when the encounter has enemies that
resolve to a known bracket — silent on empty encounters or when
all enemies fall through to the B1to4 default (which usually
means "no compendium hit," not "actually CR 0").
-}
budgetHint : Int -> Html Msg
budgetHint expectedGp =
    if expectedGp <= 0 then
        text ""

    else
        span
            [ class "treasure__budget-hint"
            , Tooltips.attr
                "SRD-derived baseline coin gp for this encounter — your roll will land near this on default settings."
            ]
            [ text ("Average ≈ " ++ formatNumber expectedGp ++ " gp") ]


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
        , mundaneSection roll.mundane
        , weaponsSection roll.weapons
        , armorSection roll.armor
        , lootSection roll.loot
        ]


mundaneSection : List Treasure.MundaneItem -> Html Msg
mundaneSection items =
    if List.isEmpty items then
        text ""

    else
        valuedSection "Mundane gear"
            Treasure.MundaneCategory
            items
            (\m -> ( m.name, m.valueGp ))
            TreasureMundaneRemove


weaponsSection : List Treasure.WeaponItem -> Html Msg
weaponsSection items =
    if List.isEmpty items then
        text ""

    else
        valuedSection "Weapons"
            Treasure.WeaponsCategory
            items
            (\w -> ( w.name, w.valueGp ))
            TreasureWeaponsRemove


armorSection : List Treasure.ArmorItem -> Html Msg
armorSection items =
    if List.isEmpty items then
        text ""

    else
        valuedSection "Armor"
            Treasure.ArmorCategory
            items
            (\a -> ( a.name, a.valueGp ))
            TreasureArmorRemove


summaryStrip : Treasure.TreasureRoll -> Html Msg
summaryStrip roll =
    let
        coinValue =
            Treasure.totalCoinValueGp roll.coins

        gemValue =
            Treasure.totalGemValue roll.gems

        artValue =
            Treasure.totalArtValue roll.art

        mundaneValue =
            Treasure.totalMundaneValue roll.mundane

        weaponsValue =
            Treasure.totalWeaponsValue roll.weapons

        armorValue =
            Treasure.totalArmorValue roll.armor

        magicCount =
            List.length roll.magic

        total =
            coinValue + gemValue + artValue + mundaneValue + weaponsValue + armorValue
    in
    div [ class "treasure__summary" ]
        [ span [ class "treasure__summary-chunk" ]
            [ text ("Coins ≈ " ++ formatNumber coinValue ++ " gp") ]
        , span [ class "treasure__summary-chunk" ]
            [ text ("Gems ≈ " ++ formatNumber gemValue ++ " gp") ]
        , span [ class "treasure__summary-chunk" ]
            [ text ("Art ≈ " ++ formatNumber artValue ++ " gp") ]
        , span [ class "treasure__summary-chunk" ]
            [ text ("Magic items: " ++ String.fromInt magicCount) ]
        , span [ class "treasure__summary-total" ]
            [ text ("Total value ≈ " ++ formatNumber total ++ " gp") ]
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
        , Tooltips.attr "Remove"
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
