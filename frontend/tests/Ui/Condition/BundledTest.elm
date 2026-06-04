module Ui.Condition.BundledTest exposing (suite)

import Dict
import Expect
import Set
import Test exposing (Test, describe, test)
import Ui.Condition.Bundled as Bundled


suite : Test
suite =
    describe "Ui.Condition.Bundled"
        [ test "defaults dict ships at least 30 presets across the four categories" <|
            \_ ->
                Bundled.defaults
                    |> Dict.size
                    |> Expect.atLeast 30
        , test "every default preset carries one of the four advertised categories" <|
            \_ ->
                let
                    advertised =
                        Set.fromList Bundled.categories

                    actual =
                        Bundled.defaults
                            |> Dict.values
                            |> List.map .category
                            |> Set.fromList
                in
                Expect.equal (Set.diff actual advertised) Set.empty
        , test "every category is represented by at least one preset" <|
            \_ ->
                let
                    present =
                        Bundled.defaults
                            |> Dict.values
                            |> List.map .category
                            |> Set.fromList

                    missing =
                        Bundled.categories
                            |> List.filter (\c -> not (Set.member c present))
                in
                Expect.equal missing []
        , test "no default preset has both an empty conditionName and an empty customName" <|
            \_ ->
                let
                    invalid =
                        Bundled.defaults
                            |> Dict.toList
                            |> List.filter
                                (\( _, p ) ->
                                    String.isEmpty p.conditionName
                                        && String.isEmpty p.customName
                                )
                            |> List.map Tuple.first
                in
                Expect.equal invalid []
        ]
