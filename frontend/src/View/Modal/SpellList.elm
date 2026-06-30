module View.Modal.SpellList exposing (view)

{-| Read-only "what spells are in this encounter?" popup.

Triggered by the 📜 icon in the encounter title bar. Walks the
encounter queue, looks each creature up in the compendium, and
prints every caster's at-will / per-day / slot spells in one
scannable list grouped by creature.

Two sources of spell data are scanned:

  - The structured `Spellcasting` field on the compendium
    creature (populated for legacy SRD / pre-2024 entries the
    parser knew how to break out).
  - Any action / bonus-action / trait whose name is
    "Spellcasting" or "Innate Spellcasting" — the 2024 MM
    format keeps the whole spell list inside one block of
    bullets like `**At Will:** Detect Magic` /
    `**2/Day Each:** Tongues`. Parsed inline here so we don't
    have to re-extract every bundled creature.

Creatures with no spells from either source are skipped. When
no caster is in the queue at all, an empty-state line tells
the GM so they don't think the modal is broken.

@docs view

-}

import Compendium exposing (Ability(..), Spellcasting)
import Encounter exposing (Creature)
import Html exposing (Html, button, div, h3, li, p, span, text, ul)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just ModalSpellList ->
            View.Modal.view
                { close = SpellListClose
                , noOp = NoOp
                , title = "Spells in encounter"
                , extraClass = "modal--spell-list"
                , chrome = model.modalChrome
                , body = body model
                }

        _ ->
            text ""


body : Model -> List (Html Msg)
body model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            let
                casters =
                    model.encounter.creatures
                        |> List.filterMap (resolveCaster db)
            in
            if List.isEmpty casters then
                [ p [ class "spell-list__empty" ]
                    [ text "No spellcasters in this encounter." ]
                ]

            else
                List.map casterSection casters

        CompendiumDbLoading ->
            [ p [ class "spell-list__empty" ] [ text "Loading compendium…" ] ]

        CompendiumDbFailed _ ->
            [ p [ class "spell-list__empty" ]
                [ text "Couldn't load the compendium — spells unavailable." ]
            ]



-- ── Resolution / extraction ───────────────────────────────────────


type alias CasterSummary =
    { creature : Creature
    , meta : Meta
    , groups : List SpellGroup
    }


{-| Header metadata extracted either from the structured
`Spellcasting` field (preferred, has ability + DC + attack) or
from the freeform action description (DC pulled out of the text
when present).
-}
type alias Meta =
    { ability : Maybe String
    , saveDc : Maybe Int
    , attackBonus : Maybe Int
    }


type alias SpellGroup =
    { label : String
    , spells : List String
    }


resolveCaster : Compendium.Db -> Creature -> Maybe CasterSummary
resolveCaster db c =
    let
        lookup =
            case c.creatureId of
                Just id ->
                    case Compendium.find id db of
                        Just hit ->
                            Just hit

                        Nothing ->
                            Compendium.findByName c.name db

                Nothing ->
                    Compendium.findByName c.name db
    in
    case lookup of
        Nothing ->
            Nothing

        Just compendiumC ->
            let
                groups =
                    case compendiumC.spellcasting of
                        Just sc ->
                            structuredGroups sc

                        Nothing ->
                            actionGroups compendiumC

                meta =
                    case compendiumC.spellcasting of
                        Just sc ->
                            structuredMeta sc

                        Nothing ->
                            actionMeta compendiumC
            in
            if List.isEmpty groups then
                Nothing

            else
                Just { creature = c, meta = meta, groups = groups }


structuredGroups : Spellcasting -> List SpellGroup
structuredGroups sc =
    let
        atWill =
            if List.isEmpty sc.atWill then
                []

            else
                [ { label = "At will", spells = sc.atWill } ]

        innate =
            List.map
                (\g ->
                    { label = String.fromInt g.uses ++ "/day each"
                    , spells = g.spells
                    }
                )
                sc.innatePerDay

        slots =
            List.map
                (\g ->
                    { label = slotLabel g.level g.slots
                    , spells = g.spells
                    }
                )
                sc.slots
    in
    atWill ++ innate ++ slots


structuredMeta : Spellcasting -> Meta
structuredMeta sc =
    { ability = Just (abilityLabel sc.ability)
    , saveDc =
        if sc.saveDc > 0 then
            Just sc.saveDc

        else
            Nothing
    , attackBonus =
        if sc.attackBonus /= 0 then
            Just sc.attackBonus

        else
            Nothing
    }


{-| Scan the compendium creature's actions / bonus-actions /
traits for a feature whose name reads as a spellcasting block,
then parse its description for `**At Will:** …` / `**N/Day
Each:** …` lines.
-}
actionGroups : Compendium.Creature -> List SpellGroup
actionGroups c =
    spellFeatures c
        |> List.concatMap (\f -> parseSpellLines f.description)


actionMeta : Compendium.Creature -> Meta
actionMeta c =
    let
        text_ =
            spellFeatures c
                |> List.map .description
                |> String.join "\n"
    in
    { ability = Nothing
    , saveDc = extractSaveDc text_
    , attackBonus = Nothing
    }


spellFeatures : Compendium.Creature -> List Compendium.Feature
spellFeatures c =
    (c.actions ++ c.bonusActions ++ c.traits)
        |> List.filter isSpellFeatureName


isSpellFeatureName : Compendium.Feature -> Bool
isSpellFeatureName f =
    let
        n =
            String.toLower (String.trim f.name)
    in
    n == "spellcasting" || n == "innate spellcasting"


{-| Pull `spell save DC NN` out of a freeform description. The
2024 MM Spellcasting blurb almost always names its DC inline,
e.g. "using Charisma as the spellcasting ability (spell save DC
17)" — we surface that next to the caster's name as a handy
GM-glance.
-}
extractSaveDc : String -> Maybe Int
extractSaveDc src =
    let
        lower =
            String.toLower src
    in
    case String.indexes "save dc" lower of
        idx :: _ ->
            let
                tail =
                    String.dropLeft (idx + String.length "save dc") lower
                        |> String.trimLeft
            in
            tail
                |> String.toList
                |> takeWhileDigits
                |> String.fromList
                |> String.toInt

        [] ->
            Nothing


takeWhileDigits : List Char -> List Char
takeWhileDigits chars =
    case chars of
        c :: rest ->
            if Char.isDigit c then
                c :: takeWhileDigits rest

            else
                []

        [] ->
            []



-- ── Description parser ────────────────────────────────────────────


{-| Walk every line of a Spellcasting action description, picking
out the `**Label:** spells` bullets. Tolerant of bullet markers
(`-` / `*`), markdown bold (`**`), and leading whitespace.
-}
parseSpellLines : String -> List SpellGroup
parseSpellLines src =
    src
        |> String.lines
        |> List.filterMap parseLine


parseLine : String -> Maybe SpellGroup
parseLine raw =
    let
        line =
            raw
                |> String.trim
                |> stripBullet
                |> String.trim
    in
    case splitOnFirst ':' line of
        Nothing ->
            Nothing

        Just ( labelRaw, spellsRaw ) ->
            let
                label =
                    cleanLabel labelRaw

                spells =
                    parseSpells spellsRaw
            in
            if List.isEmpty spells || not (looksLikeSpellLabel label) then
                Nothing

            else
                Just { label = label, spells = spells }


stripBullet : String -> String
stripBullet s =
    -- Order matters: try `- ` first so we don't accidentally
    -- treat a `*` markdown italic as a bullet.
    if String.startsWith "- " s then
        String.dropLeft 2 s

    else if String.startsWith "* " s then
        String.dropLeft 2 s

    else
        s


splitOnFirst : Char -> String -> Maybe ( String, String )
splitOnFirst sep s =
    case String.indexes (String.fromChar sep) s of
        idx :: _ ->
            Just
                ( String.left idx s
                , String.dropLeft (idx + 1) s
                )

        [] ->
            Nothing


cleanLabel : String -> String
cleanLabel raw =
    raw
        |> String.replace "**" ""
        |> String.replace "*" ""
        |> String.trim
        |> normaliseLabel


{-| Display tweak: lowercase the descriptive bits so "1/Day
Each" reads as "1/day each", matching the rest of the modal.
The leading number or word stays as authored.
-}
normaliseLabel : String -> String
normaliseLabel s =
    s
        |> String.replace "/Day Each" "/day each"
        |> String.replace "/Day" "/day"
        |> String.replace "At Will" "At will"
        |> String.replace "/Long Rest" "/long rest"
        |> String.replace "/Short Rest" "/short rest"


looksLikeSpellLabel : String -> Bool
looksLikeSpellLabel raw =
    let
        s =
            String.toLower raw
    in
    String.contains "at will" s
        || String.contains "/day" s
        || String.contains "/long rest" s
        || String.contains "/short rest" s
        || String.contains "cantrip" s
        || String.contains "level (" s


parseSpells : String -> List String
parseSpells raw =
    raw
        |> String.replace "**" ""
        |> String.replace "*" ""
        |> String.split ","
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)



-- ── View ──────────────────────────────────────────────────────────


casterSection : CasterSummary -> Html Msg
casterSection summary =
    div [ class "spell-list__caster" ]
        [ casterHeader summary
        , spellGroupList summary.groups
        ]


casterHeader : CasterSummary -> Html Msg
casterHeader { creature, meta } =
    let
        nameNode =
            case creature.creatureId of
                Just creatureId ->
                    button
                        [ class "spell-list__name"
                        , type_ "button"
                        , onClick (PanelShowCreature creatureId creature.name)
                        , Tooltips.attr ("Pin " ++ creature.name ++ "'s stat block to the side panel")
                        , attribute "aria-label"
                            ("Show stat block for " ++ creature.name)
                        ]
                        [ text creature.name ]

                Nothing ->
                    span [ class "spell-list__name spell-list__name--plain" ]
                        [ text creature.name ]

        bits =
            List.filterMap identity
                [ meta.ability
                , Maybe.map (\dc -> "DC " ++ String.fromInt dc) meta.saveDc
                , Maybe.map (\a -> signed a ++ " to hit") meta.attackBonus
                ]

        metaSuffix =
            if List.isEmpty bits then
                text ""

            else
                span [ class "spell-list__meta" ]
                    [ text (" — " ++ String.join " · " bits) ]
    in
    h3 [ class "spell-list__caster-header" ]
        [ nameNode, metaSuffix ]


spellGroupList : List SpellGroup -> Html Msg
spellGroupList groups =
    div [ class "spell-list__groups" ] (List.map renderGroup groups)


renderGroup : SpellGroup -> Html Msg
renderGroup g =
    div [ class "spell-list__group" ]
        [ div [ class "spell-list__group-label" ] [ text g.label ]
        , ul [ class "spell-list__spells" ]
            (List.map
                (\s -> li [ class "spell-list__spell" ] [ text s ])
                g.spells
            )
        ]


slotLabel : Int -> Int -> String
slotLabel level slots =
    if level == 0 then
        "Cantrips (at will)"

    else
        ordinal level ++ " level (" ++ String.fromInt slots ++ " slot" ++ plural slots ++ ")"


plural : Int -> String
plural n =
    if n == 1 then
        ""

    else
        "s"


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


signed : Int -> String
signed n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n


abilityLabel : Ability -> String
abilityLabel a =
    case a of
        Str ->
            "STR"

        Dex ->
            "DEX"

        Con ->
            "CON"

        Int_ ->
            "INT"

        Wis ->
            "WIS"

        Cha ->
            "CHA"
