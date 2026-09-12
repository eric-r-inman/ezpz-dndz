module Encounter.SaveChainSettingsTest exposing (suite)

{-| The Save Chain settings a preset can carry beyond its two
outcomes: how a relative duration settles against the creatures
at hand, how a granted immunity is found again, and that the wire
carries every new field back unchanged.
-}

import Compendium exposing (Ability(..))
import Dict
import Encounter exposing (AutoRollMode(..), Cover(..), DamageTrigger(..), Duration(..), TurnPhase(..), TurnTarget(..))
import Encounter.SaveChain as SaveChain exposing (EffectDuration(..), HpEffect(..), TurnRef(..))
import Encounter.SaveChain.Wire as Wire
import Expect
import Json.Decode as D
import Set
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Encounter.SaveChain settings"
        [ durationSuite
        , immunitySuite
        , wireSuite
        ]


durationSuite : Test
durationSuite =
    describe "resolveDuration"
        [ test "until removed is the manual duration" <|
            \_ ->
                SaveChain.resolveDuration "Ogre" "Goblin" LastsUntilRemoved
                    |> Expect.equal DurationManual
        , test "the bearer's turn names the bearer" <|
            \_ ->
                SaveChain.resolveDuration "Ogre" "Goblin" (LastsUntilTurn AtEnd TurnOfBearer)
                    |> Expect.equal (DurationUntilTurn AtEnd OnCurrentTurn "Goblin")
        , test "the active creature's turn names whoever is active" <|
            \_ ->
                SaveChain.resolveDuration "Ogre" "Goblin" (LastsUntilTurn AtBegin TurnOfActive)
                    |> Expect.equal (DurationUntilTurn AtBegin OnCurrentTurn "Ogre")
        , test "the active creature falls back to the bearer before combat starts" <|
            \_ ->
                SaveChain.resolveDuration "" "Goblin" (LastsUntilTurn AtBegin TurnOfActive)
                    |> Expect.equal (DurationUntilTurn AtBegin OnCurrentTurn "Goblin")
        , test "a named creature is used as given" <|
            \_ ->
                SaveChain.resolveDuration "Ogre" "Goblin" (LastsUntilTurn AtEnd (TurnOf "Lyra"))
                    |> Expect.equal (DurationUntilTurn AtEnd OnCurrentTurn "Lyra")
        , test "the active creature's own end of turn means its next one" <|
            \_ ->
                SaveChain.resolveDuration "Ogre" "Goblin" (LastsUntilTurn AtEnd TurnOfActive)
                    |> Expect.equal (DurationUntilTurn AtEnd OnNextTurn "Ogre")
        , test "a countdown on the active bearer skips the end of turn moments away" <|
            \_ ->
                SaveChain.resolveDuration "Goblin" "Goblin" (LastsForTurns AtEnd 3)
                    |> Expect.equal (DurationCountdown AtEnd 3 True)
        , test "a countdown on an inactive bearer counts its first end of turn" <|
            \_ ->
                SaveChain.resolveDuration "Ogre" "Goblin" (LastsForTurns AtEnd 3)
                    |> Expect.equal (DurationCountdown AtEnd 3 False)
        , test "one minute is ten of the bearer's turns" <|
            \_ ->
                SaveChain.resolveDuration "Ogre" "Goblin" LastsOneMinute
                    |> Expect.equal (DurationCountdown AtEnd 10 False)
        ]


immunitySuite : Test
immunitySuite =
    let
        chain =
            { name = "Ghast Stench"
            , saveAbility = Con
            , saveDc = Just 10
            , onFail = SaveChain.empty.onFail
            , onSuccess = SaveChain.empty.onSuccess
            , immunity = Just LastsUntilRemoved
            , area = Nothing
            }

        goblin =
            creature "Goblin"

        enc =
            { creatures = [ goblin ], activeName = "Goblin", round = 1 }
                |> withEmptyRest
    in
    describe "immunity"
        [ test "a creature without the chip is not immune" <|
            \_ ->
                SaveChain.isImmune chain "Goblin" enc |> Expect.equal False
        , test "granting the immunity leaves a chip the chain recognises" <|
            \_ ->
                SaveChain.grantImmunity "Goblin" chain "Goblin" enc
                    |> SaveChain.isImmune chain "Goblin"
                    |> Expect.equal True
        , test "the chip is named for the chain" <|
            \_ ->
                SaveChain.immunityName chain |> Expect.equal "Immune: Ghast Stench"
        , test "a chain that grants no immunity leaves the creature alone" <|
            \_ ->
                SaveChain.grantImmunity "Goblin" { chain | immunity = Nothing } "Goblin" enc
                    |> Expect.equal enc
        ]


{-| A creature with every field at its blank value.
-}
creature : String -> Encounter.Creature
creature name =
    { name = name
    , kind = ""
    , initiative = 12
    , initiativeBonus = 0
    , currentHp = 7
    , maxHp = 7
    , originalMaxHp = 7
    , tempHp = 0
    , armorClass = 15
    , speed = 30
    , conditions = []
    , saveNotices = []
    , selected = False
    , cover = NoCover
    , concentrating = False
    , concentrationNote = ""
    , hiding = False
    , dodging = False
    , flying = False
    , flyHeight = 0
    , bloodied = False
    , deathSaves = { successes = 0, failures = 0 }
    , acceptingDeathSaves = False
    , reactionUsed = False
    , rechargeAbilities = []
    , readied = False
    , inactive = False
    , note = ""
    , memo = ""
    , timer = Nothing
    , creatureId = Nothing
    , legendaryActionsCount = 0
    , legendaryActionsLairBonus = 0
    , legendaryActionsUsed = Set.empty
    , legendaryResistanceCount = 0
    , legendaryResistanceLairBonus = 0
    , legendaryResistanceUsed = Set.empty
    , isPlaceholder = False
    , creatureKind = "enemy"
    , race = ""
    , alignment = ""
    , hasSpecialReactions = False
    , specialReactionsUsed = Set.empty
    }


{-| The encounter fields beyond the three the tests care about,
at their empty values.
-}
withEmptyRest : { creatures : List Encounter.Creature, activeName : String, round : Int } -> Encounter.Encounter
withEmptyRest partial =
    let
        empty =
            Encounter.empty
    in
    { empty | creatures = partial.creatures, activeName = partial.activeName, round = partial.round }


wireSuite : Test
wireSuite =
    let
        chain =
            { name = "Medusa Petrifying Gaze"
            , saveAbility = Con
            , saveDc = Just 13
            , onFail =
                { hp = DealDamage "4d10"
                , effects =
                    [ { name = "Restrained"
                      , note = "Petrifying Gaze"
                      , duration = LastsOneMinute
                      , saveToEnd =
                            Just
                                { autoRoll = AutoRollAtEnd
                                , onFail = { damage = Just "2d6", becomes = Just "Petrified" }
                                , onDamage = RollOnDamage
                                }
                      , with = "Incapacitated"
                      }
                    , { name = "Marked"
                      , note = ""
                      , duration = LastsThisTurn
                      , saveToEnd = Nothing
                      , with = ""
                      }
                    ]
                }
            , onSuccess =
                { hp = HalfFailDamage
                , effects =
                    [ { name = "Shaken"
                      , note = ""
                      , duration = LastsForTurns AtBegin 3
                      , saveToEnd = Just { autoRoll = AutoRollAskAtEnd, onFail = Encounter.noFailedSave, onDamage = AskOnDamage }
                      , with = ""
                      }
                    ]
                }
            , immunity = Just (LastsUntilTurn AtEnd TurnOfActive)
            , area = Just AtEnd
            }

        presets =
            Dict.fromList [ ( chain.name, chain ) ]
    in
    describe "Encounter.SaveChain.Wire"
        [ test "every setting survives encode → decode" <|
            \_ ->
                Wire.encodePresets presets
                    |> D.decodeValue Wire.decodePresets
                    |> Expect.equal (Ok presets)
        , test "a preset written before the settings existed reads as until-removed with no immunity" <|
            \_ ->
                D.decodeString Wire.decodePresets
                    """
                    { "Old Hold":
                        { "name": "Old Hold"
                        , "save_ability": "wis"
                        , "save_dc": 14
                        , "on_fail":
                            { "hp": { "kind": "none" }
                            , "effects": [ { "name": "Paralyzed", "note": "", "save_to_end": "at_end" } ]
                            }
                        , "on_success": { "hp": { "kind": "none" }, "effects": [] }
                        }
                    }
                    """
                    |> Result.map (Dict.get "Old Hold")
                    |> Expect.equal
                        (Ok
                            (Just
                                { name = "Old Hold"
                                , saveAbility = Wis
                                , saveDc = Just 14
                                , onFail =
                                    { hp = NoHpEffect
                                    , effects =
                                        [ { name = "Paralyzed"
                                          , note = ""
                                          , duration = LastsUntilRemoved
                                          , saveToEnd = Just { autoRoll = AutoRollAtEnd, onFail = Encounter.noFailedSave, onDamage = NoDamageTrigger }
                                          , with = ""
                                          }
                                        ]
                                    }
                                , onSuccess = SaveChain.empty.onSuccess
                                , immunity = Nothing
                                , area = Nothing
                                }
                            )
                        )
        ]
