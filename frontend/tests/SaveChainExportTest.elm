module SaveChainExportTest exposing (suite)

{-| Golden-string tests for `Encounter.SaveChain.Export.asElm`.

The exporter powers the "📤 Export as Elm" button in the Save
Chain modal — its output is pasted verbatim into
`Encounter/SaveChain/Bundled.elm`, so a regression in the
literal shape shows up as a compile error in whoever picks up
the promoted preset next. Lock the format in with a small
matrix that exercises every branch of the generator:

  - `saveDc = Nothing` and `saveDc = Just N`
  - each `HpEffect` constructor (`NoHpEffect`, `DealDamage`,
    `HealFor`, `HalfFailDamage`)
  - `effects = []` and `effects = [_, _]`
  - `saveToEnd = Nothing`, `Just AutoRollAtEnd`,
    `Just AutoRollAtBegin`, `Just AutoRollManual`
  - all six `Ability` variants (`Str` / `Dex` / `Con` / `Int_`
    / `Wis` / `Cha`)
  - the empty-name → `myPreset` fallback

-}

import Compendium
import Encounter
import Encounter.SaveChain exposing (HpEffect(..), SaveChain)
import Encounter.SaveChain.Export as Export
import Expect
import Test exposing (Test, describe, test)


{-| A canonical Hold-Person-ish chain used across a few cases.
-}
holdPerson : SaveChain
holdPerson =
    { name = "Hold Person (2nd)"
    , saveAbility = Compendium.Wis
    , saveDc = Nothing
    , onFail =
        { hp = NoHpEffect
        , effects =
            [ { name = "Paralyzed"
              , note = ""
              , saveToEnd = Just Encounter.AutoRollAtEnd
              }
            ]
        }
    , onSuccess =
        { hp = NoHpEffect
        , effects = []
        }
    }


fireball : SaveChain
fireball =
    { name = "Fireball"
    , saveAbility = Compendium.Dex
    , saveDc = Just 15
    , onFail =
        { hp = DealDamage "8d6"
        , effects = []
        }
    , onSuccess =
        { hp = HalfFailDamage
        , effects = []
        }
    }


nameFallbackSuite : Test
nameFallbackSuite =
    describe "camelCase identifier"
        [ test "empty name falls back to myPreset" <|
            \_ ->
                let
                    blank =
                        { holdPerson | name = "" }
                in
                Export.asElm blank
                    |> String.contains "myPreset : SaveChain"
                    |> Expect.equal True
        , test "single-word title lowercases the first letter" <|
            \_ ->
                let
                    slow =
                        { holdPerson | name = "Slow" }
                in
                Export.asElm slow
                    |> String.contains "slow : SaveChain"
                    |> Expect.equal True
        , test "multi-word title camelcases each word after the first" <|
            \_ ->
                -- "Hold Person (2nd)" → "holdPerson2nd" (valid
                -- Elm identifier; the parenthesised suffix is
                -- retained rather than dropped because a name
                -- like "Bane" vs "Bane (upcast)" could otherwise
                -- collide).  The reviewer renames during
                -- promotion, so we only lock in that the first
                -- two words are correctly camelCased.
                Export.asElm holdPerson
                    |> String.contains "holdPerson"
                    |> Expect.equal True
        ]


dcSuite : Test
dcSuite =
    describe "saveDc rendering"
        [ test "Nothing renders as Nothing" <|
            \_ ->
                Export.asElm holdPerson
                    |> String.contains ", saveDc = Nothing"
                    |> Expect.equal True
        , test "Just N renders as Just N" <|
            \_ ->
                Export.asElm fireball
                    |> String.contains ", saveDc = Just 15"
                    |> Expect.equal True
        ]


hpEffectSuite : Test
hpEffectSuite =
    let
        withHp hp =
            { fireball
                | onFail = { hp = hp, effects = [] }
                , onSuccess = { hp = NoHpEffect, effects = [] }
            }
    in
    describe "HpEffect rendering"
        [ test "NoHpEffect" <|
            \_ ->
                Export.asElm (withHp NoHpEffect)
                    |> String.contains "hp = NoHpEffect"
                    |> Expect.equal True
        , test "DealDamage escapes the amount as an Elm string literal" <|
            \_ ->
                Export.asElm (withHp (DealDamage "8d6"))
                    |> String.contains "hp = DealDamage \"8d6\""
                    |> Expect.equal True
        , test "HealFor renders with a string arg" <|
            \_ ->
                Export.asElm (withHp (HealFor "2d4+2"))
                    |> String.contains "hp = HealFor \"2d4+2\""
                    |> Expect.equal True
        , test "HalfFailDamage is a bare constructor" <|
            \_ ->
                Export.asElm fireball
                    |> String.contains "hp = HalfFailDamage"
                    |> Expect.equal True
        ]


saveToEndSuite : Test
saveToEndSuite =
    let
        withEffectMode m =
            { holdPerson
                | onFail =
                    { hp = NoHpEffect
                    , effects =
                        [ { name = "X", note = "", saveToEnd = m } ]
                    }
            }
    in
    describe "saveToEnd rendering"
        [ test "Nothing → literal Nothing" <|
            \_ ->
                Export.asElm (withEffectMode Nothing)
                    |> String.contains "saveToEnd = Nothing"
                    |> Expect.equal True
        , test "AutoRollAtEnd" <|
            \_ ->
                Export.asElm (withEffectMode (Just Encounter.AutoRollAtEnd))
                    |> String.contains "saveToEnd = Just AutoRollAtEnd"
                    |> Expect.equal True
        , test "AutoRollAtBegin" <|
            \_ ->
                Export.asElm (withEffectMode (Just Encounter.AutoRollAtBegin))
                    |> String.contains "saveToEnd = Just AutoRollAtBegin"
                    |> Expect.equal True
        , test "AutoRollManual" <|
            \_ ->
                Export.asElm (withEffectMode (Just Encounter.AutoRollManual))
                    |> String.contains "saveToEnd = Just AutoRollManual"
                    |> Expect.equal True
        ]


abilitySuite : Test
abilitySuite =
    let
        withAbility a =
            { holdPerson | saveAbility = a }

        expectContains a token =
            \_ ->
                Export.asElm (withAbility a)
                    |> String.contains (", saveAbility = " ++ token)
                    |> Expect.equal True
    in
    describe "saveAbility rendering (each Ability variant)"
        [ test "Str" (expectContains Compendium.Str "Str")
        , test "Dex" (expectContains Compendium.Dex "Dex")
        , test "Con" (expectContains Compendium.Con "Con")
        , test "Int_" (expectContains Compendium.Int_ "Int_")
        , test "Wis" (expectContains Compendium.Wis "Wis")
        , test "Cha" (expectContains Compendium.Cha "Cha")
        ]


headerSuite : Test
headerSuite =
    describe "paste-hint header"
        [ test "always includes the promote-to-Bundled reminder" <|
            \_ ->
                Export.asElm fireball
                    |> String.contains "Paste into Encounter/SaveChain/Bundled.elm"
                    |> Expect.equal True
        , test "reminds the reader to add to defaults" <|
            \_ ->
                Export.asElm fireball
                    |> String.contains "add its name to `defaults`"
                    |> Expect.equal True
        ]


suite : Test
suite =
    describe "Encounter.SaveChain.Export.asElm"
        [ nameFallbackSuite
        , dcSuite
        , hpEffectSuite
        , saveToEndSuite
        , abilitySuite
        , headerSuite
        ]
