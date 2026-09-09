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
import Encounter
import Encounter.SaveChain as SaveChain exposing (EffectApply, EffectDuration(..), EffectSave, HpEffect(..), SaveChain, SaveOutcome, TurnRef(..))
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
        , ( "immunity", encodeMaybe encodeDuration chain.immunity )
        , ( "area", encodeMaybe (\phase -> E.string (phaseString phase)) chain.area )
        ]


decode : D.Decoder SaveChain
decode =
    D.map7 SaveChain
        (D.field "name" D.string)
        (D.field "save_ability" abilityDecoder)
        (optionalField "save_dc" (D.nullable D.int) Nothing)
        (optionalField "on_fail" outcomeDecoder SaveChain.empty.onFail)
        (optionalField "on_success" outcomeDecoder SaveChain.empty.onSuccess)
        (optionalField "immunity" (D.nullable durationDecoder) Nothing)
        (optionalField "area" (D.nullable phaseDecoder) Nothing)


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


encodeMaybe : (a -> E.Value) -> Maybe a -> E.Value
encodeMaybe enc m =
    case m of
        Just v ->
            enc v

        Nothing ->
            E.null



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
                let
                    blank =
                        SaveChain.emptyEffect
                in
                if String.isEmpty (String.trim name) then
                    []

                else
                    [ { blank | name = name, note = note } ]
            )


{-| `save_to_end` stays the mode string the wire has always
carried; the failed-save outcome and the damage trigger ride
beside it as `on_failed_save` and `on_damage`, each set whenever
the effect opts in and null otherwise.
-}
encodeEffect : EffectApply -> E.Value
encodeEffect e =
    E.object
        [ ( "name", E.string e.name )
        , ( "note", E.string e.note )
        , ( "save_to_end"
          , encodeMaybe (\s -> E.string (autoRollString s.autoRoll)) e.saveToEnd
          )
        , ( "on_failed_save"
          , encodeMaybe (\s -> encodeFailedSave s.onFail) e.saveToEnd
          )
        , ( "on_damage"
          , encodeMaybe (\s -> E.string (damageTriggerString s.onDamage)) e.saveToEnd
          )
        , ( "duration", encodeDuration e.duration )
        , ( "with", E.string e.with )
        ]


effectDecoder : D.Decoder EffectApply
effectDecoder =
    D.map5 EffectApply
        (D.field "name" D.string)
        (optionalField "note" D.string "")
        (optionalField "duration" durationDecoder LastsUntilRemoved)
        (D.map3 effectSave
            (optionalField "save_to_end" saveToEndDecoder Nothing)
            (optionalField "on_failed_save" (D.nullable failedSaveDecoder) Nothing)
            (optionalField "on_damage" (D.nullable damageTriggerDecoder) Nothing)
        )
        (optionalField "with" D.string "")


effectSave :
    Maybe Encounter.AutoRollMode
    -> Maybe Encounter.FailedSave
    -> Maybe Encounter.DamageTrigger
    -> Maybe EffectSave
effectSave mode onFail onDamage =
    Maybe.map
        (\m ->
            { autoRoll = m
            , onFail = Maybe.withDefault Encounter.noFailedSave onFail
            , onDamage = Maybe.withDefault Encounter.NoDamageTrigger onDamage
            }
        )
        mode


damageTriggerString : Encounter.DamageTrigger -> String
damageTriggerString trigger =
    case trigger of
        Encounter.NoDamageTrigger ->
            "none"

        Encounter.AskOnDamage ->
            "ask"

        Encounter.RollOnDamage ->
            "roll"

        Encounter.RollOnDamageWithAdvantage ->
            "roll_advantage"


{-| An unknown token reads as no trigger, the value every effect
had before damage triggers existed.
-}
damageTriggerDecoder : D.Decoder Encounter.DamageTrigger
damageTriggerDecoder =
    D.string
        |> D.map
            (\s ->
                case s of
                    "ask" ->
                        Encounter.AskOnDamage

                    "roll" ->
                        Encounter.RollOnDamage

                    "roll_advantage" ->
                        Encounter.RollOnDamageWithAdvantage

                    _ ->
                        Encounter.NoDamageTrigger
            )


{-| `save_to_end` on the wire accepts three shapes:

  - String enum (`"manual"` / `"at_begin"` / `"at_end"` /
    `"ask_at_end"`) — the canonical form, parses to
    `Just AutoRollMode`.
  - Bool (`true` / `false`) — the pre-mode wire from the
    previous refactor. `true` maps to the default
    `AutoRollAtEnd`; `false` maps to `Nothing`.
  - Null / absent — same as `false` → `Nothing`.

-}
saveToEndDecoder : D.Decoder (Maybe Encounter.AutoRollMode)
saveToEndDecoder =
    D.oneOf
        [ D.null Nothing
        , D.string
            |> D.andThen
                (\s ->
                    case s of
                        "manual" ->
                            D.succeed (Just Encounter.AutoRollManual)

                        "at_begin" ->
                            D.succeed (Just Encounter.AutoRollAtBegin)

                        "at_end" ->
                            D.succeed (Just Encounter.AutoRollAtEnd)

                        "ask_at_end" ->
                            D.succeed (Just Encounter.AutoRollAskAtEnd)

                        _ ->
                            D.succeed Nothing
                )
        , D.bool
            |> D.map
                (\b ->
                    if b then
                        Just Encounter.AutoRollAtEnd

                    else
                        Nothing
                )
        ]


autoRollString : Encounter.AutoRollMode -> String
autoRollString mode =
    case mode of
        Encounter.AutoRollManual ->
            "manual"

        Encounter.AutoRollAtBegin ->
            "at_begin"

        Encounter.AutoRollAtEnd ->
            "at_end"

        Encounter.AutoRollAskAtEnd ->
            "ask_at_end"


encodeFailedSave : Encounter.FailedSave -> E.Value
encodeFailedSave f =
    E.object
        [ ( "damage", encodeMaybe E.string f.damage )
        , ( "becomes", encodeMaybe E.string f.becomes )
        ]


failedSaveDecoder : D.Decoder Encounter.FailedSave
failedSaveDecoder =
    D.map2 Encounter.FailedSave
        (optionalField "damage" (D.nullable D.string) Nothing)
        (optionalField "becomes" (D.nullable D.string) Nothing)



-- ── EffectDuration ───────────────────────────────────────────────


encodeDuration : EffectDuration -> E.Value
encodeDuration duration =
    case duration of
        LastsUntilRemoved ->
            E.object [ ( "kind", E.string "manual" ) ]

        LastsUntilTurn phase ref ->
            E.object
                ([ ( "kind", E.string "until_turn" )
                 , ( "phase", E.string (phaseString phase) )
                 ]
                    ++ turnRefFields ref
                )

        LastsThisTurn ->
            E.object [ ( "kind", E.string "this_turn" ) ]

        LastsForTurns phase turns ->
            E.object
                [ ( "kind", E.string "countdown" )
                , ( "phase", E.string (phaseString phase) )
                , ( "turns", E.int turns )
                ]

        LastsOneMinute ->
            E.object [ ( "kind", E.string "one_minute" ) ]


turnRefFields : TurnRef -> List ( String, E.Value )
turnRefFields ref =
    case ref of
        TurnOfBearer ->
            [ ( "of", E.string "bearer" ) ]

        TurnOfActive ->
            [ ( "of", E.string "active" ) ]

        TurnOf name ->
            [ ( "of", E.string "named" ), ( "name", E.string name ) ]


{-| An unknown kind reads as "until removed", the value every
effect had before durations existed.
-}
durationDecoder : D.Decoder EffectDuration
durationDecoder =
    optionalField "kind" D.string "manual"
        |> D.andThen
            (\kind ->
                case kind of
                    "until_turn" ->
                        D.map2 LastsUntilTurn
                            (optionalField "phase" phaseDecoder Encounter.AtEnd)
                            turnRefDecoder

                    "countdown" ->
                        D.map2 LastsForTurns
                            (optionalField "phase" phaseDecoder Encounter.AtEnd)
                            (optionalField "turns" D.int 1)

                    "one_minute" ->
                        D.succeed LastsOneMinute

                    "this_turn" ->
                        D.succeed LastsThisTurn

                    _ ->
                        D.succeed LastsUntilRemoved
            )


turnRefDecoder : D.Decoder TurnRef
turnRefDecoder =
    optionalField "of" D.string "bearer"
        |> D.andThen
            (\of_ ->
                case of_ of
                    "active" ->
                        D.succeed TurnOfActive

                    "named" ->
                        D.map TurnOf (optionalField "name" D.string "")

                    _ ->
                        D.succeed TurnOfBearer
            )


phaseString : Encounter.TurnPhase -> String
phaseString phase =
    case phase of
        Encounter.AtBegin ->
            "at_begin"

        Encounter.AtEnd ->
            "at_end"


phaseDecoder : D.Decoder Encounter.TurnPhase
phaseDecoder =
    D.string
        |> D.map
            (\s ->
                if s == "at_begin" then
                    Encounter.AtBegin

                else
                    Encounter.AtEnd
            )



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

        DrainDamage s ->
            E.object [ ( "kind", E.string "drain" ), ( "amount", E.string s ) ]


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

                    "drain" ->
                        D.field "amount" amountDecoder |> D.map DrainDamage

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
