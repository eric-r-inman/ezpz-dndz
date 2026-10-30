module Encounter.TreasureBreakdownTest exposing (suite)

{-| The By creature breakdown stays in step with the roll's totals
when the DM removes a row or re-rolls a category.
-}

import Encounter.Treasure as Treasure exposing (CreatureContribution, TreasureRoll)
import Expect
import Test exposing (Test, describe, test)


gem : String -> Treasure.GemItem
gem name =
    { name = name, valueGp = 10 }


contribution : String -> Int -> List Treasure.GemItem -> CreatureContribution
contribution name gold gems =
    { creatureName = name
    , coins = { copper = 3, silver = 0, electrum = 0, gold = gold, platinum = 0 }
    , gems = gems
    , art = []
    , magic = []
    , mundane = []
    , weapons = []
    , armor = []
    , loot = []
    , bracket = Treasure.B1to4
    }


{-| An individual roll's totals are its creatures' shares joined in
order, the way the generator builds them.
-}
rollOf : List CreatureContribution -> TreasureRoll
rollOf contributions =
    { kind = Treasure.Individual
    , bracket = Treasure.B1to4
    , coins =
        { copper = List.sum (List.map (.coins >> .copper) contributions)
        , silver = 0
        , electrum = 0
        , gold = List.sum (List.map (.coins >> .gold) contributions)
        , platinum = 0
        }
    , gems = List.concatMap .gems contributions
    , art = []
    , magic = []
    , mundane = []
    , weapons = []
    , armor = []
    , source = Nothing
    , contributions = contributions
    , loot = []
    }


goblins : TreasureRoll
goblins =
    rollOf
        [ contribution "Goblin" 4 [ gem "Agate" ]
        , contribution "Goblin 2" 6 [ gem "Jasper", gem "Onyx" ]
        ]


suite : Test
suite =
    describe "Treasure breakdown"
        [ test "removing a gem takes it from the creature that rolled it" <|
            \_ ->
                Treasure.removeGem 1 goblins
                    |> .contributions
                    |> List.map (\c -> ( c.creatureName, List.map .name c.gems ))
                    |> Expect.equal [ ( "Goblin", [ "Agate" ] ), ( "Goblin 2", [ "Onyx" ] ) ]
        , test "clearing a denomination clears it for every creature" <|
            \_ ->
                Treasure.clearCoin "gold" goblins
                    |> .contributions
                    |> List.map (.coins >> .gold)
                    |> Expect.equal [ 0, 0 ]
        , test "a re-rolled category replaces each creature's share and keeps the rest" <|
            \_ ->
                goblins
                    |> Treasure.withCategoryFrom Treasure.GemsCategory
                        (rollOf
                            [ contribution "Goblin" 99 [ gem "Pearl" ]
                            , contribution "Goblin 2" 99 []
                            ]
                        )
                    |> .contributions
                    |> List.map (\c -> ( c.coins.gold, List.map .name c.gems ))
                    |> Expect.equal [ ( 4, [ "Pearl" ] ), ( 6, [] ) ]
        , test "a re-roll made for other creatures drops the breakdown" <|
            \_ ->
                goblins
                    |> Treasure.withCategoryFrom Treasure.CoinsCategory
                        (rollOf [ contribution "Ogre" 50 [] ])
                    |> Expect.all
                        [ .contributions >> Expect.equal []
                        , .coins >> .gold >> Expect.equal 50
                        ]
        ]
