module View.StatBlock exposing
    ( view
    , TagDisplay(..)
    )

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
import Html exposing (Html, a, button, div, em, hr, li, p, span, strong, text, ul)
import Html.Attributes exposing (attribute, class, href, target)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import View.Tooltips as Tooltips



-- ── ENTRY POINT ──────────────────────────────────────────────────────────────


{-| How tags (and the optional ↗ "open in new tab" link) are
rendered in the stat-block header.

  - `TagBadges` puts each tag as a right-justified badge on the
    name row. Used by the standalone single-creature page and
    the paste-modal preview, where there's room for badges but
    no need for the ↗ link (the standalone view IS the new tab;
    paste-preview creatures don't have a server id yet).
  - `TagBadgesOpenInNewTab` is the same plus an ↗ anchor at the
    far right of the name row that opens the standalone view in
    a new tab. Used by the compendium modal.
  - `TagIconTooltip` collapses tags to a single 🏷 icon next to
    the name, with the full list in a hover tooltip. Used by
    the pinned right-rail panel — which renders its own ↗ link
    as a sibling absolute-positioned over the stat block.

When a creature has no tags, the tag affordance is omitted in
all three modes; the ↗ link still appears in
`TagBadgesOpenInNewTab`.

-}
type TagDisplay
    = TagBadges
    | TagBadgesOpenInNewTab
    | TagIconTooltip


{-| Render a creature stat block.

  - `onRoll` — handler for clickable inline dice notation found
    in feature descriptions (e.g. `"7 (1d8 + 3)"`). Arguments:
    creature display name, parsed `Dice.Expression`, and the
    `clientX` / `clientY` of the mouse at click time (so the
    spawned floating popup anchors to where the user clicked).
    Pass `RollFromStatBlock` from `Main` to get the same
    roll-and-log behavior used elsewhere.
  - `onAbilityCheck` — handler for clicking one of the six
    ability cells (STR / DEX / CON / INT / WIS / CHA). Receives
    the creature's display name, the ability label (e.g. `"STR"`),
    and the flat ability modifier (`(score − 10) // 2`). Pass
    `AbilityCheckOpen` from `Main` to get the ability-check modal.
  - `onSavingThrow` — handler for clicking one of the inline
    chips in the Saving Throws property line. Receives the same
    shape as `onAbilityCheck`, but the bonus is the proficient
    save bonus straight from the creature's `savingThrows`
    record. Pass `AbilitySaveOpen` from `Main` to get the
    saving-throw modal.

-}
view :
    (String -> Dice.Expression -> Int -> Int -> msg)
    -> (String -> String -> Int -> Int -> Int -> msg)
    -> (String -> String -> Int -> Int -> Int -> msg)
    -> TagDisplay
    -> Creature
    -> Html msg
view onRoll onAbilityCheck onSavingThrow tagDisplay c =
    div [ class "statblock" ]
        ([ viewHead tagDisplay c
         , hr [ class "statblock__divider" ] []
         , viewCoreLine c
         , hr [ class "statblock__divider" ] []
         , viewAbilities onAbilityCheck c
         , hr [ class "statblock__divider" ] []
         ]
            ++ viewProperties onSavingThrow c
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
            ++ viewLoot c.loot
            ++ viewMetaTags c
        )



-- ── HEAD ─────────────────────────────────────────────────────────────────────


viewHead : TagDisplay -> Creature -> Html msg
viewHead tagDisplay c =
    div [ class "statblock__head" ]
        [ nameRow tagDisplay c
        , div [ class "statblock__type" ]
            [ text (typeLine c) ]
        , if String.isEmpty c.description then
            text ""

          else
            p [ class "statblock__description" ]
                [ em [] [ text c.description ] ]
        ]


{-| Name row layout depends on the `TagDisplay` choice.

  - `TagBadges`: name on the left, badge strip right-justified
    in a flex row — the compendium modal has room for both.
  - `TagIconTooltip`: name and 🏷 icon sit inline together (no
    flex spacing), so the icon reads as "this creature has tags"
    immediately to the right of the name in the cramped right-rail
    panel.

-}
nameRow : TagDisplay -> Creature -> Html msg
nameRow tagDisplay c =
    case tagDisplay of
        TagBadges ->
            div [ class "statblock__name-row" ]
                [ div [ class "statblock__name" ] [ text c.name ]
                , kindBadge c.kind
                , bundledBadge c.isBundled
                , tagBadges c.tags
                ]

        TagBadgesOpenInNewTab ->
            div [ class "statblock__name-row" ]
                [ div [ class "statblock__name" ] [ text c.name ]
                , kindBadge c.kind
                , bundledBadge c.isBundled
                , div [ class "statblock__name-row-end" ]
                    [ tagBadges c.tags
                    , openInNewTabLink c.id
                    ]
                ]

        TagIconTooltip ->
            div [ class "statblock__name statblock__name--inline-tags" ]
                (text c.name
                    :: kindBadge c.kind
                    :: bundledBadge c.isBundled
                    :: inlineTagIcon c.tags
                )


{-| Padlock chip rendered next to the kind badge when the creature
originates from the read-only SRD bundle. Mirrors the existing
kind-badge styling pattern so themed colour tokens stay in one
place; the dedicated `--bundled` modifier lets CSS distinguish
bundled vs Player/Enemy/NPC visually.

Omitted entirely for user-owned creatures to keep the row visually
quiet — the absence of the chip is the affirmative signal that the
creature is editable.

-}
bundledBadge : Bool -> Html msg
bundledBadge isBundled =
    if isBundled then
        span
            [ class "statblock__kind-badge statblock__kind-badge--bundled"
            , Html.Attributes.attribute "title" "Bundled (read-only)"
            , Html.Attributes.attribute "aria-label" "Bundled (read-only)"
            ]
            [ text "🔒" ]

    else
        text ""


{-| Coloured Player / Enemy / NPC chip rendered to the right of
the creature name. Uses the same `--kind-*` modifier suffixes
the Custom-card kind badge uses so themed colour tokens stay in
one place.
-}
kindBadge : Compendium.CreatureKind -> Html msg
kindBadge kind =
    let
        ( label, slug ) =
            case kind of
                Compendium.Player ->
                    ( "Player", "kind-player" )

                Compendium.Enemy ->
                    ( "Enemy", "kind-enemy" )

                Compendium.Npc ->
                    ( "NPC", "kind-npc" )
    in
    span
        [ class ("statblock__kind-badge statblock__kind-badge--" ++ slug) ]
        [ text label ]


{-| ↗ anchor that opens the standalone single-creature page in
a new tab. Used by the compendium-modal stat block so the GM
can park a creature's full sheet in another browser tab without
leaving the modal. Mirrors the side-panel link in target, rel,
and tooltip; only the layout differs (this one sits inline in
the name row rather than absolute-positioned over the block).
-}
openInNewTabLink : String -> Html msg
openInNewTabLink id =
    a
        [ class "statblock__open"
        , href ("/compendium/creatures/" ++ id)
        , target "_blank"
        , attribute "rel" "noopener"
        , Tooltips.attr Tooltips.panelStatBlockNewWindow
        , attribute "aria-label" "Open in new window"
        ]
        [ text "↗" ]


tagBadges : List String -> Html msg
tagBadges tags =
    if List.isEmpty tags then
        text ""

    else
        div [ class "statblock__tags" ]
            (List.map tagBadge tags)


{-| Single 🏷 icon next to the creature name with an instant
tooltip carrying the full tag list. `data-tooltip-delay="0"`
asks the tooltip portal to show without its default 300ms gate
— the icon has no other affordance and the user is already
hovering deliberately. Returns an empty list when the creature
has no tags so the caller can splice it into the name row
without conditional plumbing.
-}
inlineTagIcon : List String -> List (Html msg)
inlineTagIcon tags =
    if List.isEmpty tags then
        []

    else
        let
            joined =
                String.join ", " tags
        in
        [ span
            [ class "statblock__tag-icon"
            , attribute "data-tooltip" joined
            , attribute "data-tooltip-delay" "0"
            , attribute "aria-label" ("Tags: " ++ joined)
            ]
            [ text "🏷" ]
        ]


tagBadge : String -> Html msg
tagBadge t =
    span [ class "statblock__tag-badge" ] [ text t ]


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
viewAbilities onAbilityCheck c =
    let
        cell label _ score =
            -- Ability cells fire an *ability check*, so we pass
            -- the flat modifier (not the proficient save bonus).
            -- The save bonus has its own dedicated chip in the
            -- Saving Throws property line.
            viewAbilityCell onAbilityCheck c.name label (modifier score) score
    in
    div [ class "ability-row" ]
        [ cell "STR" Str c.abilities.str
        , cell "DEX" Dex c.abilities.dex
        , cell "CON" Con c.abilities.con
        , cell "INT" Int_ c.abilities.int
        , cell "WIS" Wis c.abilities.wis
        , cell "CHA" Cha c.abilities.cha
        ]


viewAbilityCell :
    (String -> String -> Int -> Int -> Int -> msg)
    -> String
    -> String
    -> Int
    -> Int
    -> Html msg
viewAbilityCell onAbilityCheck creatureName label bonus score =
    Html.button
        [ class "ability ability--clickable"
        , Html.Attributes.type_ "button"
        , Html.Events.on "click"
            (Decode.map2 (onAbilityCheck creatureName label bonus)
                (Decode.field "clientX" Decode.int)
                (Decode.field "clientY" Decode.int)
            )
        , Tooltips.attr (Tooltips.statBlockAbilityCheck label (modifier score))
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


viewProperties :
    (String -> String -> Int -> Int -> Int -> msg)
    -> Creature
    -> List (Html msg)
viewProperties onSavingThrow c =
    List.filterMap identity
        [ savingThrowsHtmlLine onSavingThrow c.name c.savingThrows
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


{-| Saving-Throws property line with per-save click-to-roll
buttons. Mirrors the ability-cell affordance up top: the bonus
value `+N` is a real `<button>` that fires the same
`AbilitySaveOpen` Msg with the save's bonus (instead of the
flat ability modifier the ability cells default to when the
creature isn't proficient).
-}
savingThrowsHtmlLine :
    (String -> String -> Int -> Int -> Int -> msg)
    -> String
    -> List AbilitySave
    -> Maybe (Html msg)
savingThrowsHtmlLine onSavingThrow creatureName saves =
    if List.isEmpty saves then
        Nothing

    else
        Just
            (p [ class "statblock__prop" ]
                (strong [] [ text "Saving Throws " ]
                    :: (saves
                            |> List.map (savingThrowEntry onSavingThrow creatureName)
                            |> List.intersperse (text " ")
                       )
                )
            )


savingThrowEntry :
    (String -> String -> Int -> Int -> Int -> msg)
    -> String
    -> AbilitySave
    -> Html msg
savingThrowEntry onSavingThrow creatureName s =
    let
        label =
            abilityLabel s.ability
    in
    Html.button
        [ class "statblock__save-roll"
        , Html.Attributes.type_ "button"
        , Html.Events.on "click"
            (Decode.map2 (onSavingThrow creatureName label s.bonus)
                (Decode.field "clientX" Decode.int)
                (Decode.field "clientY" Decode.int)
            )
        , Tooltips.attr (Tooltips.statBlockSavingThrow label s.bonus)
        ]
        [ text (label ++ " " ++ signed s.bonus) ]


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


{-| 2024 MM habitat line: Material-Plane habitats render bare,
the planar ones group under a single "Planar (…)" wrapper so the
rendered string mirrors what's printed in the book. Empty list →
empty string so the prop line drops out entirely.
-}
habitatsLine : List Compendium.Habitat -> String
habitatsLine hs =
    if List.isEmpty hs then
        ""

    else
        let
            ( material, planar ) =
                List.partition (not << Compendium.isPlanarHabitat) hs

            materialPart =
                List.map Compendium.habitatLabel material

            planarPart =
                if List.isEmpty planar then
                    []

                else
                    [ "Planar ("
                        ++ String.join ", "
                            (List.map Compendium.habitatLabel planar)
                        ++ ")"
                    ]
        in
        String.join ", " (materialPart ++ planarPart)


treasuresLine : List Compendium.Treasure -> String
treasuresLine ts =
    if List.isEmpty ts then
        ""

    else
        ts
            |> List.map Compendium.treasureLabel
            |> String.join ", "


{-| Habitat + Treasure tag block. Sits at the very bottom of the
stat block (below custom sections), separated by a divider so the
2024 MM meta tags don't visually attach to the last lore section.
Renders nothing when both fields are empty.
-}
viewMetaTags : Creature -> List (Html msg)
viewMetaTags c =
    let
        rows =
            List.filterMap identity
                [ habitatPropLine (habitatsLine c.habitats)
                , propLine "Treasure" (treasuresLine c.treasures)
                ]
    in
    if List.isEmpty rows then
        []

    else
        hr [ class "statblock__divider" ] [] :: rows


{-| Inline copy of `propLine` for the Habitat row so we can
attach a tooltip explaining where the data came from — the
bundled `habitats` field is filled by the CLI's inference pass
[`Encounter.RandomEncounter`](../Encounter/RandomEncounter.elm)
description, not by an authoritative SRD source.
-}
habitatPropLine : String -> Maybe (Html msg)
habitatPropLine value =
    if String.isEmpty value then
        Nothing

    else
        Just
            (p
                [ class "statblock__prop"
                , Tooltips.attr Tooltips.statBlockHabitat
                ]
                [ strong [] [ text "Habitat " ]
                , text value
                ]
            )


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
                :: descriptionParagraph (legendaryPreamble la)
                :: List.map (viewLegendaryOption onRoll creatureName) la.options


{-| Compose the SRD-format "Legendary Action Uses: N (M in Lair)."
preamble. When the creature carries a non-empty `description`
(typically because the user pasted in their own block), trust
that text and show it verbatim — otherwise synthesize the 2024
MM canonical paragraph from the structured `uses` / `usesInLair`
fields.

The lair clause is omitted entirely when `usesInLair <= uses`
so non-lair creatures (Solar, Tarrasque, Unicorn) read cleanly.

-}
legendaryPreamble : LegendaryActions -> String
legendaryPreamble la =
    if not (String.isEmpty (String.trim la.description)) then
        la.description

    else
        let
            usesPart =
                "Legendary Action Uses: "
                    ++ String.fromInt la.uses
                    ++ (if la.usesInLair > la.uses then
                            " (" ++ String.fromInt la.usesInLair ++ " in Lair)."

                        else
                            "."
                       )
        in
        usesPart
            ++ " Immediately after another creature's turn, this creature can expend a use to take one of the following actions. This creature regains all expended uses at the start of each of its turns."


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


{-| Free-form loot list at the bottom of the stat block. Empty
list renders nothing — bundled creatures don't ship with loot
and the section shouldn't appear as an empty heading.
-}
viewLoot : List String -> List (Html msg)
viewLoot loot =
    if List.isEmpty loot then
        []

    else
        [ sectionHeading "Loot"
        , ul [ class "statblock__loot" ]
            (List.map (\item -> li [] [ text item ]) loot)
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
                , Tooltips.attr (Tooltips.statBlockRoll shown)
                ]
                [ text shown ]

        Dice.AttackLink shown mod ->
            button
                [ class "dice-link attack-link"
                , Html.Events.on "click"
                    (Decode.map2 (onRoll creatureName (attackExpression mod))
                        (Decode.field "clientX" Decode.int)
                        (Decode.field "clientY" Decode.int)
                    )
                , Tooltips.attr (Tooltips.statBlockAttack shown mod)
                ]
                [ text shown ]


{-| `1d20 + mod` expression for an attack-roll click. The sign
of `mod` flows into `constant` as-is; negative values render as
`1d20 - 1` via `expressionToString`.
-}
attackExpression : Int -> Dice.Expression
attackExpression mod =
    { dice = [ { count = 1, faces = 20, sign = Dice.Positive } ]
    , constant = mod
    , damageType = Nothing
    }


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
