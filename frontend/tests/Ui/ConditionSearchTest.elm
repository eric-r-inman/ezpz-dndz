module Ui.ConditionSearchTest exposing (suite)

import Dict
import Expect
import Test exposing (Test, describe, test)
import Ui.Condition as ConditionUi
import Ui.Condition.Bundled as Bundled


suite : Test
suite =
    describe "Ui.Condition.matchesSearch"
        [ test "an empty box leaves every preset in the menu" <|
            \_ ->
                Bundled.defaults
                    |> Dict.keys
                    |> List.filter (ConditionUi.matchesSearch "")
                    |> List.length
                    |> Expect.equal (Dict.size Bundled.defaults)
        , test "a box holding only spaces leaves every preset in the menu" <|
            \_ ->
                Bundled.defaults
                    |> Dict.keys
                    |> List.filter (ConditionUi.matchesSearch "   ")
                    |> List.length
                    |> Expect.equal (Dict.size Bundled.defaults)
        , test "a query matches case-insensitively and inside the name" <|
            \_ ->
                ConditionUi.matchesSearch "word stun" "Power Word Stun"
                    |> Expect.equal True
        , test "a query nothing answers empties the menu" <|
            \_ ->
                Bundled.defaults
                    |> Dict.keys
                    |> List.filter (ConditionUi.matchesSearch "zzyzx")
                    |> Expect.equal []
        , test "every bundled preset is findable by its own name" <|
            \_ ->
                Bundled.defaults
                    |> Dict.keys
                    |> List.filter (\name -> not (ConditionUi.matchesSearch name name))
                    |> Expect.equal []
        ]
