module CompendiumTest exposing (suite)

{-| Behavior tests for `Compendium` — `Db` ops (search / filter /
sort) plus the `crToFloat` helper that drives the CR sort.
-}

import Compendium
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Compendium"
        [ dbOpsSuite
        , searchSuite
        , filterByKindSuite
        , sortByNameSuite
        , sortByCrSuite
        , sortByRecencySuite
        , crToFloatSuite
        , draftToInstanceRechargeSuite
        ]



-- ── FIXTURES ─────────────────────────────────────────────────────────────


mkCreature : { id : String, name : String, kind : Compendium.CreatureKind, cr : String, createdAt : Int } -> Compendium.Creature
mkCreature args =
    { id = args.id
    , name = args.name
    , kind = args.kind
    , size = Compendium.Medium
    , race = ""
    , subrace = ""
    , alignment = ""
    , source = ""
    , description = ""
    , armorClass = 10
    , armorClassNote = ""
    , maxHp = 10
    , hpFormula = ""
    , initiativeBonus = 0
    , speed =
        { walk = 30
        , fly = 0
        , swim = 0
        , climb = 0
        , burrow = 0
        , hover = False
        }
    , abilities =
        { str = 10, dex = 10, con = 10, int = 10, wis = 10, cha = 10 }
    , savingThrows = []
    , skills = []
    , damageVulnerabilities = []
    , damageResistances = []
    , damageImmunities = []
    , conditionImmunities = []
    , senses =
        { blindsight = 0
        , darkvision = 0
        , tremorsense = 0
        , truesight = 0
        , passivePerception = 10
        }
    , languages = []
    , challengeRating = args.cr
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
    , createdAt = args.createdAt
    , updatedAt = args.createdAt
    }


goblin : Compendium.Creature
goblin =
    let
        c =
            mkCreature { id = "g1", name = "Goblin", kind = Compendium.Enemy, cr = "1/4", createdAt = 100 }
    in
    { c | race = "humanoid (goblinoid)" }


ogre : Compendium.Creature
ogre =
    mkCreature { id = "o1", name = "Ogre", kind = Compendium.Enemy, cr = "2", createdAt = 200 }


lyra : Compendium.Creature
lyra =
    mkCreature { id = "l1", name = "Lyra Vale", kind = Compendium.Player, cr = "—", createdAt = 50 }


bard : Compendium.Creature
bard =
    mkCreature { id = "b1", name = "Tavern Bard", kind = Compendium.Npc, cr = "1/8", createdAt = 300 }


db : Compendium.Db
db =
    Compendium.fromList [ goblin, ogre, lyra, bard ]


names : Compendium.Db -> List String
names =
    Compendium.toList >> List.map .name



-- ── Db ops ───────────────────────────────────────────────────────────────


dbOpsSuite : Test
dbOpsSuite =
    describe "Db basics"
        [ test "fromList preserves the input order" <|
            \_ ->
                names db
                    |> Expect.equal [ "Goblin", "Ogre", "Lyra Vale", "Tavern Bard" ]
        , test "count returns the list length" <|
            \_ ->
                Compendium.count db
                    |> Expect.equal 4
        , test "find returns the matching creature when the id exists" <|
            \_ ->
                Compendium.find "o1" db
                    |> Maybe.map .name
                    |> Expect.equal (Just "Ogre")
        , test "find returns Nothing for an unknown id" <|
            \_ ->
                Compendium.find "nope" db
                    |> Expect.equal Nothing
        ]



-- ── search ───────────────────────────────────────────────────────────────


searchSuite : Test
searchSuite =
    describe "search"
        [ test "empty query returns the full DB unchanged" <|
            \_ ->
                Compendium.search "" db
                    |> Compendium.count
                    |> Expect.equal 4
        , test "whitespace-only query returns the full DB unchanged" <|
            \_ ->
                Compendium.search "   " db
                    |> Compendium.count
                    |> Expect.equal 4
        , test "case-insensitive name match" <|
            \_ ->
                Compendium.search "GoB" db
                    |> names
                    |> Expect.equal [ "Goblin" ]
        , test "matches against race text" <|
            \_ ->
                Compendium.search "humanoid" db
                    |> names
                    |> Expect.equal [ "Goblin" ]
        , test "matches against challenge rating" <|
            \_ ->
                Compendium.search "1/4" db
                    |> names
                    |> Expect.equal [ "Goblin" ]
        , test "no match returns an empty DB" <|
            \_ ->
                Compendium.search "xyzzy" db
                    |> Compendium.count
                    |> Expect.equal 0
        ]



-- ── filterByKind ─────────────────────────────────────────────────────────


filterByKindSuite : Test
filterByKindSuite =
    describe "filterByKind"
        [ test "empty filter list returns the full DB unchanged" <|
            \_ ->
                Compendium.filterByKind [] db
                    |> Compendium.count
                    |> Expect.equal 4
        , test "single-kind filter keeps only matching creatures" <|
            \_ ->
                Compendium.filterByKind [ Compendium.Enemy ] db
                    |> names
                    |> Expect.equal [ "Goblin", "Ogre" ]
        , test "multi-kind filter is OR'd" <|
            \_ ->
                Compendium.filterByKind [ Compendium.Player, Compendium.Npc ] db
                    |> names
                    |> Expect.equal [ "Lyra Vale", "Tavern Bard" ]
        ]



-- ── sortByName / sortByCr / sortByRecency ────────────────────────────────


sortByNameSuite : Test
sortByNameSuite =
    describe "sortByName"
        [ test "sorts case-insensitively, ascending" <|
            \_ ->
                Compendium.sortByName db
                    |> names
                    |> Expect.equal [ "Goblin", "Lyra Vale", "Ogre", "Tavern Bard" ]
        ]


sortByCrSuite : Test
sortByCrSuite =
    describe "sortByCr"
        [ test "sorts by parsed CR ascending; '—' lands at the front (-1)" <|
            \_ ->
                Compendium.sortByCr db
                    |> names
                    |> Expect.equal [ "Lyra Vale", "Tavern Bard", "Goblin", "Ogre" ]
        ]


sortByRecencySuite : Test
sortByRecencySuite =
    describe "sortByRecency"
        [ test "sorts by createdAt descending (newest first)" <|
            \_ ->
                Compendium.sortByRecency db
                    |> names
                    |> Expect.equal [ "Tavern Bard", "Ogre", "Goblin", "Lyra Vale" ]
        ]



-- ── crToFloat ────────────────────────────────────────────────────────────


crToFloatSuite : Test
crToFloatSuite =
    describe "crToFloat"
        [ test "parses an integer CR" <|
            \_ ->
                Compendium.crToFloat "5"
                    |> Expect.within (Expect.Absolute 0.001) 5.0
        , test "parses a fractional CR like 1/4" <|
            \_ ->
                Compendium.crToFloat "1/4"
                    |> Expect.within (Expect.Absolute 0.001) 0.25
        , test "parses 1/8" <|
            \_ ->
                Compendium.crToFloat "1/8"
                    |> Expect.within (Expect.Absolute 0.001) 0.125
        , test "returns -1 for unparseable input" <|
            \_ ->
                Compendium.crToFloat "—"
                    |> Expect.within (Expect.Absolute 0.001) -1.0
        , test "returns -1 for an empty string" <|
            \_ ->
                Compendium.crToFloat ""
                    |> Expect.within (Expect.Absolute 0.001) -1.0
        , test "trims surrounding whitespace" <|
            \_ ->
                Compendium.crToFloat "  3  "
                    |> Expect.within (Expect.Absolute 0.001) 3.0
        ]



-- ── draftToInstance recharge name fallback ────────────────────────────────


draftToInstanceRechargeSuite : Test
draftToInstanceRechargeSuite =
    describe "draftToInstance — recharge name fallback"
        [ test "extracts (Recharge X-Y) from a parsed-paste feature name" <|
            \_ ->
                -- Mirrors what the paste parser produces for a line
                -- like "Petrifying Gaze (Recharge 4-6). description…"
                -- — `usage` is `Nothing`, the recharge lives in the
                -- name suffix.  The fallback in draftToInstance must
                -- pick it up so the encounter card shows the chip.
                let
                    source =
                        let
                            c =
                                mkCreature
                                    { id = "x"
                                    , name = "Test"
                                    , kind = Compendium.Enemy
                                    , cr = "4"
                                    , createdAt = 0
                                    }
                        in
                        { c
                            | bonusActions =
                                [ { name = "Petrifying Gaze (Recharge 4-6)"
                                  , description = "Constitution save…"
                                  , usage = Nothing
                                  }
                                ]
                        }

                    instance =
                        Compendium.draftToInstance
                            { displayName = "Test", initiativeRoll = 0 }
                            source
                in
                instance.rechargeAbilities
                    |> Expect.equal
                        [ { name = "Petrifying Gaze"
                          , low = 4
                          , high = 6
                          , ready = True
                          }
                        ]
        , test "handles single-value (Recharge 6) and en-dash variants" <|
            \_ ->
                let
                    source =
                        let
                            c =
                                mkCreature
                                    { id = "y"
                                    , name = "Mephit"
                                    , kind = Compendium.Enemy
                                    , cr = "1/4"
                                    , createdAt = 0
                                    }
                        in
                        { c
                            | actions =
                                [ { name = "Frost Breath (Recharge 6)"
                                  , description = "…"
                                  , usage = Nothing
                                  }
                                , { name = "Fire Breath (Recharge 5–6)"

                                  -- ^ en-dash, not ASCII hyphen
                                  , description = "…"
                                  , usage = Nothing
                                  }
                                ]
                        }

                    instance =
                        Compendium.draftToInstance
                            { displayName = "Mephit", initiativeRoll = 0 }
                            source

                    ranges =
                        instance.rechargeAbilities
                            |> List.map (\r -> ( r.name, r.low, r.high ))
                in
                ranges
                    |> Expect.equal
                        [ ( "Frost Breath", 6, 6 )
                        , ( "Fire Breath", 5, 6 )
                        ]
        , test "structured `usage` wins over name suffix when both are present" <|
            \_ ->
                let
                    source =
                        let
                            c =
                                mkCreature
                                    { id = "z"
                                    , name = "Custom"
                                    , kind = Compendium.Enemy
                                    , cr = "1"
                                    , createdAt = 0
                                    }
                        in
                        { c
                            | actions =
                                [ { name = "Bite (Recharge 5-6)"
                                  , description = "…"
                                  , usage =
                                        Just
                                            (Compendium.Recharge
                                                { low = 3, high = 6 }
                                            )
                                  }
                                ]
                        }

                    instance =
                        Compendium.draftToInstance
                            { displayName = "Custom", initiativeRoll = 0 }
                            source
                in
                instance.rechargeAbilities
                    |> List.map (\r -> ( r.low, r.high ))
                    |> Expect.equal [ ( 3, 6 ) ]
        , test "feature without recharge suffix produces no chip" <|
            \_ ->
                let
                    source =
                        let
                            c =
                                mkCreature
                                    { id = "q"
                                    , name = "Goblin"
                                    , kind = Compendium.Enemy
                                    , cr = "1/4"
                                    , createdAt = 0
                                    }
                        in
                        { c
                            | actions =
                                [ { name = "Scimitar"
                                  , description = "Melee Attack Roll…"
                                  , usage = Nothing
                                  }
                                ]
                        }

                    instance =
                        Compendium.draftToInstance
                            { displayName = "Goblin", initiativeRoll = 0 }
                            source
                in
                instance.rechargeAbilities |> Expect.equal []
        ]
