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
import Encounter.SaveChain as SaveChain exposing (EffectApply, HpEffect(..), SaveChain, SaveOutcome)
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
        , ( "effects", E.list encodeEffect o.effects )
        ]


{-| Decode an outcome, falling back to the pre-migration
`condition_name` / `condition_note` fields when `effects` is
absent — any preset already in `localStorage.saveChainPresets`
from before the multi-effect refactor still loads cleanly.
-}
outcomeDecoder : D.Decoder SaveOutcome
outcomeDecoder =
    D.map2 SaveOutcome
        (optionalField "hp" hpEffectDecoder NoHpEffect)
        (D.oneOf
            [ D.field "effects" (D.list effectDecoder)
            , legacyEffectsDecoder
            ]
        )


{-| Backward-compat: the pre-multi-effect wire had
`condition_name` / `condition_note` as top-level outcome
fields. Repackage them as a one-element effect list, or as
an empty list when the name was blank.
-}
legacyEffectsDecoder : D.Decoder (List EffectApply)
legacyEffectsDecoder =
    D.map2 (\n note -> ( n, note ))
        (optionalField "condition_name" D.string "")
        (optionalField "condition_note" D.string "")
        |> D.map
            (\( name, note ) ->
                if String.isEmpty (String.trim name) then
                    []

                else
                    [ { name = name, note = note } ]
            )


encodeEffect : EffectApply -> E.Value
encodeEffect e =
    E.object
        [ ( "name", E.string e.name )
        , ( "note", E.string e.note )
        ]


effectDecoder : D.Decoder EffectApply
effectDecoder =
    D.map2 EffectApply
        (D.field "name" D.string)
        (optionalField "note" D.string "")



-- ── HpEffect ─────────────────────────────────────────────────────


encodeHpEffect : HpEffect -> E.Value
encodeHpEffect h =
    case h of
        NoHpEffect ->
            E.object [ ( "kind", E.string "none" ) ]

        DealDamage s ->
            E.object [ ( "kind", E.string "damage" ), ( "amount", E.string s ) ]

        HealFor s ->
            E.object [ ( "kind", E.string "heal" ), ( "amount", E.string s ) ]

        HalfFailDamage ->
            E.object [ ( "kind", E.string "half_fail" ) ]


hpEffectDecoder : D.Decoder HpEffect
hpEffectDecoder =
    D.field "kind" D.string
        |> D.andThen
            (\kind ->
                case kind of
                    "damage" ->
                        D.field "amount" amountDecoder |> D.map DealDamage

                    "heal" ->
                        D.field "amount" amountDecoder |> D.map HealFor

                    "half_fail" ->
                        D.succeed HalfFailDamage

                    _ ->
                        D.succeed NoHpEffect
            )


{-| Accept either a JSON string (`"8d6"`) or a JSON int
(`28`) for the amount field. The int path keeps
backward-compat with the previous wire format so any preset
already in a user's `localStorage.saveChainPresets` still
loads cleanly after the string-amount migration.
-}
amountDecoder : D.Decoder String
amountDecoder =
    D.oneOf
        [ D.string
        , D.int |> D.map String.fromInt
        ]



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
