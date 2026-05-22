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
        |> List.concatMap splitCompoundMetaLine


{-| 2024 MM stat blocks sometimes print Habitat and Treasure on a
single physical line — "Habitat: Planar (Limbo) Treasure: Any" —
which would otherwise be claimed in full by whichever meta
prefix the line begins with, dropping the second key's body on
the floor. Only split when the line itself starts with a meta
key, so feature descriptions that happen to mention "habitat" or
"treasure" mid-sentence stay intact.
-}
splitCompoundMetaLine : String -> List String
splitCompoundMetaLine line =
    if startsWithMetaKey (String.toLower line) then
        splitCompoundMetaLineHelp line

    else
        [ line ]


startsWithMetaKey : String -> Bool
startsWithMetaKey lower =
    List.any (\m -> String.startsWith m lower)
        [ "habitat:"
        , "habitat "
        , "habitats:"
        , "habitats "
        , "treasure:"
        , "treasure "
        , "treasures:"
        , "treasures "
        ]


splitCompoundMetaLineHelp : String -> List String
splitCompoundMetaLineHelp line =
    let
        lower =
            String.toLower line

        nextKeyIdx =
            [ " habitat:"
            , " habitats:"
            , " treasure:"
            , " treasures:"
            ]
                |> List.filterMap (\m -> List.head (String.indexes m lower))
                |> List.minimum
    in
    case nextKeyIdx of
        Just i ->
            let
                head_ =
                    String.trim (String.left i line)

                tail =
                    String.trim (String.dropLeft (i + 1) line)
            in
            head_ :: splitCompoundMetaLineHelp tail

        Nothing ->
            [ line ]



-- ── STATE ────────────────────────────────────────────────────────────────────


type alias State =
    { creature : Compendium.Creature
    , section : Section
    , pending : Maybe PendingFeature
    , passedHeader : Bool
    , loreMode : Bool
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
        , xpInLair = 0
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
        , habitats = []
        , treasures = []
        , tags = []
        , createdAt = 0
        , updatedAt = 0
        }
    , section = TraitsSection
    , pending = Nothing
    , passedHeader = False
    , loreMode = False
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
    if state.loreMode then
        -- Even in lore mode, watch for late-arriving section
        -- headers like "Blue Dragon Lairs" — D&D Beyond emits
        -- these AFTER the monster description prose, so by the
        -- time they show up we're already past the legendary
        -- actions and dumping into Description.  The 2024 MM also
        -- prints Habitat: / Treasure: at the very end of a stat
        -- block (frequently AFTER the lore paragraph), so those
        -- prefixes need the same lore-mode escape — otherwise the
        -- typed fields stay empty and the tag line shows up as
        -- description text.
        case classifySection line (String.toLower line) of
            Just (LineSectionHeader section) ->
                { state
                    | section = section
                    , passedHeader = True
                    , loreMode = False
                }

            _ ->
                if isLateMetaLine (String.toLower line) then
                    dispatchClassifiedLine line { state | loreMode = False }

                else
                    appendLore line state

    else
        dispatchClassifiedLine line state


{-| Predicate: line begins with a meta key (Habitat / Treasure)
that the 2024 MM emits after the lore prose. Used by the
lore-mode escape so these tags actually land in their typed
fields instead of being swallowed by the description.
-}
isLateMetaLine : String -> Bool
isLateMetaLine lower =
    List.any (\m -> String.startsWith m lower)
        [ "habitat:"
        , "habitat "
        , "habitats:"
        , "habitats "
        , "treasure:"
        , "treasure "
        , "treasures:"
        , "treasures "
        ]


dispatchClassifiedLine : String -> State -> State
dispatchClassifiedLine line state =
    case classifyLine line of
        LineIgnore ->
            state

        LineArmorClass ac note ->
            withCreature
                (\c -> { c | armorClass = ac, armorClassNote = note })
                (commitFeature state)
                |> applyEmbeddedInitiative line

        LineHitPoints hp formula ->
            withCreature
                (\c -> { c | maxHp = hp, hpFormula = formula })
                (commitFeature state)

        LineSpeed speed ->
            withCreature (\c -> { c | speed = speed }) (commitFeature state)

        LineInitiative bonus ->
            withCreature (\c -> { c | initiativeBonus = bonus }) (commitFeature state)

        LineAbilities abs_ ->
            withCreature (\c -> { c | abilities = abs_ }) (commitFeature state)

        LineAbilityRow ability score maybeSave ->
            withCreature (applyAbilityRow ability score maybeSave) (commitFeature state)

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

        LineHabitats hs ->
            withCreature (\c -> { c | habitats = hs }) (commitFeature state)

        LineTreasures ts ->
            withCreature (\c -> { c | treasures = ts }) (commitFeature state)

        LineChallenge fields ->
            withCreature
                (\c ->
                    let
                        next =
                            { c
                                | challengeRating = fields.cr
                                , xp = fields.xp
                                , xpInLair = fields.xpInLair
                            }
                    in
                    if fields.pb > 0 then
                        { next | proficiencyBonus = fields.pb }

                    else
                        next
                )
                (commitFeature state)

        LineProficiencyBonus pb ->
            withCreature (\c -> { c | proficiencyBonus = pb }) (commitFeature state)

        LineSectionHeader section ->
            -- Commit FIRST so the pending feature lands in the
            -- previous section, then switch. Mark `passedHeader`
            -- so the lore detector knows we're past the meta phase.
            let
                committed =
                    commitFeature state
            in
            { committed | section = section, passedHeader = True }

        LineFeatureStart name body ->
            commitFeature state
                |> startFeature name body

        LineContinuation body ->
            if shouldEnterLoreMode state body then
                state
                    |> commitFeature
                    |> enterLoreMode body

            else
                extendFeature body state


withCreature : (Compendium.Creature -> Compendium.Creature) -> State -> State
withCreature fn state =
    { state | creature = fn state.creature }


{-| When the AC line carries a trailing "Initiative +N (M)" annotation
(D&D Beyond 2024 sometimes packs both onto one row), capture the
`+N` as the creature's initiative bonus so we don't lose the data
to `cleanAcLine`'s stripping. The `(M)` is the passive total; we
recompute it on render, so we discard it here.
-}
applyEmbeddedInitiative : String -> State -> State
applyEmbeddedInitiative line state =
    case extractInitiativeFromLine line of
        Just bonus ->
            withCreature (\c -> { c | initiativeBonus = bonus }) state

        Nothing ->
            state


extractInitiativeFromLine : String -> Maybe Int
extractInitiativeFromLine line =
    let
        lower =
            String.toLower line
    in
    case String.indexes "initiative" lower of
        i :: _ ->
            String.dropLeft (i + String.length "initiative") line
                |> String.trim
                |> readSignedIntPrefix

        [] ->
            Nothing


{-| Read a leading signed integer from a string (e.g. `"+10 (20)"`
returns `Just 10`). Unlike `parseSignedInt`, this returns `Nothing`
when the string doesn't actually start with a sign-and-digit run,
so the caller can distinguish "no initiative annotation" from
"initiative +0".
-}
readSignedIntPrefix : String -> Maybe Int
readSignedIntPrefix raw =
    case String.uncons raw of
        Just ( '+', rest ) ->
            firstIntMaybe rest

        Just ( '-', rest ) ->
            Maybe.map negate (firstIntMaybe rest)

        _ ->
            Nothing


firstIntMaybe : String -> Maybe Int
firstIntMaybe raw =
    let
        digits =
            raw
                |> String.toList
                |> dropUntil Char.isDigit
                |> takeWhileChars Char.isDigit
                |> String.fromList
    in
    if String.isEmpty digits then
        Nothing

    else
        String.toInt digits


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


{-| Lore mode kicks in when the previous feature has finished
cleanly (its last body line ends in sentence punctuation) AND the
incoming line looks like a paragraph rather than a continuation.

We deliberately require `pending = Just complete` instead of
allowing `Nothing` — otherwise, a long opening trait body
arriving right after a section header would trip the heuristic
before we've parsed even one feature in the new section.

The lookahead protects against, e.g., the lore tail of a D&D
Beyond export ("Adult blue dragons command small empires…")
silently extending the body of the last legendary action.

-}
shouldEnterLoreMode : State -> String -> Bool
shouldEnterLoreMode state body =
    case state.pending of
        Just p ->
            state.passedHeader
                && pendingComplete p
                && looksLikeLore body

        Nothing ->
            False


pendingComplete : PendingFeature -> Bool
pendingComplete p =
    case List.reverse p.body of
        last :: _ ->
            String.endsWith "." last
                || String.endsWith "?" last
                || String.endsWith "!" last

        [] ->
            False


looksLikeLore : String -> Bool
looksLikeLore body =
    let
        firstFeatureBoundary =
            case String.indexes ". " body of
                first :: _ ->
                    first

                [] ->
                    String.length body
    in
    String.length body > 60 && firstFeatureBoundary > 40


enterLoreMode : String -> State -> State
enterLoreMode line state =
    { state | loreMode = True }
        |> appendLore line


{-| Append a single paragraph into the running "Description"
custom section. If "Description" is already the last section,
append with a paragraph break; otherwise create a new entry.
-}
appendLore : String -> State -> State
appendLore line state =
    withCreature (\c -> { c | customSections = mergeIntoDescription line c.customSections })
        state


mergeIntoDescription : String -> List Compendium.CustomSection -> List Compendium.CustomSection
mergeIntoDescription line sections =
    case List.reverse sections of
        last :: rest ->
            if last.name == "Description" then
                List.reverse rest
                    ++ [ { last | body = last.body ++ "\n\n" ++ line } ]

            else
                sections ++ [ { name = "Description", body = line } ]

        [] ->
            [ { name = "Description", body = line } ]


applyAbilityRow :
    Compendium.Ability
    -> Int
    -> Maybe Int
    -> Compendium.Creature
    -> Compendium.Creature
applyAbilityRow ability score maybeSave c =
    let
        abilities =
            c.abilities

        nextAbilities =
            case ability of
                Compendium.Str ->
                    { abilities | str = score }

                Compendium.Dex ->
                    { abilities | dex = score }

                Compendium.Con ->
                    { abilities | con = score }

                Compendium.Int_ ->
                    { abilities | int = score }

                Compendium.Wis ->
                    { abilities | wis = score }

                Compendium.Cha ->
                    { abilities | cha = score }

        modifier =
            (score - 10) // 2

        savesAdditions =
            case maybeSave of
                Just save ->
                    if save /= modifier then
                        [ { ability = ability, bonus = save } ]

                    else
                        []

                Nothing ->
                    []
    in
    { c
        | abilities = nextAbilities
        , savingThrows = c.savingThrows ++ savesAdditions
    }


parkPreamble : Section -> String -> Compendium.Creature -> Compendium.Creature
parkPreamble section body c =
    case section of
        LairSection ->
            { c
                | lairActions =
                    Just
                        (case c.lairActions of
                            Just la ->
                                { la | description = appendDescription la.description body }

                            Nothing ->
                                { initiative = 20
                                , description = body
                                , options = []
                                }
                        )
            }

        RegionalSection ->
            { c
                | regionalEffects =
                    Just
                        (case c.regionalEffects of
                            Just re ->
                                { re | description = appendDescription re.description body }

                            Nothing ->
                                { description = body
                                , effects = []
                                , fadeAfter = ""
                                }
                        )
            }

        LegendarySection ->
            { c
                | legendaryActions =
                    Just
                        (case c.legendaryActions of
                            Just la ->
                                { la | description = appendDescription la.description body }

                            Nothing ->
                                { description = body
                                , uses = 3
                                , usesInLair = 0
                                , options = []
                                }
                        )
            }

        _ ->
            -- Traits / Actions / Bonus Actions / Reactions /
            -- Spellcasting / OtherSection: park into customSections
            -- so nothing's silently dropped.
            let
                heading =
                    sectionLabel section ++ " (preamble)"
            in
            { c | customSections = c.customSections ++ [ { name = heading, body = body } ] }


appendDescription : String -> String -> String
appendDescription existing new =
    if String.isEmpty existing then
        new

    else
        existing ++ "\n\n" ++ new


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
    | LineInitiative Int
    | LineAbilities Compendium.Abilities
    | LineAbilityRow Compendium.Ability Int (Maybe Int)
    | LineSaves (List Compendium.AbilitySave)
    | LineSkills (List Compendium.SkillBonus)
    | LineDamageVulnerabilities (List String)
    | LineDamageResistances (List String)
    | LineDamageImmunities (List String)
    | LineConditionImmunities (List String)
    | LineSenses Compendium.Senses
    | LineLanguages (List String)
    | LineHabitats (List Compendium.Habitat)
    | LineTreasures (List Compendium.Treasure)
    | LineChallenge { cr : String, xp : Int, xpInLair : Int, pb : Int }
      -- ^ `xpInLair` is 0 when the source omits the lair-XP clause.
      -- `pb` is 0 when no `PB +N` is on the line; the consumer
      -- treats 0 as "don't override the default proficiency bonus".
    | LineProficiencyBonus Int
    | LineSectionHeader Section
    | LineFeatureStart String String
    | LineContinuation String
    | LineIgnore


classifyLine : String -> Line
classifyLine line =
    let
        lower =
            String.toLower line
    in
    case classifySection line lower of
        Just headerLine ->
            headerLine

        Nothing ->
            case classifyAbilityRow line of
                Just abilityRowLine ->
                    abilityRowLine

                Nothing ->
                    case classifyByPrefix line lower of
                        Just prefixLine ->
                            prefixLine

                        Nothing ->
                            case parseAbilityLine line of
                                Just abs_ ->
                                    LineAbilities abs_

                                Nothing ->
                                    case splitFeatureStart line of
                                        Just ( name, body ) ->
                                            LineFeatureStart name body

                                        Nothing ->
                                            LineContinuation line


{-| Map known section-heading lines to the matching Section.
Section headings on D&D Beyond appear on a line by themselves
with no body — "Traits", "Actions", "Bonus Actions", etc. — so
exact-match against the lowercased line is enough.

Non-heading lines return Nothing so the caller can fall through.

-}
classifySection : String -> String -> Maybe Line
classifySection line lower =
    case lower of
        "traits" ->
            Just (LineSectionHeader TraitsSection)

        "actions" ->
            Just (LineSectionHeader ActionsSection)

        "bonus actions" ->
            Just (LineSectionHeader BonusActionsSection)

        "reactions" ->
            Just (LineSectionHeader ReactionsSection)

        "legendary actions" ->
            Just (LineSectionHeader LegendarySection)

        "lair actions" ->
            Just (LineSectionHeader LairSection)

        "regional effects" ->
            Just (LineSectionHeader RegionalSection)

        "spellcasting" ->
            Just (LineSectionHeader SpellcastingSection)

        _ ->
            -- Fuzzy match for D&D Beyond-style headings: "Blue
            -- Dragon Lairs", "Lich Lair", "Adult Red Dragon
            -- Regional Effects", etc.  These appear in the trailing
            -- lore section of pasted blocks and should fold into
            -- the matching structured field.
            if isLairHeading line lower then
                Just (LineSectionHeader LairSection)

            else if isRegionalHeading line lower then
                Just (LineSectionHeader RegionalSection)

            else
                Nothing


{-| A heading-style line ending in "Lair" or "Lairs". To avoid
matching sentence fragments ("...the dragon's lair", "It enters
the lair"), we additionally require the line to be short and to
be in title-case (each word starts with an uppercase letter, with
common short-words like "of"/"the"/"a" exempted).
-}
isLairHeading : String -> String -> Bool
isLairHeading line lower =
    String.length line
        < 40
        && (lower
                == "lair"
                || lower
                == "lairs"
                || String.endsWith " lair" lower
                || String.endsWith " lairs" lower
           )
        && isTitleCase line


isRegionalHeading : String -> String -> Bool
isRegionalHeading line lower =
    String.length line
        < 60
        && (lower
                == "regional effects"
                || String.endsWith " regional effects" lower
           )
        && isTitleCase line


{-| Each word's first letter is uppercase, except the small
joining words that conventionally stay lowercase in titles ("of",
"the", "a", "an", "and", "or", "in"). Punctuation-only "words"
(like "5-6)") are skipped. The first word still has to be
uppercase, even if it'd otherwise be a small word.
-}
isTitleCase : String -> Bool
isTitleCase line =
    let
        words =
            String.words line

        smallWords =
            [ "of", "the", "a", "an", "and", "or", "in", "on", "to", "for" ]

        firstLetter word =
            String.toList word
                |> List.filter Char.isAlpha
                |> List.head

        wordIsTitleCased index word =
            case firstLetter word of
                Nothing ->
                    True

                Just c ->
                    Char.isUpper c
                        || (index > 0 && List.member (String.toLower word) smallWords)
    in
    List.indexedMap wordIsTitleCased words
        |> List.all identity


{-| Prefix-driven dispatch for the upper detail block. Each rule
matches a case-insensitive prefix and is handed the trailing
text. Both old-style ("Armor Class …", "Hit Points …",
"Damage Immunities …") and modern compact forms ("AC …", "HP …",
"Immunities …") map to the same Lines so downstream logic
doesn't care.

The "Initiative" lookup is intentional: D&D Beyond 2024 sometimes
emits a standalone "Initiative +10 (20)" line that we parse here
just to capture the bonus. Anything with the bonus already
extracted from the AC line still works because the AC parser
strips that suffix before reading parens.

-}
classifyByPrefix : String -> String -> Maybe Line
classifyByPrefix line lower =
    let
        rules =
            [ ( "armor class ", \rest -> parseArmorClass (cleanAcLine rest) )
            , ( "ac ", \rest -> parseArmorClass (cleanAcLine rest) )
            , ( "hit points ", parseHitPoints )
            , ( "hp ", parseHitPoints )
            , ( "speed ", \rest -> LineSpeed (parseSpeed rest) )
            , ( "initiative ", \rest -> LineInitiative (parseSignedInt rest) )

            -- Save / skill rows.
            , ( "saving throws ", \rest -> LineSaves (parseSaves rest) )
            , ( "skills ", \rest -> LineSkills (parseSkills rest) )

            -- Damage / condition lists. Long forms first so they
            -- shadow the short forms when both could match.
            , ( "damage vulnerabilities ", \rest -> LineDamageVulnerabilities (parseCsv rest) )
            , ( "damage resistances ", \rest -> LineDamageResistances (parseCsv rest) )
            , ( "damage immunities ", \rest -> LineDamageImmunities (parseCsv rest) )
            , ( "condition immunities ", \rest -> LineConditionImmunities (parseCsv rest) )
            , ( "vulnerabilities ", \rest -> LineDamageVulnerabilities (parseCsv rest) )
            , ( "resistances ", \rest -> LineDamageResistances (parseCsv rest) )
            , ( "immunities ", \rest -> LineDamageImmunities (parseCsv rest) )

            -- Senses / languages.
            , ( "senses ", \rest -> LineSenses (parseSenses rest) )
            , ( "languages ", \rest -> LineLanguages (parseCsv rest) )

            -- 2024 MM habitat tags.  The colon-bearing forms come
            -- first so they shadow the bare prefixes; both singular
            -- ("Habitat:") and plural ("Habitats:") variants exist
            -- in third-party exports.
            , ( "habitat: ", \rest -> LineHabitats (parseHabitats rest) )
            , ( "habitats: ", \rest -> LineHabitats (parseHabitats rest) )
            , ( "habitat ", \rest -> LineHabitats (parseHabitats rest) )
            , ( "habitats ", \rest -> LineHabitats (parseHabitats rest) )

            -- 2024 MM treasure tags.  Same colon-first ordering as
            -- habitats; bare-prefix forms catch sources that omit
            -- the colon.
            , ( "treasure: ", \rest -> LineTreasures (parseTreasures rest) )
            , ( "treasures: ", \rest -> LineTreasures (parseTreasures rest) )
            , ( "treasure ", \rest -> LineTreasures (parseTreasures rest) )
            , ( "treasures ", \rest -> LineTreasures (parseTreasures rest) )

            -- CR + the legacy standalone PB line.
            , ( "challenge ", parseChallenge )
            , ( "cr ", parseChallenge )
            , ( "proficiency bonus ", \rest -> LineProficiencyBonus (parseSignedInt rest) )
            ]
    in
    matchPrefix line lower rules


{-| Apply prefix rules in order. The first one whose lowercased
prefix matches the lowercased line wins; the matching rule
receives the original (case-preserving) line minus the prefix.
This way "Armor Class 15" and "AC 15" both flow into
`parseArmorClass "15"` regardless of which prefix matched.
-}
matchPrefix : String -> String -> List ( String, String -> Line ) -> Maybe Line
matchPrefix line lower rules =
    case rules of
        [] ->
            Nothing

        ( prefix, fn ) :: rest ->
            if String.startsWith prefix lower then
                Just (fn (String.dropLeft (String.length prefix) line))

            else
                matchPrefix line lower rest


{-| Strip "Initiative +N (M)" suffixes from an AC line so the
parens-extractor for the AC note doesn't grab the initiative
roll-result by accident. Pre-2024 stat blocks just have
"AC 15 (leather armor)" so this is a no-op for them.
-}
cleanAcLine : String -> String
cleanAcLine raw =
    case String.indexes "Initiative" raw of
        i :: _ ->
            String.left i raw |> String.trim

        [] ->
            -- Try lower-case in case the source preserved it.
            case String.indexes "initiative" (String.toLower raw) of
                i :: _ ->
                    String.left i raw |> String.trim

                [] ->
                    raw


{-| `STR\t25\t+7\t+7`-style ability rows. These show up in
D&D Beyond's tabular layout, one per line. The columns are
ability label, score, mod, save bonus. We carry the save
bonus through so `applyAbilityRow` can register a
`savingThrows` entry only when it differs from the modifier
(i.e. the creature is proficient in that save).

Lines with just `Mod\tSave` (the table header) or extra
whitespace get ignored cleanly via `LineIgnore`.

-}
classifyAbilityRow : String -> Maybe Line
classifyAbilityRow line =
    let
        cols =
            String.split "\t" line
                |> List.map String.trim
                |> List.filter (not << String.isEmpty)
    in
    case cols of
        [ "Mod", "Save" ] ->
            Just LineIgnore

        firstCol :: rest ->
            case ( abilityFromAbbrev firstCol, rest ) of
                ( Just ability, scoreText :: more ) ->
                    case String.toInt scoreText of
                        Just score ->
                            Just (LineAbilityRow ability score (extractSaveColumn more))

                        Nothing ->
                            Nothing

                _ ->
                    Nothing

        [] ->
            Nothing


{-| Pull the save bonus out of the trailing columns. The mod
column comes first ("+7"), then the save column ("+7"). If only
one signed column is present we treat it as the save bonus.
-}
extractSaveColumn : List String -> Maybe Int
extractSaveColumn rest =
    let
        signed =
            List.filter looksSigned rest
    in
    case List.reverse signed of
        last :: _ ->
            Just (parseSignedInt last)

        [] ->
            Nothing


looksSigned : String -> Bool
looksSigned raw =
    String.startsWith "+" raw || String.startsWith "-" raw



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
            firstInt rest

        Just ( '-', rest ) ->
            negate (firstInt rest)

        _ ->
            firstInt trimmed


parseCsv : String -> List String
parseCsv raw =
    raw
        |> String.split ","
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)


{-| Parse the body of a 2024-MM habitat line. Two shapes to
handle on top of the comma-separated bare labels:

  - Trailing semicolon-separated continuation ("...; Treasure:
    Any") gets trimmed before the comma split.

  - Planar habitats are wrapped — "Planar (Limbo)" or
    "Planar (Abyss, Nine Hells)". The outer split must respect
    paren depth so the inner commas don't split prematurely, and
    each `Planar (…)` segment expands to its inner labels.

Unknown tokens drop silently — the field is decorative and a
typo shouldn't swallow the whole creature parse.

-}
parseHabitats : String -> List Compendium.Habitat
parseHabitats raw =
    let
        body =
            case String.indexes ";" raw of
                i :: _ ->
                    String.left i raw

                [] ->
                    raw
    in
    body
        |> splitTopLevelCommas
        |> List.concatMap expandHabitatSegment


{-| One segment of the comma-split habitat list. A bare label
like "Mountain" maps directly; a "Planar (X, Y)" wrapper expands
to its inner labels so each one lands in the typed list.
-}
expandHabitatSegment : String -> List Compendium.Habitat
expandHabitatSegment seg =
    let
        trimmed =
            String.trim seg

        lower =
            String.toLower trimmed
    in
    if String.startsWith "planar (" lower && String.endsWith ")" trimmed then
        trimmed
            |> String.slice 8 (String.length trimmed - 1)
            |> String.split ","
            |> List.filterMap (String.trim >> habitatFromLabel)

    else
        case habitatFromLabel trimmed of
            Just h ->
                [ h ]

            Nothing ->
                []


habitatFromLabel : String -> Maybe Compendium.Habitat
habitatFromLabel raw =
    let
        normalized =
            String.toLower (String.trim raw)
    in
    Compendium.allHabitats
        |> List.filter
            (\h -> String.toLower (Compendium.habitatLabel h) == normalized)
        |> List.head


{-| Split a comma-separated list, but treat commas inside
parentheses as ordinary characters. Lets "Mountain, Planar
(Abyss, Nine Hells)" survive as two top-level segments instead
of getting shredded into four.
-}
splitTopLevelCommas : String -> List String
splitTopLevelCommas s =
    splitTopLevelCommasHelp (String.toList s) 0 [] []


splitTopLevelCommasHelp :
    List Char
    -> Int
    -> List Char
    -> List String
    -> List String
splitTopLevelCommasHelp chars depth currentRev acc =
    case chars of
        [] ->
            List.reverse
                (String.fromList (List.reverse currentRev) :: acc)

        c :: rest ->
            case ( c, depth ) of
                ( '(', _ ) ->
                    splitTopLevelCommasHelp rest
                        (depth + 1)
                        (c :: currentRev)
                        acc

                ( ')', _ ) ->
                    splitTopLevelCommasHelp rest
                        (max 0 (depth - 1))
                        (c :: currentRev)
                        acc

                ( ',', 0 ) ->
                    splitTopLevelCommasHelp rest
                        depth
                        []
                        (String.fromList (List.reverse currentRev) :: acc)

                _ ->
                    splitTopLevelCommasHelp rest
                        depth
                        (c :: currentRev)
                        acc


{-| Same shape as `parseHabitats`: trim any trailing
semicolon-separated key/value pairs, CSV-split, match each token
case-insensitively against the four canonical treasure labels,
silently drop unknowns.

Special case: "Any" — the 2024 MM's most common treasure tag —
expands to all four buckets. The book uses `Any` to mean "any of
these four is appropriate," so the typed field reflects that
intent instead of staying empty.

-}
parseTreasures : String -> List Compendium.Treasure
parseTreasures raw =
    let
        body =
            case String.indexes ";" raw of
                i :: _ ->
                    String.left i raw

                [] ->
                    raw
    in
    if String.toLower (String.trim body) == "any" then
        Compendium.allTreasures

    else
        body
            |> String.split ","
            |> List.filterMap (String.trim >> treasureFromLabel)


treasureFromLabel : String -> Maybe Compendium.Treasure
treasureFromLabel raw =
    let
        normalized =
            String.toLower (String.trim raw)
    in
    Compendium.allTreasures
        |> List.filter
            (\t -> String.toLower (Compendium.treasureLabel t) == normalized)
        |> List.head



-- Senses: "blindsight 60 ft., darkvision 60 ft., passive Perception 12"


parseSenses : String -> Compendium.Senses
parseSenses raw =
    let
        -- D&D Beyond 2024 uses "Senses Blindsight 60 ft.,
        -- Darkvision 120 ft.; Passive Perception 22" — comma
        -- between sense modes, semicolon before passive
        -- Perception. We treat both as segment boundaries.
        segments =
            raw
                |> String.replace ";" ","
                |> String.split ","
                |> List.map String.trim
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
    LineChallenge
        { cr =
            raw
                |> String.split "("
                |> List.head
                |> Maybe.withDefault raw
                |> String.trim
        , xp = extractXp raw
        , xpInLair = extractLairXpFromChallenge raw
        , pb = extractPbFromChallenge raw
        }


{-| Pull `+N` after `PB` out of strings like
"16 (XP 15,000, or 18,000 in lair; PB +5)" — D&D Beyond 2024
combines CR / XP / lair-XP / PB on a single line. Returns 0
if no PB found (caller treats 0 as "leave default alone").
-}
extractPbFromChallenge : String -> Int
extractPbFromChallenge raw =
    let
        lower =
            String.toLower raw
    in
    case String.indexes "pb " lower of
        i :: _ ->
            String.dropLeft (i + 3) raw
                |> parseSignedInt

        [] ->
            0


{-| Pull the in-lair XP out of strings like
"16 (XP 15,000, or 18,000 in lair; PB +5)". D&D 2024 stat
blocks publish the lair variant inline, immediately after an
"or" keyword and immediately before "in lair" (case-insensitive).

Returns 0 when the line doesn't carry a lair XP — the creature
either has no lair or the source didn't print one, and the
caller treats 0 as "no separate lair XP".

-}
extractLairXpFromChallenge : String -> Int
extractLairXpFromChallenge raw =
    let
        lower =
            String.toLower raw
    in
    case String.indexes "in lair" lower of
        i :: _ ->
            -- Walk backwards from "in lair" through any digits and
            -- thousand-separator commas to find the start of the
            -- lair XP number.  Whitespace between digits and the
            -- "in lair" keyword is consumed by the back-walk.
            takeTrailingNumber (String.left i raw)

        [] ->
            0


{-| Walk a string from the right, skipping trailing whitespace,
then collecting a contiguous run of digits and commas. Strip the
commas and parse what's left. Returns 0 when no digits precede
the trimmed tail, so callers don't have to special-case the
"the line had `in lair` somewhere unrelated" failure mode.
-}
takeTrailingNumber : String -> Int
takeTrailingNumber raw =
    let
        chars =
            raw
                |> String.trimRight
                |> String.toList
                |> List.reverse

        ( digitsRev, _ ) =
            splitWhile (\c -> Char.isDigit c || c == ',') chars
    in
    digitsRev
        |> List.reverse
        |> String.fromList
        |> String.replace "," ""
        |> String.toInt
        |> Maybe.withDefault 0


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
    -- then the body. The leading phrase must:
    --
    --   - be no longer than ~60 chars (so usage tags like "Legendary
    --     Resistance (3/Day, or 4/Day in Lair)" still fit)
    --   - start with an uppercase letter
    --   - read like Title Case (every alpha-leading word is uppercase
    --     or a small joining word like "of"/"in"). This filters out
    --     prose sentences like "Blue dragons dwell in arid lands."
    --     where the period happens to land within 60 chars.
    case String.indexes ". " line of
        first :: _ ->
            if first > 0 && first <= 60 then
                let
                    name =
                        String.left first line |> String.trim

                    body =
                        String.dropLeft (first + 2) line |> String.trim
                in
                if startsUppercase name && isTitleCase name then
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
