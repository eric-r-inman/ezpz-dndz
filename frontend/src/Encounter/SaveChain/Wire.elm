module Encounter.SaveChain.Wire exposing
    ( encodePresets, decodePresets
    , encode, decode
    )

{-| JSON encode / decode for `SaveChain` presets so the GM's
saved chains survive across reloads. Payload is written to
`localStorage.saveChainPresets` as a `{ name → SaveChain }` object.

@docs encodePresets, decodePresets
@docs encode, decode

-}

import Compendium exposing (Ability(..))
import Dict exposing (Dict)
import Encounter.SaveChain as SaveChain exposing (HpEffect(..), SaveChain, SaveOutcome)
import Json.Decode as D
import Json.Encode as E



-- ── Presets dict ──────────────────────────────────────────────────


encodePresets : Dict String SaveChain -> E.Value
encodePresets presets =
    presets
        |> Dict.toList
        |> List.map (\( k, v ) -> ( k, encode v ))
        |> E.object


decodePresets : D.Decoder (Dict String SaveChain)
decodePresets =
    D.dict decode



-- ── SaveChain ────────────────────────────────────────────────────


encode : SaveChain -> E.Value
encode chain =
    E.object
        [ ( "name", E.string chain.name )
        , ( "save_ability", encodeAbility chain.saveAbility )
        , ( "save_dc"
          , case chain.saveDc of
                Just n ->
                    E.int n

                Nothing ->
                    E.null
          )
        , ( "on_fail", encodeOutcome chain.onFail )
        , ( "on_success", encodeOutcome chain.onSuccess )
        ]


decode : D.Decoder SaveChain
decode =
    D.map5 SaveChain
        (D.field "name" D.string)
        (D.field "save_ability" abilityDecoder)
        (optionalField "save_dc" (D.nullable D.int) Nothing)
        (optionalField "on_fail" outcomeDecoder SaveChain.empty.onFail)
        (optionalField "on_success" outcomeDecoder SaveChain.empty.onSuccess)


{-| Backport of `Json.Decode.Pipeline.optional`. Falls back to
`default` when the field is absent or the inner decoder fails —
matches the wire-tolerance the other preset decoders rely on.
-}
optionalField : String -> D.Decoder a -> a -> D.Decoder a
optionalField key inner default =
    D.oneOf
        [ D.field key inner
        , D.succeed default
        ]



-- ── SaveOutcome ──────────────────────────────────────────────────


encodeOutcome : SaveOutcome -> E.Value
encodeOutcome o =
    E.object
        [ ( "hp", encodeHpEffect o.hp )
        , ( "condition_name", E.string o.conditionName )
        , ( "condition_note", E.string o.conditionNote )
        ]


outcomeDecoder : D.Decoder SaveOutcome
outcomeDecoder =
    D.map3 SaveOutcome
        (optionalField "hp" hpEffectDecoder NoHpEffect)
        (optionalField "condition_name" D.string "")
        (optionalField "condition_note" D.string "")



-- ── HpEffect ─────────────────────────────────────────────────────


encodeHpEffect : HpEffect -> E.Value
encodeHpEffect h =
    case h of
        NoHpEffect ->
            E.object [ ( "kind", E.string "none" ) ]

        DealDamage n ->
            E.object [ ( "kind", E.string "damage" ), ( "amount", E.int n ) ]

        HealFor n ->
            E.object [ ( "kind", E.string "heal" ), ( "amount", E.int n ) ]

        HalfFailDamage ->
            E.object [ ( "kind", E.string "half_fail" ) ]


hpEffectDecoder : D.Decoder HpEffect
hpEffectDecoder =
    D.field "kind" D.string
        |> D.andThen
            (\kind ->
                case kind of
                    "damage" ->
                        D.field "amount" D.int |> D.map DealDamage

                    "heal" ->
                        D.field "amount" D.int |> D.map HealFor

                    "half_fail" ->
                        D.succeed HalfFailDamage

                    _ ->
                        D.succeed NoHpEffect
            )



-- ── Ability ──────────────────────────────────────────────────────


encodeAbility : Ability -> E.Value
encodeAbility a =
    E.string (abilityString a)


abilityString : Ability -> String
abilityString a =
    case a of
        Str ->
            "str"

        Dex ->
            "dex"

        Con ->
            "con"

        Int_ ->
            "int"

        Wis ->
            "wis"

        Cha ->
            "cha"


abilityDecoder : D.Decoder Ability
abilityDecoder =
    D.string
        |> D.andThen
            (\s ->
                case String.toLower s of
                    "str" ->
                        D.succeed Str

                    "dex" ->
                        D.succeed Dex

                    "con" ->
                        D.succeed Con

                    "int" ->
                        D.succeed Int_

                    "wis" ->
                        D.succeed Wis

                    "cha" ->
                        D.succeed Cha

                    _ ->
                        D.fail ("Unknown ability: " ++ s)
            )
