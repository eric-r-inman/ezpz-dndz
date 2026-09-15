module Ui.Condition.BundledTest exposing (suite)

import Dict
import Expect
import Msg exposing (DurationKind(..))
import Set
import Test exposing (Test, describe, test)
import Ui.Condition as ConditionUi
import Ui.Condition.Bundled as Bundled
import Update.Condition


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
        , test "loading any bundled preset yields a non-empty effective name (Apply stays enabled)" <|
            \_ ->
                let
                    blank =
                        ConditionUi.fresh "TestTarget"

                    presetsThatBreakApply =
                        Bundled.defaults
                            |> Dict.toList
                            |> List.filter
                                (\( name, preset ) ->
                                    ConditionUi.applyPreset name preset blank
                                        |> .name
                                        |> String.trim
                                        |> String.isEmpty
                                )
                            |> List.map Tuple.first
                in
                Expect.equal presetsThatBreakApply []
        , test "no retired name is still shipped" <|
            \_ ->
                Bundled.retiredNames
                    |> List.filter (\name -> Dict.member name Bundled.defaults)
                    |> Expect.equal []
        , test "every preset's name, note, and companions fit the editor's fields" <|
            \_ ->
                let
                    fits text =
                        String.length text <= Update.Condition.maxConditionNoteLength

                    overlong =
                        Bundled.defaults
                            |> Dict.toList
                            |> List.filter
                                (\( _, p ) ->
                                    not (List.all fits (p.customName :: p.note :: p.companions))
                                )
                            |> List.map Tuple.first
                in
                Expect.equal overlong []
        , test "no preset lists its own condition, or one twice, among its companions" <|
            \_ ->
                let
                    blank =
                        ConditionUi.fresh "TestTarget"

                    repeats =
                        Bundled.defaults
                            |> Dict.toList
                            |> List.filter
                                (\( name, preset ) ->
                                    List.member (ConditionUi.applyPreset name preset blank).name preset.companions
                                        || Set.size (Set.fromList preset.companions)
                                        /= List.length preset.companions
                                )
                            |> List.map Tuple.first
                in
                Expect.equal repeats []
        , test "Heroism lasts its minute and brings immunity to Frightened" <|
            \_ ->
                Dict.get "Heroism (Bard/Paladin)" Bundled.defaults
                    |> Maybe.map (\p -> ( p.durationKind, p.countdownTurns, p.companions ))
                    |> Expect.equal (Just ( DurKindCountdown, 10, [ "Immunity: Frightened" ] ))
        ]
