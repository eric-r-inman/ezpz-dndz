module HpChangeTest exposing (suite)

{-| Behavior tests for the HP-change engine. Covers the four
arithmetic flavors plus the auto-derived bloodied flag and the
heal-from-zero death-save reset.

We construct minimal fixture creatures inline rather than
reaching into `Encounter.initialEncounter` so the tests don't
shift when the seed changes.

-}

import Encounter
import Encounter.DeathSaves as DeathSaves
import Expect
import HpChange
import Set
import Test exposing (Test, describe, test)


fixture : Encounter.Creature
fixture =
    { name = "Test"
    , kind = "Test creature"
    , initiative = 10
    , initiativeBonus = 0
    , currentHp = 30
    , maxHp = 50
    , tempHp = 0
    , armorClass = 12
    , speed = 30
    , conditions = []
    , saveNotices = []
    , selected = False
    , cover = Encounter.NoCover
    , concentrating = False
    , hiding = False
    , dodging = False
    , flying = False
    , flyHeight = 0
    , bloodied = False
    , deathSaves = DeathSaves.empty
    , acceptingDeathSaves = False
    , readied = False
    , inactive = False
    , note = ""
    , memo = ""
    , timer = Nothing
    , creatureId = Nothing
    , hasLegendaryActions = False
    , legendaryActionsUsed = Set.empty
    , hasLegendaryResistance = False
    , legendaryResistanceUsed = Set.empty
    , isPlaceholder = False
    , creatureKind = "enemy"
    , race = ""
    , alignment = ""
    }


damageSuite : Test
damageSuite =
    describe "Damage"
        [ test "subtracts from currentHp" <|
            \_ ->
                fixture
                    |> HpChange.apply (HpChange.Damage { amount = 5, ignoreTemp = False })
                    |> .currentHp
                    |> Expect.equal 25
        , test "clamps currentHp at zero (never negative)" <|
            \_ ->
                fixture
                    |> HpChange.apply (HpChange.Damage { amount = 999, ignoreTemp = False })
                    |> .currentHp
                    |> Expect.equal 0
        , test "soaks against tempHp first" <|
            \_ ->
                { fixture | tempHp = 7 }
                    |> HpChange.apply (HpChange.Damage { amount = 5, ignoreTemp = False })
                    |> Expect.all
                        [ \c -> c.currentHp |> Expect.equal 30
                        , \c -> c.tempHp |> Expect.equal 2
                        ]
        , test "ignoreTemp = True bypasses the temp-HP buffer" <|
            \_ ->
                { fixture | tempHp = 7 }
                    |> HpChange.apply (HpChange.Damage { amount = 5, ignoreTemp = True })
                    |> Expect.all
                        [ \c -> c.currentHp |> Expect.equal 25
                        , \c -> c.tempHp |> Expect.equal 7
                        ]
        , test "auto-sets bloodied when dropping below half HP" <|
            \_ ->
                fixture
                    |> HpChange.apply (HpChange.Damage { amount = 10, ignoreTemp = False })
                    |> .bloodied
                    |> Expect.equal True
        ]


healSuite : Test
healSuite =
    describe "Heal"
        [ test "adds to currentHp" <|
            \_ ->
                fixture
                    |> HpChange.apply (HpChange.Heal 10)
                    |> .currentHp
                    |> Expect.equal 40
        , test "caps at maxHp" <|
            \_ ->
                fixture
                    |> HpChange.apply (HpChange.Heal 100)
                    |> .currentHp
                    |> Expect.equal fixture.maxHp
        , test "revival from 0 HP clears death-save tracker" <|
            \_ ->
                let
                    knockedDown =
                        { fixture
                            | currentHp = 0
                            , deathSaves = DeathSaves.empty |> DeathSaves.addFailures 2
                        }
                in
                knockedDown
                    |> HpChange.apply (HpChange.Heal 5)
                    |> .deathSaves
                    |> Expect.equal DeathSaves.empty
        , test "auto-clears bloodied on heal back above half HP" <|
            \_ ->
                { fixture | currentHp = 5, bloodied = True }
                    |> HpChange.apply (HpChange.Heal 25)
                    |> .bloodied
                    |> Expect.equal False
        ]


tempHpSuite : Test
tempHpSuite =
    describe "TempHp"
        [ test "replaces existing tempHp with a higher value" <|
            \_ ->
                { fixture | tempHp = 3 }
                    |> HpChange.apply (HpChange.TempHp 8)
                    |> .tempHp
                    |> Expect.equal 8
        , test "ignores a lower value (never stacks down)" <|
            \_ ->
                { fixture | tempHp = 8 }
                    |> HpChange.apply (HpChange.TempHp 3)
                    |> .tempHp
                    |> Expect.equal 8
        ]


setHpSuite : Test
setHpSuite =
    describe "GM overrides"
        [ test "setCurrentHp clamps to 0..maxHp" <|
            \_ ->
                fixture
                    |> HpChange.setCurrentHp 999
                    |> .currentHp
                    |> Expect.equal fixture.maxHp
        , test "setMaxHp drags currentHp down if it would exceed" <|
            \_ ->
                fixture
                    |> HpChange.setMaxHp 10
                    |> Expect.all
                        [ \c -> c.maxHp |> Expect.equal 10
                        , \c -> c.currentHp |> Expect.equal 10
                        ]
        ]


suite : Test
suite =
    describe "HpChange (pure HP arithmetic)"
        [ damageSuite, healSuite, tempHpSuite, setHpSuite ]
