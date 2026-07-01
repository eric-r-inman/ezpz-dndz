module Compendium.SpellcastingText exposing (parse)

{-| Parse a freeform "Spellcasting" / "Innate Spellcasting"
description into a structured `Compendium.Spellcasting` record.

Real-world descriptions arrive in three shapes:

  - **Bulleted, markdown-bold** (2024 MM via 5e-tools):

        ...(spell save DC 17):

          - **At Will:** Detect Magic
          - **2/Day Each:** Wind Walk
          - **1/Day Each:** Plane Shift

  - **Bulleted, plain text** (older 5e):

          - Cantrips (at will): fire bolt, light
          - 1st level (4 slots): magic missile
          - 2nd level (3 slots): misty step

  - **Run-on, no delimiters at all** (some D&D Beyond pastes):

        ...(spell save DC 16): At Will: Detect Magic,
        Detect Thoughts, Mage Hand, Major Image
        1/Day Each: Blight, Cloudkill, Fly, Plane Shift

The old bullet-split approach broke on the run-on shape — there
was no delimiter to split on and everything landed as one blob.
This module instead **scans the description for label positions
directly** (`at will:`, `N/day each:`, `Nst level (M slots):`,
`cantrips (at will):`) and slices the spell text between each
label's colon and the next label's start. Comma splitting is
paren-aware so spell notes like `Invisibility (self only)` or
`Compulsion (concentration, up to 1 minute)` survive intact.

Meta (ability, save DC, spell attack bonus) is scraped out of
whatever prose sits before the first label so the stat-block
header still reads correctly.

@docs parse

-}

import Compendium exposing (Ability(..), InnatePerDay, SpellSlotLevel, Spellcasting)



-- ── Entry ────────────────────────────────────────────────────────


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

        lower =
            String.toLower cleaned

        hits =
            allHits lower
                |> List.sortBy .start
                |> dedupOverlapping

        groups =
            hits
                |> withSpellRanges (String.length cleaned)
                |> List.filterMap (buildGroup cleaned)

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
            { description = summariseDescription cleaned (List.head hits |> Maybe.map .start)
            , ability = extractAbility cleaned |> Maybe.withDefault Cha
            , saveDc = extractSaveDc cleaned |> Maybe.withDefault 0
            , attackBonus = extractAttackBonus cleaned |> Maybe.withDefault 0
            , atWill = atWill
            , slots = slots
            , innatePerDay = innate
            }



-- ── Label scanning ───────────────────────────────────────────────


{-| A recognised spell-group label. `start` is where the label
text begins in the source string (used to bound the previous
group's spell range) and `labelEnd` is the position **after**
the trailing colon (where the spell list starts).
-}
type alias Hit =
    { start : Int
    , labelEnd : Int
    , kind : LabelKind
    }


type LabelKind
    = KAtWill
    | KSlot Int Int
    | KInnate Int


allHits : String -> List Hit
allHits lower =
    List.concat
        [ atWillHits lower
        , cantripHits lower
        , slotHits lower
        , innateHits lower
        ]


{-| Find every `at will:` occurrence — but skip matches that
sit inside `cantrips (at will):` so we don't emit two hits for
one label.
-}
atWillHits : String -> List Hit
atWillHits lower =
    let
        term =
            "at will"

        termLen =
            String.length term
    in
    String.indexes term lower
        |> List.filterMap
            (\i ->
                if precededBy "cantrips (" lower i then
                    Nothing

                else
                    findColonSkippingSpaces lower (i + termLen)
                        |> Maybe.map
                            (\cpos ->
                                { start = i, labelEnd = cpos + 1, kind = KAtWill }
                            )
            )


{-| Recognise `Cantrips:` and `Cantrips (at will):` as a
0th-level slot group so the display path renders them as
"Cantrips (at will)" uniformly.
-}
cantripHits : String -> List Hit
cantripHits lower =
    let
        term =
            "cantrips"

        termLen =
            String.length term
    in
    String.indexes term lower
        |> List.filterMap
            (\i ->
                let
                    after =
                        i + termLen
                in
                case cantripLabelEnd lower after of
                    Just e ->
                        Just { start = i, labelEnd = e, kind = KSlot 0 0 }

                    Nothing ->
                        Nothing
            )


cantripLabelEnd : String -> Int -> Maybe Int
cantripLabelEnd lower pos =
    case firstColonAt lower pos of
        Just cpos ->
            Just (cpos + 1)

        Nothing ->
            let
                parenSuffix =
                    " (at will)"
            in
            if String.slice pos (pos + String.length parenSuffix) lower == parenSuffix then
                case firstColonAt lower (pos + String.length parenSuffix) of
                    Just cpos ->
                        Just (cpos + 1)

                    Nothing ->
                        Nothing

            else
                Nothing


{-| Recognise `Nst level (M slot(s)):` — the classic 5e
prepared-caster shape. We match on the fixed " level ("
substring, then walk back for the ordinal + level digits and
forward for the slot count.

Requires the space before `level` so we don't accidentally match
`Blight (level 8 version)` in a spell name, where the parenthesis
sits **before** the word rather than after it.

-}
slotHits : String -> List Hit
slotHits lower =
    let
        term =
            " level ("
    in
    String.indexes term lower
        |> List.filterMap (parseSlotHit lower (String.length term))


parseSlotHit : String -> Int -> Int -> Maybe Hit
parseSlotHit lower termLen levelIdx =
    let
        ordinalEnd =
            levelIdx

        ordinalStart =
            ordinalEnd - 2
    in
    if ordinalStart < 1 then
        Nothing

    else
        let
            ordinal =
                String.slice ordinalStart ordinalEnd lower
        in
        if isOrdinalMarker ordinal then
            let
                digitEnd =
                    ordinalStart

                digitStart =
                    walkBackDigits lower digitEnd
            in
            if digitStart == digitEnd then
                Nothing

            else
                case String.toInt (String.slice digitStart digitEnd lower) of
                    Just lv ->
                        slotBodyAndColon lower (levelIdx + termLen) digitStart lv

                    Nothing ->
                        Nothing

        else
            Nothing


isOrdinalMarker : String -> Bool
isOrdinalMarker s =
    s == "st" || s == "nd" || s == "rd" || s == "th"


slotBodyAndColon : String -> Int -> Int -> Int -> Maybe Hit
slotBodyAndColon lower afterOpenParen labelStart level =
    let
        digitEnd =
            walkForwardDigits lower afterOpenParen
    in
    if digitEnd == afterOpenParen then
        Nothing

    else
        case String.toInt (String.slice afterOpenParen digitEnd lower) of
            Just slots ->
                findFirstIndex ")" lower digitEnd
                    |> Maybe.andThen (\pcpos -> firstColonAt lower (pcpos + 1))
                    |> Maybe.map
                        (\cpos ->
                            { start = labelStart
                            , labelEnd = cpos + 1
                            , kind = KSlot level slots
                            }
                        )

            Nothing ->
                Nothing


{-| Recognise `N/day` and `N/day each` — the innate spellcasting
per-day pool. Both variants map to the same InnatePerDay
structure since the wire format doesn't distinguish them.
-}
innateHits : String -> List Hit
innateHits lower =
    let
        term =
            "/day"

        termLen =
            String.length term
    in
    String.indexes term lower
        |> List.filterMap (parseInnateHit lower termLen)


parseInnateHit : String -> Int -> Int -> Maybe Hit
parseInnateHit lower termLen dayIdx =
    let
        digitEnd =
            dayIdx

        digitStart =
            walkBackDigits lower digitEnd
    in
    if digitStart == digitEnd then
        Nothing

    else
        case String.toInt (String.slice digitStart digitEnd lower) of
            Just uses ->
                let
                    afterDay =
                        dayIdx + termLen

                    eachTag =
                        " each"

                    withEach =
                        String.slice afterDay (afterDay + String.length eachTag) lower == eachTag

                    afterOptEach =
                        if withEach then
                            afterDay + String.length eachTag

                        else
                            afterDay
                in
                firstColonAt lower afterOptEach
                    |> Maybe.map
                        (\cpos ->
                            { start = digitStart
                            , labelEnd = cpos + 1
                            , kind = KInnate uses
                            }
                        )

            Nothing ->
                Nothing



-- ── Post-scan grouping ───────────────────────────────────────────


{-| After sorting hits by `.start`, drop any hit whose start
falls **inside** a previously-kept hit's label range. Guards
against `at will` matching inside `cantrips (at will):`, and
against a stray `/day` inside another label's spell body being
misread as a new group.
-}
dedupOverlapping : List Hit -> List Hit
dedupOverlapping hits =
    let
        walk seen remaining =
            case remaining of
                [] ->
                    List.reverse seen

                h :: rest ->
                    let
                        overlapsWithSeen =
                            List.any
                                (\s ->
                                    h.start >= s.start && h.start < s.labelEnd
                                )
                                seen
                    in
                    if overlapsWithSeen then
                        walk seen rest

                    else
                        walk (h :: seen) rest
    in
    walk [] hits


{-| Pair each hit with the position at which its spell list ends
— which is the next hit's `.start`, or the end of the string
for the final hit.
-}
withSpellRanges : Int -> List Hit -> List ( Hit, Int )
withSpellRanges totalLen hits =
    let
        starts =
            List.map .start (List.drop 1 hits) ++ [ totalLen ]
    in
    List.map2 Tuple.pair hits starts


buildGroup : String -> ( Hit, Int ) -> Maybe Group
buildGroup cleaned ( hit, spellsEnd ) =
    let
        rawSpells =
            String.slice hit.labelEnd spellsEnd cleaned

        spells =
            parseSpells rawSpells
    in
    if List.isEmpty spells then
        Nothing

    else
        case hit.kind of
            KAtWill ->
                Just (GroupAtWill spells)

            KSlot level slots ->
                Just (GroupSlot { level = level, slots = slots, spells = spells })

            KInnate uses ->
                Just (GroupInnate { uses = uses, spells = spells })


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



-- ── Spell list parsing (paren-aware) ─────────────────────────────


{-| Split on commas that sit at paren-depth zero, trim, drop
empties. Trailing bullet markers and terminal punctuation are
stripped so run-on descriptions ending with "..., Tongues." or
"..., Fly -" don't leave stray characters on the last spell.
-}
parseSpells : String -> List String
parseSpells raw =
    raw
        |> String.replace "*" ""
        |> parenAwareCommaSplit
        |> List.map String.trim
        |> List.map stripTrailingJunk
        |> List.filter (not << String.isEmpty)


{-| Fold across the string tracking parenthesis depth; only
break on commas that occur at depth zero. Keeps spell notes
like `Invisibility (self only)` and `Compulsion (concentration,
up to 1 minute)` intact.
-}
parenAwareCommaSplit : String -> List String
parenAwareCommaSplit s =
    let
        step ch ( depth, current, acc ) =
            if ch == '(' then
                ( depth + 1, String.cons ch current, acc )

            else if ch == ')' then
                ( max 0 (depth - 1), String.cons ch current, acc )

            else if ch == ',' && depth == 0 then
                ( depth, "", String.reverse current :: acc )

            else
                ( depth, String.cons ch current, acc )

        ( _, tail, done ) =
            String.foldl step ( 0, "", [] ) s
    in
    List.reverse (String.reverse tail :: done)


{-| Iteratively strip trailing whitespace then trailing `-` or
`.` off a spell name. Some descriptions leave a bullet-marker
tail on the last spell of a group ("…, Acid Arrow\\n- **1/Day
Each:**…"): after slicing, the last entry lands as `Acid
Arrow\n-`, which HTML whitespace-collapse renders as
"Acid Arrow -". Trimming right, dropping the trailing `-`,
and re-trimming eats the newline too so the spell reads
cleanly as "Acid Arrow".

We only strip `-` and `.` — the two junk characters real
spells never end with — so a spell name like "1st-level
Chuck" (hypothetical) isn't over-stripped.

-}
stripTrailingJunk : String -> String
stripTrailingJunk s =
    let
        stripped =
            String.trimRight s
    in
    case String.right 1 stripped of
        "-" ->
            stripTrailingJunk (String.dropRight 1 stripped)

        "." ->
            stripTrailingJunk (String.dropRight 1 stripped)

        _ ->
            stripped



-- ── Meta extraction (ability / DC / attack bonus) ────────────────


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


{-| Trim the description down to the prose that comes **before**
the first spell label. That leading sentence — "The X casts...
using Charisma..." — gives the statblock view its context.
-}
summariseDescription : String -> Maybe Int -> String
summariseDescription cleaned firstLabelStart =
    case firstLabelStart of
        Just idx ->
            String.left idx cleaned
                |> stripTrailingLabelPreamble

        Nothing ->
            String.trim cleaned


stripTrailingLabelPreamble : String -> String
stripTrailingLabelPreamble s =
    -- Drop the trailing colon + any preceding "as the spellcasting ability
    -- (spell save DC N):" chunk so the preserved description reads as a
    -- clean sentence rather than trailing off mid-phrase.
    s
        |> String.trim
        |> chopAtLastOccurrence ":"


chopAtLastOccurrence : String -> String -> String
chopAtLastOccurrence needle haystack =
    let
        indexes =
            String.indexes needle haystack
    in
    case List.reverse indexes of
        idx :: _ ->
            String.left idx haystack |> String.trim

        [] ->
            haystack



-- ── Low-level scanning helpers ───────────────────────────────────


{-| Check whether the substring `prefix` ends exactly at
position `i` in `s`. Used to detect that an `at will` hit is
inside `cantrips (at will):` and should be skipped.
-}
precededBy : String -> String -> Int -> Bool
precededBy prefix s i =
    let
        pstart =
            i - String.length prefix
    in
    pstart >= 0 && String.slice pstart i s == prefix


{-| Find the next `:` starting at `pos`, skipping over any
zero-or-more space / tab characters. Returns `Nothing` if the
first non-whitespace char isn't a colon — meaning the label
we're scanning didn't actually have a colon after it.
-}
firstColonAt : String -> Int -> Maybe Int
firstColonAt s pos =
    let
        len =
            String.length s
    in
    if pos >= len then
        Nothing

    else
        let
            c =
                String.slice pos (pos + 1) s
        in
        if c == ":" then
            Just pos

        else if c == " " || c == "\t" then
            firstColonAt s (pos + 1)

        else
            Nothing


findColonSkippingSpaces : String -> Int -> Maybe Int
findColonSkippingSpaces =
    firstColonAt


findFirstIndex : String -> String -> Int -> Maybe Int
findFirstIndex needle haystack fromPos =
    String.indexes needle (String.dropLeft fromPos haystack)
        |> List.head
        |> Maybe.map (\i -> i + fromPos)


walkBackDigits : String -> Int -> Int
walkBackDigits s end =
    if end == 0 then
        0

    else
        let
            c =
                String.slice (end - 1) end s
        in
        if isDigitString c then
            walkBackDigits s (end - 1)

        else
            end


walkForwardDigits : String -> Int -> Int
walkForwardDigits s start =
    let
        len =
            String.length s
    in
    if start >= len then
        start

    else
        let
            c =
                String.slice start (start + 1) s
        in
        if isDigitString c then
            walkForwardDigits s (start + 1)

        else
            start


isDigitString : String -> Bool
isDigitString s =
    case String.uncons s of
        Just ( ch, _ ) ->
            Char.isDigit ch

        Nothing ->
            False


firstIntAfter : String -> String -> Maybe Int
firstIntAfter marker haystack =
    case String.indexes marker haystack of
        [] ->
            Nothing

        idx :: _ ->
            let
                tail =
                    String.dropLeft (idx + String.length marker) haystack
            in
            tail
                |> String.toList
                |> dropUntil Char.isDigit
                |> takeWhileChars Char.isDigit
                |> String.fromList
                |> String.toInt


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
