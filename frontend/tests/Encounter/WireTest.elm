module Encounter.WireTest exposing (suite)

{-| Round-trip tests for `Encounter.Wire`. Confirms that
encoding an `Encounter` then decoding the result reproduces the
original value field-for-field. This is what guarantees Save →
Load (and the anonymous-mode localStorage round-trip, and the
device-download JSON, since they all go through the same
`encodeEncounter` / `decodeEncounter`).

The fixture below sets EVERY field on `Creature` to a
non-default value, so if a new field is added to `Creature` but
not threaded through `encodeCreature` or `decodeCreature`, this
test fails with a structural mismatch.

-}

import Encounter exposing (AutoRollMode(..), Cover(..), Duration(..), TurnPhase(..), TurnTarget(..))
import Encounter.Wire as Wire
import Expect
import Json.Decode as D
import Json.Encode as E
import Set
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Encounter.Wire round-trip"
        [ test "empty encounter survives encode → decode" <|
            \_ ->
                Encounter.empty |> roundTripExpect
        , test "fully-populated single-creature encounter survives" <|
            \_ ->
                singleCreatureEncounter |> roundTripExpect
        , test "multi-creature encounter with active marker survives" <|
            \_ ->
                multiCreatureEncounter |> roundTripExpect
        , test "encoder includes the `activeName` field verbatim" <|
            \_ ->
                let
                    json =
                        E.encode 0 (Wire.encodeEncounter multiCreatureEncounter)
                in
                String.contains "\"activeName\":\"Brakka\"" json
                    |> Expect.equal True
        , test "encoder includes the new structured identity fields" <|
            \_ ->
                let
                    json =
                        E.encode 0 (Wire.encodeEncounter singleCreatureEncounter)
                in
                List.all (\token -> String.contains token json)
                    [ "\"creatureKind\":\"enemy\""
                    , "\"race\":\"Dragon\""
                    , "\"alignment\":\"chaotic evil\""
                    , "\"isPlaceholder\":false"
                    ]
                    |> Expect.equal True
        ]



-- ── FIXTURES ────────────────────────────────────────────────────────────────


singleCreatureEncounter : Encounter.Encounter
singleCreatureEncounter =
    { creatures = [ fullyPopulatedCreature ]
    , activeName = "Smaug"
    , round = 7
    , treasure = Nothing
    }


multiCreatureEncounter : Encounter.Encounter
multiCreatureEncounter =
    { creatures =
        [ { fullyPopulatedCreature | name = "Lyra", initiative = 22 }
        , { fullyPopulatedCreature | name = "Brakka", initiative = 18 }
        , { fullyPopulatedCreature | name = "Goblin 3", initiative = 12 }
        ]
    , activeName = "Brakka"
    , round = 3
    , treasure = Nothing
    }


{-| Every field set to a non-default value so the round-trip
catches any field added to `Creature` without a matching encode +
decode entry. If you find yourself adding a field to `Creature`,
add a non-default value here too.
-}
fullyPopulatedCreature : Encounter.Creature
fullyPopulatedCreature =
    { name = "Smaug"
    , kind = "Adult Red Dragon"
    , initiative = 18
    , initiativeBonus = 4
    , currentHp = 256
    , maxHp = 367
    , tempHp = 12
    , armorClass = 19
    , speed = 40
    , conditions =
        [ { id = 1
          , name = "Frightened"
          , note = "of Lyra"
          , duration = DurationCountdown AtBegin 2 True
          , saveToEnd =
                Just
                    { ability = "WIS"
                    , dc = 16
                    , bonus = 3
                    , autoRoll = AutoRollAtEnd
                    }
          }
        , { id = 2
          , name = "Slowed"
          , note = "ice patch"
          , duration = DurationUntilTurn AtEnd OnNextTurn "Lyra"
          , saveToEnd = Nothing
          }
        ]
    , saveNotices =
        [ { id = 11, conditionName = "Charmed", turnsRemaining = 1 } ]
    , selected = True
    , cover = ThreeQuartersCover
    , concentrating = True
    , hiding = True
    , dodging = True
    , flying = True
    , flyHeight = 80
    , bloodied = True
    , deathSaves = { successes = 2, failures = 1 }
    , acceptingDeathSaves = True
    , reactionUsed = False
    , rechargeAbilities = []
    , readied = True
    , inactive = False
    , note = "boss"
    , memo = "legendary res used"
    , timer =
        Just
            { remaining = 3
            , phase = AtEnd
            , ringing = False
            , note = "spell ends"
            }
    , creatureId = Just "smaug-id"
    , legendaryActionsCount = 3
    , legendaryActionsLairBonus = 0
    , legendaryActionsUsed = Set.fromList [ 0, 1, 3 ]
    , legendaryResistanceCount = 3
    , legendaryResistanceLairBonus = 0
    , legendaryResistanceUsed = Set.fromList [ 0, 2 ]
    , isPlaceholder = False
    , creatureKind = "enemy"
    , race = "Dragon"
    , alignment = "chaotic evil"
    }



-- ── HELPERS ─────────────────────────────────────────────────────────────────


roundTripExpect : Encounter.Encounter -> Expect.Expectation
roundTripExpect enc =
    enc
        |> Wire.encodeEncounter
        |> D.decodeValue Wire.decodeEncounter
        |> Result.map ((==) enc)
        |> Result.mapError (D.errorToString >> (++) "decode failed: ")
        |> (\result ->
                case result of
                    Ok True ->
                        Expect.pass

                    Ok False ->
                        Expect.fail
                            ("round-trip changed the value; original=\n"
                                ++ Debug.toString enc
                                ++ "\nafter round-trip=\n"
                                ++ Debug.toString
                                    (Wire.encodeEncounter enc
                                        |> D.decodeValue Wire.decodeEncounter
                                    )
                            )

                    Err msg ->
                        Expect.fail msg
           )
