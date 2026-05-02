module Compendium.Parser exposing (ParseError(..), parseStatBlock)

{-| Permissive line-based parser for plain-text 5e stat blocks.

Targets the canonical SRD / D&D Beyond / Roll20 export shape:

    Creature Name
    Size race (subrace), alignment
    Armor Class N (note)
    Hit Points N (formula)
    Speed N ft., fly N ft. (hover)
    STR N (+M) DEX N (+M) CON N (+M) INT N (+M) WIS N (+M) CHA N (+M)
    Saving Throws Str +N, Dex +N
    Skills Perception +N, Stealth +N
    Damage Vulnerabilities ...
    Damage Resistances ...
    Damage Immunities ...
    Condition Immunities ...
    Senses blindsight N ft., darkvision N ft., passive Perception N
    Languages Common, Draconic
    Challenge N (XP)
    Proficiency Bonus +N
    Trait Name. Body of the trait...
    Actions
    Action Name. Body...

Empty / blank lines are dropped before walking. Lines we don't
recognize are appended to the body of the previous feature so
multi-line traits and actions stay coherent.

Out of MVP scope (silently ignored — the GM can re-add manually):

  - Two-line ability table (header row + values row)
  - Spellcasting slot lines and innate-per-day breakdowns
  - Lair-action initiative ("On initiative count 20…")
  - Legendary-action preamble ("The dragon can take 3…")

These are kept as text in `customSections` if encountered, so
nothing is lost — they just don't get structured.

@docs ParseError, parseStatBlock

-}

import Compendium


{-| Errors the parser surfaces. The two early-failure cases catch
empty input and a missing first line; everything else is permissive
and falls through to "best-effort" parsing.
-}
type ParseError
    = EmptyInput
    | MissingHeader



-- ── ENTRY ────────────────────────────────────────────────────────────────────


parseStatBlock : String -> Result ParseError Compendium.Creature
parseStatBlock raw =
    case nonEmptyLines raw of
        [] ->
            Err EmptyInput

        [ _ ] ->
            Err MissingHeader

        name :: typeLine :: rest ->
            initialState name typeLine
                |> walk rest
                |> commitFeature
                |> .creature
                |> Ok


nonEmptyLines : String -> List String
nonEmptyLines raw =
    raw
        |> String.lines
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)



-- ── STATE ────────────────────────────────────────────────────────────────────


type alias State =
    { creature : Compendium.Creature
    , section : Section
    , pending : Maybe PendingFeature
    }


type Section
    = TraitsSection
    | ActionsSection
    | BonusActionsSection
    | ReactionsSection
    | LegendarySection
    | LairSection
    | RegionalSection
    | SpellcastingSection
    | OtherSection String


type alias PendingFeature =
    { section : Section
    , name : String
    , body : List String
    }


initialState : String -> String -> State
initialState name typeLine =
    let
        meta =
            parseTypeLine typeLine
    in
    { creature =
        { id = ""
        , name = name
        , kind = inferKind name meta.race
        , size = meta.size
        , race = meta.race
        , subrace = meta.subrace
        , alignment = meta.alignment
        , source = "Pasted"
        , description = ""
        , armorClass = 10
        , armorClassNote = ""
        , maxHp = 1
        , hpFormula = ""
        , initiativeBonus = 0
        , speed = defaultSpeed
        , abilities = defaultAbilities
        , savingThrows = []
        , skills = []
        , damageVulnerabilities = []
        , damageResistances = []
        , damageImmunities = []
        , conditionImmunities = []
        , senses = defaultSenses
        , languages = []
        , challengeRating = ""
        , xp = 0
        , proficiencyBonus = 2
        , traits = []
        , actions = []
        , bonusActions = []
        , reactions = []
        , legendaryActions = Nothing
        , lairActions = Nothing
        , regionalEffects = Nothing
        , spellcasting = Nothing
        , customSections = []
        , createdAt = 0
        , updatedAt = 0
        }
    , section = TraitsSection
    , pending = Nothing
    }


defaultSpeed : Compendium.Speed
defaultSpeed =
    { walk = 0, fly = 0, swim = 0, climb = 0, burrow = 0, hover = False }


defaultAbilities : Compendium.Abilities
defaultAbilities =
    { str = 10, dex = 10, con = 10, int = 10, wis = 10, cha = 10 }


defaultSenses : Compendium.Senses
defaultSenses =
    { blindsight = 0
    , darkvision = 0
    , tremorsense = 0
    , truesight = 0
    , passivePerception = 10
    }


{-| Light-touch heuristic: PCs almost always have a class somewhere
in the type line (e.g. "rogue, lvl 5"), and the rest are enemies
unless the type line says NPC explicitly. Players can flip the
field in the edit form afterward.
-}
inferKind : String -> String -> Compendium.CreatureKind
inferKind nameLine raceLine =
    let
        haystack =
            String.toLower (nameLine ++ " " ++ raceLine)
    in
    if String.contains "(pc)" haystack || String.contains "lvl" haystack || String.contains "level " haystack then
        Compendium.Player

    else if String.contains "npc" haystack then
        Compendium.Npc

    else
        Compendium.Enemy



-- ── WALK ─────────────────────────────────────────────────────────────────────


walk : List String -> State -> State
walk lines state =
    case lines of
        [] ->
            state

        line :: rest ->
            walk rest (handleLine line state)


handleLine : String -> State -> State
handleLine line state =
    case classifyLine line of
        LineArmorClass ac note ->
            withCreature
                (\c -> { c | armorClass = ac, armorClassNote = note })
                (commitFeature state)

        LineHitPoints hp formula ->
            withCreature
                (\c -> { c | maxHp = hp, hpFormula = formula })
                (commitFeature state)

        LineSpeed speed ->
            withCreature (\c -> { c | speed = speed }) (commitFeature state)

        LineAbilities abs_ ->
            withCreature (\c -> { c | abilities = abs_ }) (commitFeature state)

        LineSaves saves ->
            withCreature (\c -> { c | savingThrows = saves }) (commitFeature state)

        LineSkills skills ->
            withCreature (\c -> { c | skills = skills }) (commitFeature state)

        LineDamageVulnerabilities vs ->
            withCreature (\c -> { c | damageVulnerabilities = vs }) (commitFeature state)

        LineDamageResistances vs ->
            withCreature (\c -> { c | damageResistances = vs }) (commitFeature state)

        LineDamageImmunities vs ->
            withCreature (\c -> { c | damageImmunities = vs }) (commitFeature state)

        LineConditionImmunities vs ->
            withCreature (\c -> { c | conditionImmunities = vs }) (commitFeature state)

        LineSenses senses ->
            withCreature (\c -> { c | senses = senses }) (commitFeature state)

        LineLanguages langs ->
            withCreature (\c -> { c | languages = langs }) (commitFeature state)

        LineChallenge cr xp ->
            withCreature
                (\c -> { c | challengeRating = cr, xp = xp })
                (commitFeature state)

        LineProficiencyBonus pb ->
            withCreature (\c -> { c | proficiencyBonus = pb }) (commitFeature state)

        LineSectionHeader section ->
            -- Commit FIRST so the pending feature lands in the
            -- previous section, then switch.
            let
                committed =
                    commitFeature state
            in
            { committed | section = section }

        LineFeatureStart name body ->
            commitFeature state
                |> startFeature name body

        LineContinuation body ->
            extendFeature body state


withCreature : (Compendium.Creature -> Compendium.Creature) -> State -> State
withCreature fn state =
    { state | creature = fn state.creature }


startFeature : String -> String -> State -> State
startFeature name body state =
    { state
        | pending =
            Just
                { section = state.section
                , name = name
                , body =
                    if String.isEmpty body then
                        []

                    else
                        [ body ]
                }
    }


extendFeature : String -> State -> State
extendFeature body state =
    case state.pending of
        Nothing ->
            -- No active feature; treat as preamble for the current
            -- section (legendary preamble, etc.). Park it in
            -- customSections under the section's name so nothing
            -- is silently dropped.
            withCreature (parkPreamble state.section body) state

        Just p ->
            { state | pending = Just { p | body = p.body ++ [ body ] } }


parkPreamble : Section -> String -> Compendium.Creature -> Compendium.Creature
parkPreamble section body c =
    let
        heading =
            sectionLabel section ++ " (preamble)"
    in
    { c | customSections = c.customSections ++ [ { name = heading, body = body } ] }


commitFeature : State -> State
commitFeature state =
    case state.pending of
        Nothing ->
            state

        Just p ->
            let
                feature =
                    { name = p.name
                    , description = String.join " " p.body
                    , usage = Nothing
                    }
            in
            { state
                | pending = Nothing
                , creature = appendFeature p.section feature state.creature
            }


appendFeature : Section -> Compendium.Feature -> Compendium.Creature -> Compendium.Creature
appendFeature section feature c =
    case section of
        TraitsSection ->
            { c | traits = c.traits ++ [ feature ] }

        ActionsSection ->
            { c | actions = c.actions ++ [ feature ] }

        BonusActionsSection ->
            { c | bonusActions = c.bonusActions ++ [ feature ] }

        ReactionsSection ->
            { c | reactions = c.reactions ++ [ feature ] }

        LegendarySection ->
            { c
                | legendaryActions =
                    Just
                        (case c.legendaryActions of
                            Just la ->
                                { la | options = la.options ++ [ legendaryOptionFromFeature feature ] }

                            Nothing ->
                                { description = ""
                                , uses = 3
                                , usesInLair = 0
                                , options = [ legendaryOptionFromFeature feature ]
                                }
                        )
            }

        LairSection ->
            { c
                | lairActions =
                    Just
                        (case c.lairActions of
                            Just la ->
                                { la | options = la.options ++ [ feature ] }

                            Nothing ->
                                { initiative = 20
                                , description = ""
                                , options = [ feature ]
                                }
                        )
            }

        RegionalSection ->
            { c
                | regionalEffects =
                    Just
                        (case c.regionalEffects of
                            Just re ->
                                { re | effects = re.effects ++ [ feature ] }

                            Nothing ->
                                { description = ""
                                , effects = [ feature ]
                                , fadeAfter = ""
                                }
                        )
            }

        SpellcastingSection ->
            -- Spellcasting needs structured slot parsing we don't do
            -- yet. Park as a custom section so the data is preserved.
            { c
                | customSections =
                    c.customSections
                        ++ [ { name = "Spellcasting: " ++ feature.name
                             , body = feature.description
                             }
                           ]
            }

        OtherSection heading ->
            { c
                | customSections =
                    c.customSections
                        ++ [ { name = heading ++ ": " ++ feature.name
                             , body = feature.description
                             }
                           ]
            }


legendaryOptionFromFeature : Compendium.Feature -> Compendium.LegendaryOption
legendaryOptionFromFeature f =
    { name = f.name, cost = 1, description = f.description }


sectionLabel : Section -> String
sectionLabel section =
    case section of
        TraitsSection ->
            "Traits"

        ActionsSection ->
            "Actions"

        BonusActionsSection ->
            "Bonus Actions"

        ReactionsSection ->
            "Reactions"

        LegendarySection ->
            "Legendary Actions"

        LairSection ->
            "Lair Actions"

        RegionalSection ->
            "Regional Effects"

        SpellcastingSection ->
            "Spellcasting"

        OtherSection s ->
            s



-- ── LINE CLASSIFICATION ──────────────────────────────────────────────────────


type Line
    = LineArmorClass Int String
    | LineHitPoints Int String
    | LineSpeed Compendium.Speed
    | LineAbilities Compendium.Abilities
    | LineSaves (List Compendium.AbilitySave)
    | LineSkills (List Compendium.SkillBonus)
    | LineDamageVulnerabilities (List String)
    | LineDamageResistances (List String)
    | LineDamageImmunities (List String)
    | LineConditionImmunities (List String)
    | LineSenses Compendium.Senses
    | LineLanguages (List String)
    | LineChallenge String Int
    | LineProficiencyBonus Int
    | LineSectionHeader Section
    | LineFeatureStart String String
    | LineContinuation String


classifyLine : String -> Line
classifyLine line =
    let
        lower =
            String.toLower line
    in
    case stripPrefix "armor class " lower of
        Just rest ->
            parseArmorClass (sliceRest line "armor class " rest)

        Nothing ->
            case stripPrefix "hit points " lower of
                Just _ ->
                    parseHitPoints (sliceRest line "hit points " "")

                Nothing ->
                    case stripPrefix "speed " lower of
                        Just _ ->
                            LineSpeed (parseSpeed (sliceRest line "speed " ""))

                        Nothing ->
                            classifyAfterCore line lower


classifyAfterCore : String -> String -> Line
classifyAfterCore line lower =
    case stripPrefix "saving throws " lower of
        Just _ ->
            LineSaves (parseSaves (sliceRest line "saving throws " ""))

        Nothing ->
            case stripPrefix "skills " lower of
                Just _ ->
                    LineSkills (parseSkills (sliceRest line "skills " ""))

                Nothing ->
                    case stripPrefix "damage vulnerabilities " lower of
                        Just _ ->
                            LineDamageVulnerabilities (parseCsv (sliceRest line "damage vulnerabilities " ""))

                        Nothing ->
                            case stripPrefix "damage resistances " lower of
                                Just _ ->
                                    LineDamageResistances (parseCsv (sliceRest line "damage resistances " ""))

                                Nothing ->
                                    classifyAfterDamage line lower


classifyAfterDamage : String -> String -> Line
classifyAfterDamage line lower =
    case stripPrefix "damage immunities " lower of
        Just _ ->
            LineDamageImmunities (parseCsv (sliceRest line "damage immunities " ""))

        Nothing ->
            case stripPrefix "condition immunities " lower of
                Just _ ->
                    LineConditionImmunities (parseCsv (sliceRest line "condition immunities " ""))

                Nothing ->
                    case stripPrefix "senses " lower of
                        Just _ ->
                            LineSenses (parseSenses (sliceRest line "senses " ""))

                        Nothing ->
                            case stripPrefix "languages " lower of
                                Just _ ->
                                    LineLanguages (parseCsv (sliceRest line "languages " ""))

                                Nothing ->
                                    classifyAfterMeta line lower


classifyAfterMeta : String -> String -> Line
classifyAfterMeta line lower =
    case stripPrefix "challenge " lower of
        Just _ ->
            parseChallenge (sliceRest line "challenge " "")

        Nothing ->
            case stripPrefix "proficiency bonus " lower of
                Just _ ->
                    LineProficiencyBonus (parseSignedInt (sliceRest line "proficiency bonus " ""))

                Nothing ->
                    case parseAbilityLine line of
                        Just abs_ ->
                            LineAbilities abs_

                        Nothing ->
                            classifySection line lower


classifySection : String -> String -> Line
classifySection line lower =
    case lower of
        "actions" ->
            LineSectionHeader ActionsSection

        "bonus actions" ->
            LineSectionHeader BonusActionsSection

        "reactions" ->
            LineSectionHeader ReactionsSection

        "legendary actions" ->
            LineSectionHeader LegendarySection

        "lair actions" ->
            LineSectionHeader LairSection

        "regional effects" ->
            LineSectionHeader RegionalSection

        "spellcasting" ->
            LineSectionHeader SpellcastingSection

        _ ->
            -- Try to parse as "Name. Body" feature-start; fall
            -- back to a continuation of the current feature.
            case splitFeatureStart line of
                Just ( name, body ) ->
                    LineFeatureStart name body

                Nothing ->
                    LineContinuation line



-- ── PARSE HELPERS ────────────────────────────────────────────────────────────


sliceRest : String -> String -> String -> String
sliceRest original prefix _ =
    String.dropLeft (String.length prefix) original


stripPrefix : String -> String -> Maybe String
stripPrefix prefix haystack =
    if String.startsWith prefix haystack then
        Just (String.dropLeft (String.length prefix) haystack)

    else
        Nothing


{-| `Armor Class 15 (leather armor, shield)` → AC 15, note "leather armor, shield".
The number is the first run of digits; the parens (if present) are the note.
-}
parseArmorClass : String -> Line
parseArmorClass raw =
    let
        ( numText, afterNum ) =
            takeLeading isDigit raw

        ac =
            String.toInt numText |> Maybe.withDefault 10

        note =
            extractParens afterNum
    in
    LineArmorClass ac note


parseHitPoints : String -> Line
parseHitPoints raw =
    let
        ( numText, afterNum ) =
            takeLeading isDigit raw

        hp =
            String.toInt numText |> Maybe.withDefault 1

        formula =
            extractParens afterNum
    in
    LineHitPoints hp formula


extractParens : String -> String
extractParens raw =
    case String.indexes "(" raw of
        first :: _ ->
            case String.indexes ")" raw of
                last :: _ ->
                    if last > first then
                        String.slice (first + 1) last raw
                            |> String.trim

                    else
                        ""

                [] ->
                    ""

        [] ->
            ""


takeLeading : (Char -> Bool) -> String -> ( String, String )
takeLeading pred raw =
    let
        trimmed =
            String.trimLeft raw

        chars =
            String.toList trimmed

        ( taken, rest ) =
            splitWhile pred chars
    in
    ( String.fromList taken, String.fromList rest )


splitWhile : (a -> Bool) -> List a -> ( List a, List a )
splitWhile pred xs =
    case xs of
        [] ->
            ( [], [] )

        x :: rest ->
            if pred x then
                let
                    ( taken, remaining ) =
                        splitWhile pred rest
                in
                ( x :: taken, remaining )

            else
                ( [], xs )


isDigit : Char -> Bool
isDigit c =
    Char.isDigit c



-- Speed: "30 ft., fly 60 ft. (hover), swim 40 ft."


parseSpeed : String -> Compendium.Speed
parseSpeed raw =
    let
        segments =
            String.split "," raw |> List.map String.trim
    in
    List.foldl applySpeedSegment defaultSpeed segments


applySpeedSegment : String -> Compendium.Speed -> Compendium.Speed
applySpeedSegment segment speed =
    let
        lower =
            String.toLower segment

        n =
            firstInt segment

        hover =
            String.contains "hover" lower
    in
    if String.startsWith "fly" lower then
        { speed | fly = n, hover = speed.hover || hover }

    else if String.startsWith "swim" lower then
        { speed | swim = n }

    else if String.startsWith "climb" lower then
        { speed | climb = n }

    else if String.startsWith "burrow" lower then
        { speed | burrow = n }

    else
        -- Bare number is walk speed (the canonical first segment).
        { speed | walk = n }


firstInt : String -> Int
firstInt raw =
    raw
        |> String.toList
        |> dropUntil Char.isDigit
        |> takeWhileChars Char.isDigit
        |> String.fromList
        |> String.toInt
        |> Maybe.withDefault 0


dropUntil : (a -> Bool) -> List a -> List a
dropUntil pred xs =
    case xs of
        [] ->
            []

        x :: rest ->
            if pred x then
                xs

            else
                dropUntil pred rest


takeWhileChars : (a -> Bool) -> List a -> List a
takeWhileChars pred xs =
    case xs of
        [] ->
            []

        x :: rest ->
            if pred x then
                x :: takeWhileChars pred rest

            else
                []



-- Abilities: "STR 8 (-1) DEX 14 (+2) CON 10 (+0) INT 10 (+0) WIS 8 (-1) CHA 8 (-1)"


parseAbilityLine : String -> Maybe Compendium.Abilities
parseAbilityLine line =
    let
        upper =
            String.toUpper line

        hasAll =
            List.all (\label -> String.contains label upper)
                [ "STR", "DEX", "CON", "INT", "WIS", "CHA" ]
    in
    if hasAll then
        Just
            { str = abilityScoreAfter "STR" upper
            , dex = abilityScoreAfter "DEX" upper
            , con = abilityScoreAfter "CON" upper
            , int = abilityScoreAfter "INT" upper
            , wis = abilityScoreAfter "WIS" upper
            , cha = abilityScoreAfter "CHA" upper
            }

    else
        Nothing


abilityScoreAfter : String -> String -> Int
abilityScoreAfter label haystack =
    case String.indexes label haystack of
        i :: _ ->
            haystack
                |> String.dropLeft (i + String.length label)
                |> firstInt

        [] ->
            10



-- Saves / Skills


parseSaves : String -> List Compendium.AbilitySave
parseSaves raw =
    String.split "," raw
        |> List.map String.trim
        |> List.filterMap parseSaveSegment


parseSaveSegment : String -> Maybe Compendium.AbilitySave
parseSaveSegment segment =
    -- "Str +5" or "Dex+3" — find the sign, parse the number after it.
    let
        normalized =
            segment
                |> String.replace "+" " +"
                |> String.replace "-" " -"
                |> String.split " "
                |> List.filter (not << String.isEmpty)
    in
    case normalized of
        [ abilityRaw, bonusRaw ] ->
            Maybe.map2 Compendium.AbilitySave
                (abilityFromAbbrev abilityRaw)
                (Just (parseSignedInt bonusRaw))

        _ ->
            Nothing


abilityFromAbbrev : String -> Maybe Compendium.Ability
abilityFromAbbrev raw =
    case String.toLower (String.left 3 raw) of
        "str" ->
            Just Compendium.Str

        "dex" ->
            Just Compendium.Dex

        "con" ->
            Just Compendium.Con

        "int" ->
            Just Compendium.Int_

        "wis" ->
            Just Compendium.Wis

        "cha" ->
            Just Compendium.Cha

        _ ->
            Nothing


parseSkills : String -> List Compendium.SkillBonus
parseSkills raw =
    String.split "," raw
        |> List.map String.trim
        |> List.filterMap parseSkillSegment


parseSkillSegment : String -> Maybe Compendium.SkillBonus
parseSkillSegment segment =
    -- "Stealth +6" — last whitespace-separated token is "+N",
    -- everything before is the name.
    let
        words =
            String.words segment

        lastWord =
            List.head (List.reverse words)
    in
    case lastWord of
        Just bonusRaw ->
            if String.startsWith "+" bonusRaw || String.startsWith "-" bonusRaw then
                let
                    nameWords =
                        List.take (List.length words - 1) words

                    name =
                        String.join " " nameWords
                in
                if String.isEmpty name then
                    Nothing

                else
                    Just
                        { name = name
                        , bonus = parseSignedInt bonusRaw
                        }

            else
                Nothing

        Nothing ->
            Nothing


parseSignedInt : String -> Int
parseSignedInt raw =
    let
        trimmed =
            String.trim raw
    in
    case String.uncons trimmed of
        Just ( '+', rest ) ->
            String.toInt rest |> Maybe.withDefault 0

        Just ( '-', rest ) ->
            String.toInt rest |> Maybe.map negate |> Maybe.withDefault 0

        _ ->
            String.toInt trimmed |> Maybe.withDefault 0


parseCsv : String -> List String
parseCsv raw =
    raw
        |> String.split ","
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)



-- Senses: "blindsight 60 ft., darkvision 60 ft., passive Perception 12"


parseSenses : String -> Compendium.Senses
parseSenses raw =
    let
        segments =
            String.split "," raw |> List.map String.trim
    in
    List.foldl applySensesSegment defaultSenses segments


applySensesSegment : String -> Compendium.Senses -> Compendium.Senses
applySensesSegment segment senses =
    let
        lower =
            String.toLower segment

        n =
            firstInt segment
    in
    if String.startsWith "blindsight" lower then
        { senses | blindsight = n }

    else if String.startsWith "darkvision" lower then
        { senses | darkvision = n }

    else if String.startsWith "tremorsense" lower then
        { senses | tremorsense = n }

    else if String.startsWith "truesight" lower then
        { senses | truesight = n }

    else if String.contains "passive perception" lower then
        { senses | passivePerception = n }

    else
        senses



-- Challenge: "1/4 (50 XP)" or "12 (8,400 XP)"


parseChallenge : String -> Line
parseChallenge raw =
    let
        crText =
            raw
                |> String.split "("
                |> List.head
                |> Maybe.withDefault raw
                |> String.trim

        xp =
            extractXp raw
    in
    LineChallenge crText xp


extractXp : String -> Int
extractXp raw =
    -- Looking for "12,345 XP" or "50 XP" inside parens. Strip
    -- commas before parsing.
    case String.indexes "(" raw of
        first :: _ ->
            case String.indexes ")" raw of
                last :: _ ->
                    if last > first then
                        String.slice (first + 1) last raw
                            |> String.replace "," ""
                            |> firstInt

                    else
                        0

                [] ->
                    0

        [] ->
            0



-- Type line: "Large dragon (chromatic), chaotic evil"


parseTypeLine : String -> { size : Compendium.Size, race : String, subrace : String, alignment : String }
parseTypeLine line =
    let
        ( beforeAlignment, alignmentRaw ) =
            splitOnLast "," line

        alignment =
            String.trim alignmentRaw

        -- Split out the parenthetical subrace if present.
        ( beforeParen, subrace ) =
            case String.indexes "(" beforeAlignment of
                first :: _ ->
                    case String.indexes ")" beforeAlignment of
                        last :: _ ->
                            if last > first then
                                ( String.left first beforeAlignment |> String.trim
                                , String.slice (first + 1) last beforeAlignment |> String.trim
                                )

                            else
                                ( beforeAlignment, "" )

                        [] ->
                            ( beforeAlignment, "" )

                [] ->
                    ( beforeAlignment, "" )

        words =
            String.words beforeParen

        ( size, raceWords ) =
            case words of
                first :: rest ->
                    ( sizeFromWord first, rest )

                [] ->
                    ( Compendium.Medium, [] )

        race =
            String.join " " raceWords
                |> String.trim
                |> capitalize
    in
    { size = size, race = race, subrace = subrace, alignment = alignment }


splitOnLast : String -> String -> ( String, String )
splitOnLast needle haystack =
    case List.reverse (String.indexes needle haystack) of
        last :: _ ->
            ( String.left last haystack
            , String.dropLeft (last + String.length needle) haystack
            )

        [] ->
            ( haystack, "" )


sizeFromWord : String -> Compendium.Size
sizeFromWord word =
    case String.toLower word of
        "tiny" ->
            Compendium.Tiny

        "small" ->
            Compendium.Small

        "large" ->
            Compendium.Large

        "huge" ->
            Compendium.Huge

        "gargantuan" ->
            Compendium.Gargantuan

        _ ->
            Compendium.Medium


capitalize : String -> String
capitalize s =
    case String.uncons s of
        Just ( first, rest ) ->
            String.cons (Char.toUpper first) rest

        Nothing ->
            s



-- Feature start: "Multiattack. The dragon makes…"


splitFeatureStart : String -> Maybe ( String, String )
splitFeatureStart line =
    -- A feature starts with a phrase ending in a period, then a space,
    -- then the body. We require the leading phrase to start with an
    -- uppercase letter and to be no longer than ~40 characters so we
    -- don't accidentally cut a sentence in half.
    case String.indexes ". " line of
        first :: _ ->
            if first > 0 && first <= 40 then
                let
                    name =
                        String.left first line |> String.trim

                    body =
                        String.dropLeft (first + 2) line |> String.trim
                in
                if startsUppercase name then
                    Just ( name, body )

                else
                    Nothing

            else
                Nothing

        [] ->
            Nothing


startsUppercase : String -> Bool
startsUppercase s =
    case String.uncons s of
        Just ( c, _ ) ->
            Char.isUpper c

        Nothing ->
            False
