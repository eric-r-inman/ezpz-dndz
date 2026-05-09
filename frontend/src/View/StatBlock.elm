module View.StatBlock exposing (view)

{-| Read-only stat-block renderer for `Compendium.Creature`.

Shared between the Compendium browser modal (Phase 3) and the
per-card Quick View (Phase 7). The renderer is purely
presentational — it has no Msgs of its own — but inline dice
notation in feature descriptions is wired to a caller-supplied
roll handler so the same `RollFromStatBlock` flow works in both
contexts.

@docs view

-}

import Compendium
    exposing
        ( Abilities
        , Ability(..)
        , AbilitySave
        , Creature
        , CreatureKind(..)
        , CustomSection
        , Feature
        , LairActions
        , LegendaryActions
        , LegendaryOption
        , RegionalEffects
        , Senses
        , Size(..)
        , SkillBonus
        , Speed
        , Spellcasting
        , Usage(..)
        )
import Dice
import Html exposing (Html, button, div, em, hr, p, span, strong, text)
import Html.Attributes exposing (class, title)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import View.Tooltips as Tooltips



-- ── ENTRY POINT ──────────────────────────────────────────────────────────────


{-| Render a creature stat block.

  - `onRoll` — handler for clickable inline dice notation found
    in feature descriptions (e.g. `"7 (1d8 + 3)"`). Arguments:
    creature display name, parsed `Dice.Expression`, and the
    `clientX` / `clientY` of the mouse at click time (so the
    spawned floating popup anchors to where the user clicked).
    Pass `RollFromStatBlock` from `Main` to get the same
    roll-and-log behavior used elsewhere.
  - `onAbilityClick` — handler for clicking one of the six
    ability cells (STR / DEX / CON / INT / WIS / CHA). Receives
    the creature's display name, the ability label (e.g. `"STR"`),
    and the saving-throw bonus (proficient if the creature has a
    `savingThrows` entry for this ability, otherwise the flat
    ability modifier). Pass `AbilitySaveOpen` from `Main` to
    get the saving-throw modal.

-}
view :
    (String -> Dice.Expression -> Int -> Int -> msg)
    -> (String -> String -> Int -> Int -> Int -> msg)
    -> Creature
    -> Html msg
view onRoll onAbilityClick c =
    div [ class "statblock" ]
        ([ viewHead c
         , hr [ class "statblock__divider" ] []
         , viewCoreLine c
         , hr [ class "statblock__divider" ] []
         , viewAbilities onAbilityClick c
         , hr [ class "statblock__divider" ] []
         ]
            ++ viewProperties c
            ++ [ hr [ class "statblock__divider" ] [] ]
            ++ viewTraits onRoll c
            ++ viewActionGroup onRoll c.name "Actions" c.actions
            ++ viewActionGroup onRoll c.name "Bonus Actions" c.bonusActions
            ++ viewActionGroup onRoll c.name "Reactions" c.reactions
            ++ viewLegendaryActions onRoll c.name c.legendaryActions
            ++ viewLairActions onRoll c.name c.lairActions
            ++ viewRegionalEffects onRoll c.name c.regionalEffects
            ++ viewSpellcasting c.spellcasting
            ++ viewCustomSections c.customSections
        )



-- ── HEAD ─────────────────────────────────────────────────────────────────────


viewHead : Creature -> Html msg
viewHead c =
    div [ class "statblock__head" ]
        [ div [ class "statblock__name" ] [ text c.name ]
        , div [ class "statblock__type" ]
            [ text (typeLine c) ]
        , if String.isEmpty c.description then
            text ""

          else
            p [ class "statblock__description" ]
                [ em [] [ text c.description ] ]
        ]


typeLine : Creature -> String
typeLine c =
    let
        sizeRace =
            sizeLabel c.size
                ++ (if String.isEmpty c.race then
                        ""

                    else
                        " " ++ c.race
                   )

        withSubrace =
            if String.isEmpty c.subrace then
                sizeRace

            else
                sizeRace ++ " (" ++ c.subrace ++ ")"

        alignment =
            if String.isEmpty c.alignment then
                ""

            else
                ", " ++ c.alignment
    in
    withSubrace ++ alignment



-- ── CORE LINE (AC / HP / Initiative / Speed) ────────────────────────────────


{-| Stacked vertically (one row per property) so each value lands
on its own line — much easier to scan than the older single-row
grid, especially for 2024-format stat blocks where Initiative
joins AC, HP, and Speed. Colons match the prevailing visual
style for "label: value" lookups.
-}
viewCoreLine : Creature -> Html msg
viewCoreLine c =
    div [ class "statblock__meta" ]
        [ viewProperty "Armor Class:" (acDisplay c)
        , viewProperty "Hit Points:" (hpDisplay c)
        , viewProperty "Initiative:" (initiativeDisplay c.initiativeBonus)
        , viewProperty "Speed:" (speedDisplay c.speed)
        ]


{-| `+10 (20)` style: signed bonus, then the parenthesized
"passive" initiative result (10 + bonus) the GM uses when they
choose not to roll. Mirrors the D&D 2024 stat-block format.
-}
initiativeDisplay : Int -> String
initiativeDisplay bonus =
    signed bonus ++ " (" ++ String.fromInt (10 + bonus) ++ ")"


acDisplay : Creature -> String
acDisplay c =
    if String.isEmpty c.armorClassNote then
        String.fromInt c.armorClass

    else
        String.fromInt c.armorClass ++ " (" ++ c.armorClassNote ++ ")"


hpDisplay : Creature -> String
hpDisplay c =
    if String.isEmpty c.hpFormula then
        String.fromInt c.maxHp

    else
        String.fromInt c.maxHp ++ " (" ++ c.hpFormula ++ ")"


speedDisplay : Speed -> String
speedDisplay s =
    let
        hover =
            if s.hover then
                " (hover)"

            else
                ""

        parts =
            List.filterMap identity
                [ Just (String.fromInt s.walk ++ " ft.")
                , whenPositive s.fly (\n -> "fly " ++ String.fromInt n ++ " ft." ++ hover)
                , whenPositive s.swim (\n -> "swim " ++ String.fromInt n ++ " ft.")
                , whenPositive s.climb (\n -> "climb " ++ String.fromInt n ++ " ft.")
                , whenPositive s.burrow (\n -> "burrow " ++ String.fromInt n ++ " ft.")
                ]
    in
    String.join ", " parts


whenPositive : Int -> (Int -> String) -> Maybe String
whenPositive n fmt =
    if n > 0 then
        Just (fmt n)

    else
        Nothing



-- ── ABILITIES ────────────────────────────────────────────────────────────────


viewAbilities : (String -> String -> Int -> Int -> Int -> msg) -> Creature -> Html msg
viewAbilities onAbilityClick c =
    let
        cell label ability score =
            viewAbilityCell onAbilityClick c.name label (saveBonus c.savingThrows ability score) score
    in
    div [ class "ability-row" ]
        [ cell "STR" Str c.abilities.str
        , cell "DEX" Dex c.abilities.dex
        , cell "CON" Con c.abilities.con
        , cell "INT" Int_ c.abilities.int
        , cell "WIS" Wis c.abilities.wis
        , cell "CHA" Cha c.abilities.cha
        ]


{-| Pull the proficient save bonus from `savingThrows` if the
creature is proficient in this ability; otherwise fall back to
the flat ability modifier. This is the bonus the saving-throw
modal applies to its `1d20`.
-}
saveBonus : List AbilitySave -> Ability -> Int -> Int
saveBonus saves ability score =
    case List.filter (\s -> s.ability == ability) saves of
        save :: _ ->
            save.bonus

        [] ->
            modifier score


viewAbilityCell :
    (String -> String -> Int -> Int -> Int -> msg)
    -> String
    -> String
    -> Int
    -> Int
    -> Html msg
viewAbilityCell onAbilityClick creatureName label bonus score =
    Html.button
        [ class "ability ability--clickable"
        , Html.Attributes.type_ "button"
        , Html.Events.on "click"
            (Decode.map2 (onAbilityClick creatureName label bonus)
                (Decode.field "clientX" Decode.int)
                (Decode.field "clientY" Decode.int)
            )
        , title (Tooltips.statBlockSavingThrow label)
        ]
        [ div [ class "ability__label" ] [ text label ]
        , div [ class "ability__value" ] [ text (String.fromInt score) ]
        , div [ class "ability__mod" ] [ text ("(" ++ signed (modifier score) ++ ")") ]
        ]


modifier : Int -> Int
modifier score =
    (score - 10) // 2


signed : Int -> String
signed n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n



-- ── PROPERTIES BLOCK ─────────────────────────────────────────────────────────


viewProperties : Creature -> List (Html msg)
viewProperties c =
    List.filterMap identity
        [ propLine "Saving Throws" (savingThrowsLine c.savingThrows)
        , propLine "Skills" (skillsLine c.skills)
        , propLine "Damage Vulnerabilities" (joinList c.damageVulnerabilities)
        , propLine "Damage Resistances" (joinList c.damageResistances)
        , propLine "Damage Immunities" (joinList c.damageImmunities)
        , propLine "Condition Immunities" (joinList c.conditionImmunities)
        , propLine "Senses" (sensesLine c.senses)
        , propLine "Languages" (languagesLine c.languages)
        , propLine "Challenge" (challengeLine c)
        , propLine "Proficiency Bonus" (proficiencyLine c.proficiencyBonus)
        ]


propLine : String -> String -> Maybe (Html msg)
propLine label value =
    if String.isEmpty value then
        Nothing

    else
        Just
            (p [ class "statblock__prop" ]
                [ strong [] [ text (label ++ " ") ]
                , text value
                ]
            )


viewProperty : String -> String -> Html msg
viewProperty label value =
    p [ class "statblock__prop" ]
        [ strong [] [ text (label ++ " ") ]
        , text value
        ]


savingThrowsLine : List AbilitySave -> String
savingThrowsLine saves =
    saves
        |> List.map (\s -> abilityLabel s.ability ++ " " ++ signed s.bonus)
        |> String.join ", "


skillsLine : List SkillBonus -> String
skillsLine skills =
    skills
        |> List.map (\s -> s.name ++ " " ++ signed s.bonus)
        |> String.join ", "


joinList : List String -> String
joinList =
    String.join ", "


sensesLine : Senses -> String
sensesLine s =
    let
        parts =
            List.filterMap identity
                [ whenPositive s.blindsight (\n -> "blindsight " ++ String.fromInt n ++ " ft.")
                , whenPositive s.darkvision (\n -> "darkvision " ++ String.fromInt n ++ " ft.")
                , whenPositive s.tremorsense (\n -> "tremorsense " ++ String.fromInt n ++ " ft.")
                , whenPositive s.truesight (\n -> "truesight " ++ String.fromInt n ++ " ft.")
                , Just ("passive Perception " ++ String.fromInt s.passivePerception)
                ]
    in
    String.join ", " parts


languagesLine : List String -> String
languagesLine langs =
    if List.isEmpty langs then
        "—"

    else
        String.join ", " langs


{-| "16 (XP 15,000, or 18,000 in lair)" — mirrors the D&D 2024
stat-block convention. When the creature carries no lair-XP,
render the simpler "16 (15,000 XP)" form; when it has no XP at
all, just the bare CR.
-}
challengeLine : Creature -> String
challengeLine c =
    if String.isEmpty c.challengeRating then
        ""

    else if c.xp > 0 && c.xpInLair > 0 then
        c.challengeRating
            ++ " (XP "
            ++ formatXp c.xp
            ++ ", or "
            ++ formatXp c.xpInLair
            ++ " in lair)"

    else if c.xp > 0 then
        c.challengeRating ++ " (" ++ formatXp c.xp ++ " XP)"

    else
        c.challengeRating


formatXp : Int -> String
formatXp n =
    -- "12,345" style. Quick & dirty: split into groups of three from the right.
    let
        digits =
            String.fromInt n |> String.toList |> List.reverse

        chunks =
            chunk3 digits

        rendered =
            chunks
                |> List.map String.fromList
                |> List.map String.reverse
                |> List.reverse
                |> String.join ","
    in
    rendered


chunk3 : List Char -> List (List Char)
chunk3 cs =
    case cs of
        [] ->
            []

        _ ->
            List.take 3 cs :: chunk3 (List.drop 3 cs)


proficiencyLine : Int -> String
proficiencyLine n =
    if n <= 0 then
        ""

    else
        signed n



-- ── TRAITS ───────────────────────────────────────────────────────────────────


viewTraits : (String -> Dice.Expression -> Int -> Int -> msg) -> Creature -> List (Html msg)
viewTraits onRoll c =
    if List.isEmpty c.traits then
        []

    else
        List.map (viewFeature onRoll c.name) c.traits



-- ── ACTION-LIKE GROUPS (Actions / Bonus Actions / Reactions) ─────────────────


viewActionGroup : (String -> Dice.Expression -> Int -> Int -> msg) -> String -> String -> List Feature -> List (Html msg)
viewActionGroup onRoll creatureName heading features =
    if List.isEmpty features then
        []

    else
        sectionHeading heading
            :: List.map (viewFeature onRoll creatureName) features


sectionHeading : String -> Html msg
sectionHeading t =
    div [ class "statblock__section-heading" ] [ text t ]



-- ── LEGENDARY / LAIR / REGIONAL ──────────────────────────────────────────────


viewLegendaryActions : (String -> Dice.Expression -> Int -> Int -> msg) -> String -> Maybe LegendaryActions -> List (Html msg)
viewLegendaryActions onRoll creatureName maybeLa =
    case maybeLa of
        Nothing ->
            []

        Just la ->
            sectionHeading "Legendary Actions"
                :: descriptionParagraph la.description
                :: List.map (viewLegendaryOption onRoll creatureName) la.options


viewLegendaryOption : (String -> Dice.Expression -> Int -> Int -> msg) -> String -> LegendaryOption -> Html msg
viewLegendaryOption onRoll creatureName opt =
    p [ class "statblock__feature" ]
        (strong []
            [ text
                (opt.name
                    ++ (if opt.cost > 1 then
                            " (Costs " ++ String.fromInt opt.cost ++ " Actions). "

                        else
                            ". "
                       )
                )
            ]
            :: List.map (viewSegment onRoll creatureName) (Dice.scan opt.description)
        )


viewLairActions : (String -> Dice.Expression -> Int -> Int -> msg) -> String -> Maybe LairActions -> List (Html msg)
viewLairActions onRoll creatureName maybeLa =
    case maybeLa of
        Nothing ->
            []

        Just la ->
            sectionHeading "Lair Actions"
                :: descriptionParagraph la.description
                :: List.map (viewFeature onRoll creatureName) la.options


viewRegionalEffects : (String -> Dice.Expression -> Int -> Int -> msg) -> String -> Maybe RegionalEffects -> List (Html msg)
viewRegionalEffects onRoll creatureName maybeRe =
    case maybeRe of
        Nothing ->
            []

        Just re ->
            sectionHeading "Regional Effects"
                :: descriptionParagraph re.description
                :: List.map (viewFeature onRoll creatureName) re.effects
                ++ (if String.isEmpty re.fadeAfter then
                        []

                    else
                        [ p [ class "statblock__regional-fade" ]
                            [ em [] [ text re.fadeAfter ] ]
                        ]
                   )



-- ── SPELLCASTING ─────────────────────────────────────────────────────────────


viewSpellcasting : Maybe Spellcasting -> List (Html msg)
viewSpellcasting maybeSc =
    case maybeSc of
        Nothing ->
            []

        Just sc ->
            sectionHeading "Spellcasting"
                :: descriptionParagraph sc.description
                :: spellcastingMeta sc
                ++ List.map viewSpellSlotLine sc.slots
                ++ List.map viewInnateLine sc.innatePerDay
                ++ atWillLine sc.atWill


spellcastingMeta : Spellcasting -> List (Html msg)
spellcastingMeta sc =
    let
        bits =
            List.filterMap identity
                [ if sc.saveDc > 0 then
                    Just ("spell save DC " ++ String.fromInt sc.saveDc)

                  else
                    Nothing
                , if sc.attackBonus /= 0 then
                    Just (signed sc.attackBonus ++ " to hit with spell attacks")

                  else
                    Nothing
                ]
    in
    if List.isEmpty bits then
        []

    else
        [ p [ class "statblock__prop" ]
            [ strong [] [ text "Spellcasting ability " ]
            , text (abilityLabel sc.ability ++ " (" ++ String.join ", " bits ++ ")")
            ]
        ]


atWillLine : List String -> List (Html msg)
atWillLine spells =
    if List.isEmpty spells then
        []

    else
        [ p [ class "statblock__feature" ]
            [ strong [] [ text "At will: " ]
            , text (String.join ", " spells)
            ]
        ]


viewSpellSlotLine : Compendium.SpellSlotLevel -> Html msg
viewSpellSlotLine sl =
    p [ class "statblock__feature" ]
        [ strong []
            [ text
                (slotHeading sl.level sl.slots ++ ": ")
            ]
        , text (String.join ", " sl.spells)
        ]


slotHeading : Int -> Int -> String
slotHeading level slots =
    let
        levelLabel =
            if level == 0 then
                "Cantrips (at will)"

            else
                ordinal level ++ " level (" ++ String.fromInt slots ++ " slots)"
    in
    levelLabel


ordinal : Int -> String
ordinal n =
    case n of
        1 ->
            "1st"

        2 ->
            "2nd"

        3 ->
            "3rd"

        _ ->
            String.fromInt n ++ "th"


viewInnateLine : Compendium.InnatePerDay -> Html msg
viewInnateLine i =
    p [ class "statblock__feature" ]
        [ strong []
            [ text (String.fromInt i.uses ++ "/day each: ") ]
        , text (String.join ", " i.spells)
        ]



-- ── CUSTOM SECTIONS ──────────────────────────────────────────────────────────


viewCustomSections : List CustomSection -> List (Html msg)
viewCustomSections sections =
    List.concatMap viewCustomSection sections


viewCustomSection : CustomSection -> List (Html msg)
viewCustomSection cs =
    [ sectionHeading cs.name
    , p [ class "statblock__feature" ] [ text cs.body ]
    ]



-- ── FEATURE / SEGMENT ────────────────────────────────────────────────────────


viewFeature : (String -> Dice.Expression -> Int -> Int -> msg) -> String -> Feature -> Html msg
viewFeature onRoll creatureName f =
    p [ class "statblock__feature" ]
        (strong []
            [ text (f.name ++ usageSuffix f.usage ++ ". ") ]
            :: List.map (viewSegment onRoll creatureName) (Dice.scan f.description)
        )


usageSuffix : Maybe Usage -> String
usageSuffix maybeUsage =
    case maybeUsage of
        Nothing ->
            ""

        Just AtWill ->
            " (At Will)"

        Just (Recharge { low, high }) ->
            if low == high then
                " (Recharge " ++ String.fromInt low ++ ")"

            else
                " (Recharge " ++ String.fromInt low ++ "–" ++ String.fromInt high ++ ")"

        Just (PerDay n) ->
            " (" ++ String.fromInt n ++ "/Day)"

        Just (PerShortRest n) ->
            " (" ++ String.fromInt n ++ "/Short Rest)"

        Just (PerLongRest n) ->
            " (" ++ String.fromInt n ++ "/Long Rest)"


viewSegment : (String -> Dice.Expression -> Int -> Int -> msg) -> String -> Dice.Segment -> Html msg
viewSegment onRoll creatureName segment =
    case segment of
        Dice.Literal s ->
            text s

        Dice.DiceLink shown expr ->
            button
                [ class "dice-link"
                , Html.Events.on "click"
                    (Decode.map2 (onRoll creatureName expr)
                        (Decode.field "clientX" Decode.int)
                        (Decode.field "clientY" Decode.int)
                    )
                , title (Tooltips.statBlockRoll shown)
                ]
                [ text shown ]


descriptionParagraph : String -> Html msg
descriptionParagraph s =
    p [ class "statblock__prose" ] [ text s ]



-- ── LABELS ───────────────────────────────────────────────────────────────────


sizeLabel : Size -> String
sizeLabel s =
    case s of
        Tiny ->
            "Tiny"

        Small ->
            "Small"

        Medium ->
            "Medium"

        Large ->
            "Large"

        Huge ->
            "Huge"

        Gargantuan ->
            "Gargantuan"


abilityLabel : Ability -> String
abilityLabel a =
    case a of
        Str ->
            "Str"

        Dex ->
            "Dex"

        Con ->
            "Con"

        Int_ ->
            "Int"

        Wis ->
            "Wis"

        Cha ->
            "Cha"
