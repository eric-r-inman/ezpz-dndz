module Compendium.SpellcastingText exposing (parse)

{-| Parse a freeform "Spellcasting" / "Innate Spellcasting"
description into a structured `Compendium.Spellcasting` record.

The paste-in parser and the encounter-bar spell-list modal both
need to pull spells out of prose that looks like

    The djinni casts one of the following spells, using
    Charisma as the spellcasting ability (spell save DC 17):

      - **At Will:** Detect Evil and Good, Detect Magic
      - **2/Day Each:** Create Food and Water, Tongues
      - **1/Day Each:** Creation, Gaseous Form

or the older 5e slot-based phrasing

    Spellcasting. The archmage is an 18th-level spellcaster.
    Its spellcasting ability is Intelligence (spell save DC
    17, +9 to hit with spell attacks). The archmage has the
    following wizard spells prepared:

      - Cantrips (at will): fire bolt, light, mage hand
      - 1st level (4 slots): detect magic, magic missile
      - 2nd level (3 slots): mirror image, misty step

The parser strips markdown bold markers (`**`), splits the
prose on `-` bullets and finds each `Label: spells` chunk,
then classifies the label as At-Will / N-per-day / cantrip /
Nth-level slot. Meta (ability, save DC, spell attack bonus)
is scraped out of whatever prose surrounds the bullets so the
stat-block header still reads correctly.

@docs parse

-}

import Compendium exposing (Ability(..), InnatePerDay, SpellSlotLevel, Spellcasting)


{-| Attempt to build a `Spellcasting` record from a description
string. Returns `Nothing` when nothing that looks like a spell
group can be recognised — the caller should leave any existing
spellcasting state alone in that case.
-}
parse : String -> Maybe Spellcasting
parse rawDescription =
    let
        cleaned =
            rawDescription
                |> String.replace "\u{000D}" ""
                |> String.replace "**" ""

        segments =
            cleaned
                |> normaliseBullets
                |> String.split "•SEP•"
                |> List.map String.trim
                |> List.filter (not << String.isEmpty)

        groups =
            List.filterMap classifySegment segments

        atWill =
            groups |> List.filterMap onlyAtWill |> List.concat

        innate =
            List.filterMap onlyInnate groups

        slots =
            List.filterMap onlySlot groups
    in
    if List.isEmpty atWill && List.isEmpty innate && List.isEmpty slots then
        Nothing

    else
        Just
            { description = summariseDescription rawDescription
            , ability = extractAbility rawDescription |> Maybe.withDefault Cha
            , saveDc = extractSaveDc rawDescription |> Maybe.withDefault 0
            , attackBonus = extractAttackBonus rawDescription |> Maybe.withDefault 0
            , atWill = atWill
            , slots = slots
            , innatePerDay = innate
            }



-- ── Segment splitting ─────────────────────────────────────────────


{-| Replace every bullet-shaped delimiter we know about
(`-`, `–`, `•`, or the same at line-start) with a stable
sentinel we can then split on. Bulleted stat blocks arrive
either newline-separated or (after the paste parser joins body
lines with spaces) space-separated; either shape produces a
delimiter we can normalise.
-}
normaliseBullets : String -> String
normaliseBullets s =
    s
        |> String.replace "\n- " "•SEP•"
        |> String.replace "\n– " "•SEP•"
        |> String.replace "\n• " "•SEP•"
        |> String.replace " - " "•SEP•"
        |> String.replace " – " "•SEP•"
        |> String.replace " • " "•SEP•"



-- ── Segment → group classification ────────────────────────────────


type Group
    = GroupAtWill (List String)
    | GroupInnate InnatePerDay
    | GroupSlot SpellSlotLevel


onlyAtWill : Group -> Maybe (List String)
onlyAtWill g =
    case g of
        GroupAtWill spells ->
            Just spells

        _ ->
            Nothing


onlyInnate : Group -> Maybe InnatePerDay
onlyInnate g =
    case g of
        GroupInnate ip ->
            Just ip

        _ ->
            Nothing


onlySlot : Group -> Maybe SpellSlotLevel
onlySlot g =
    case g of
        GroupSlot s ->
            Just s

        _ ->
            Nothing


{-| Parse one bullet segment. Splits on the first `:` (label
vs. spells) and matches the label against the four known
patterns — anything else (like the leading prose sentence) is
skipped by returning `Nothing`.
-}
classifySegment : String -> Maybe Group
classifySegment segment =
    case splitOnFirst ':' segment of
        Nothing ->
            Nothing

        Just ( labelRaw, spellsRaw ) ->
            let
                label =
                    labelRaw
                        |> String.trim
                        |> String.toLower

                spells =
                    parseSpells spellsRaw
            in
            if List.isEmpty spells then
                Nothing

            else
                classifyLabel label spells


classifyLabel : String -> List String -> Maybe Group
classifyLabel label spells =
    if label == "at will" then
        Just (GroupAtWill spells)

    else if String.startsWith "cantrips" label then
        -- "cantrips (at will)" and plain "cantrips" both land here.
        Just (GroupSlot { level = 0, slots = 0, spells = spells })

    else
        case parseLevelSlots label of
            Just ( level, slots ) ->
                Just (GroupSlot { level = level, slots = slots, spells = spells })

            Nothing ->
                case parseUsesPerDay label of
                    Just uses ->
                        Just (GroupInnate { uses = uses, spells = spells })

                    Nothing ->
                        Nothing


{-| Recognise `Nst level (M slots)` / `Nth level (M slot)` etc.
Returns `(level, slots)` on match.
-}
parseLevelSlots : String -> Maybe ( Int, Int )
parseLevelSlots label =
    case String.indexes " level" label of
        [] ->
            Nothing

        idx :: _ ->
            let
                levelPart =
                    String.left idx label |> String.trim

                level =
                    readOrdinalPrefix levelPart

                slotsPart =
                    String.dropLeft (idx + String.length " level") label

                slots =
                    slotsPart
                        |> firstIntIn
                        |> Maybe.withDefault 0
            in
            Maybe.map (\l -> ( l, slots )) level


{-| Read the leading numeric portion of "1st" / "2nd" / "3rd" /
"9th" — used to identify the slot level in labels like
"1st level (4 slots)".
-}
readOrdinalPrefix : String -> Maybe Int
readOrdinalPrefix s =
    s
        |> String.toList
        |> takeWhileChars Char.isDigit
        |> String.fromList
        |> String.toInt


{-| Recognise `N/day` and `N/day each` — returns the count.
The `each` vs bare form both map to the same InnatePerDay
structure (there's no separate wire field), but the display
label in the modal will read "N/day each" so callers preserve
per-spell semantics visually.
-}
parseUsesPerDay : String -> Maybe Int
parseUsesPerDay label =
    if String.contains "/day" label then
        firstIntIn label

    else
        Nothing


parseSpells : String -> List String
parseSpells raw =
    raw
        |> String.replace "*" ""
        |> String.split ","
        |> List.map String.trim
        |> List.map stripTrailingDash
        |> List.filter (not << String.isEmpty)


{-| Some spell lists have a trailing `-` on the last entry
because the segment splitter left a stray bullet marker on the
end. Trim it so we don't render "Plane Shift -".
-}
stripTrailingDash : String -> String
stripTrailingDash s =
    if String.endsWith " -" s then
        String.dropRight 2 s |> String.trim

    else
        s



-- ── Meta extraction (ability / DC / attack bonus) ─────────────────


extractAbility : String -> Maybe Ability
extractAbility src =
    let
        lower =
            String.toLower src
    in
    if String.contains "charisma" lower then
        Just Cha

    else if String.contains "wisdom" lower then
        Just Wis

    else if String.contains "intelligence" lower then
        Just Int_

    else if String.contains "constitution" lower then
        Just Con

    else if String.contains "dexterity" lower then
        Just Dex

    else if String.contains "strength" lower then
        Just Str

    else
        Nothing


extractSaveDc : String -> Maybe Int
extractSaveDc src =
    firstIntAfter "save dc" (String.toLower src)


{-| Recognise `+N to hit with spell attacks` or `spell attack
modifier +N` — both phrasings appear in the wild.
-}
extractAttackBonus : String -> Maybe Int
extractAttackBonus src =
    let
        lower =
            String.toLower src
    in
    case firstSignedIntBefore "to hit with spell attacks" lower of
        Just n ->
            Just n

        Nothing ->
            firstSignedIntAfter "spell attack modifier" lower


{-| Trim the description down to the sentence(s) that come
before the first bullet — that's the "The X casts... using
Charisma..." preamble that gives context in the statblock view.
-}
summariseDescription : String -> String
summariseDescription raw =
    let
        cleaned =
            raw |> String.replace "\u{000D}" ""

        firstBullet =
            [ "\n- ", "\n– ", "\n• ", " - ", " – ", " • " ]
                |> List.filterMap
                    (\marker ->
                        case String.indexes marker cleaned of
                            idx :: _ ->
                                Just idx

                            [] ->
                                Nothing
                    )
                |> List.minimum
    in
    case firstBullet of
        Just idx ->
            String.left idx cleaned |> String.trim

        Nothing ->
            String.trim cleaned



-- ── Low-level scanning helpers ───────────────────────────────────


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


firstIntIn : String -> Maybe Int
firstIntIn s =
    s
        |> String.toList
        |> dropUntil Char.isDigit
        |> takeWhileChars Char.isDigit
        |> String.fromList
        |> String.toInt


firstIntAfter : String -> String -> Maybe Int
firstIntAfter marker haystack =
    case String.indexes marker haystack of
        [] ->
            Nothing

        idx :: _ ->
            String.dropLeft (idx + String.length marker) haystack
                |> firstIntIn


firstSignedIntBefore : String -> String -> Maybe Int
firstSignedIntBefore marker haystack =
    case String.indexes marker haystack of
        [] ->
            Nothing

        idx :: _ ->
            String.left idx haystack
                |> String.right 20
                |> lastSignedInt


firstSignedIntAfter : String -> String -> Maybe Int
firstSignedIntAfter marker haystack =
    case String.indexes marker haystack of
        [] ->
            Nothing

        idx :: _ ->
            String.dropLeft (idx + String.length marker) haystack
                |> String.left 20
                |> firstSignedInt


firstSignedInt : String -> Maybe Int
firstSignedInt s =
    let
        chars =
            String.toList s |> dropUntil (\c -> c == '+' || c == '-' || Char.isDigit c)
    in
    case chars of
        [] ->
            Nothing

        c :: _ ->
            if c == '+' then
                readIntFrom (List.drop 1 chars)

            else if c == '-' then
                Maybe.map negate (readIntFrom (List.drop 1 chars))

            else
                readIntFrom chars


lastSignedInt : String -> Maybe Int
lastSignedInt s =
    s
        |> String.reverse
        |> String.toList
        |> takeWhileChars (\c -> Char.isDigit c || c == '+' || c == '-')
        |> String.fromList
        |> String.reverse
        |> String.toInt


readIntFrom : List Char -> Maybe Int
readIntFrom chars =
    chars
        |> takeWhileChars Char.isDigit
        |> String.fromList
        |> String.toInt


dropUntil : (Char -> Bool) -> List Char -> List Char
dropUntil pred chars =
    case chars of
        c :: rest ->
            if pred c then
                chars

            else
                dropUntil pred rest

        [] ->
            []


takeWhileChars : (Char -> Bool) -> List Char -> List Char
takeWhileChars pred chars =
    case chars of
        c :: rest ->
            if pred c then
                c :: takeWhileChars pred rest

            else
                []

        [] ->
            []
