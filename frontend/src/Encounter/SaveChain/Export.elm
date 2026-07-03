module Encounter.SaveChain.Export exposing (asElm)

{-| Render a [`SaveChain`](Encounter-SaveChain#SaveChain) as a
copy-pasteable Elm source snippet, suitable for promoting a
user-authored preset into
[`Encounter.SaveChain.Bundled.defaults`](Encounter-SaveChain-Bundled#defaults).

The output is the raw record literal wrapped in a function
declaration, e.g.

    myFireball : SaveChain
    myFireball =
        { name = "My Fireball"
        , saveAbility = Dex
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

We deliberately don't use the `effect` / `effectSvEoT` /
`damageOnly` helpers that live inside `Bundled.elm` — the raw
form is easier to generate reliably (no ambiguity around which
helper matches which shape), and the reviewer converting the
snippet to helper form during promotion catches any
already-covered spell they might otherwise duplicate.

@docs asElm

-}

import Compendium
import Encounter
import Encounter.SaveChain exposing (EffectApply, HpEffect(..), SaveChain, SaveOutcome)


{-| Return the multiline Elm source for `chain`. Includes a
header comment reminding the reader where to paste and, when
applicable, that the value must also be added to `defaults`.
-}
asElm : SaveChain -> String
asElm chain =
    let
        funcName =
            camelize chain.name
                |> emptyToDefault "myPreset"

        header =
            [ "-- Paste into Encounter/SaveChain/Bundled.elm.  Rename the"
            , "-- function and add its name to `defaults` if you want to"
            , "-- ship it as a bundled preset."
            , ""
            ]

        head =
            [ funcName ++ " : SaveChain"
            , funcName ++ " ="
            , "    { name = " ++ elmString chain.name
            , "    , saveAbility = " ++ abilityToElm chain.saveAbility
            , "    , saveDc = " ++ maybeIntToElm chain.saveDc
            , "    , onFail ="
            ]

        onFailLines =
            indentAll 8 (outcomeLines chain.onFail)

        successHeader =
            [ "    , onSuccess =" ]

        onSuccessLines =
            indentAll 8 (outcomeLines chain.onSuccess)

        tail =
            [ "    }" ]
    in
    String.join "\n"
        (header
            ++ head
            ++ onFailLines
            ++ successHeader
            ++ onSuccessLines
            ++ tail
        )



-- ── record body helpers ────────────────────────────────────────


outcomeLines : SaveOutcome -> List String
outcomeLines o =
    [ "{ hp = " ++ hpEffectToElm o.hp
    , ", effects =" ++ effectsToElmTail o.effects
    , "}"
    ]


effectsToElmTail : List EffectApply -> String
effectsToElmTail effects =
    case effects of
        [] ->
            " []"

        _ ->
            "\n    " ++ effectsToElm effects


effectsToElm : List EffectApply -> String
effectsToElm effects =
    let
        rendered =
            List.map effectToElm effects
    in
    case rendered of
        [] ->
            "[]"

        first :: rest ->
            String.join "\n    "
                (("[ " ++ first) :: List.map (\r -> ", " ++ r) rest ++ [ "]" ])


effectToElm : EffectApply -> String
effectToElm e =
    "{ name = "
        ++ elmString e.name
        ++ ", note = "
        ++ elmString e.note
        ++ ", saveToEnd = "
        ++ maybeAutoRollToElm e.saveToEnd
        ++ " }"


hpEffectToElm : HpEffect -> String
hpEffectToElm hp =
    case hp of
        NoHpEffect ->
            "NoHpEffect"

        DealDamage amt ->
            "DealDamage " ++ elmString amt

        HealFor amt ->
            "HealFor " ++ elmString amt

        HalfFailDamage ->
            "HalfFailDamage"


maybeAutoRollToElm : Maybe Encounter.AutoRollMode -> String
maybeAutoRollToElm m =
    case m of
        Nothing ->
            "Nothing"

        Just mode ->
            "Just " ++ autoRollToElm mode


autoRollToElm : Encounter.AutoRollMode -> String
autoRollToElm mode =
    case mode of
        Encounter.AutoRollManual ->
            "AutoRollManual"

        Encounter.AutoRollAtBegin ->
            "AutoRollAtBegin"

        Encounter.AutoRollAtEnd ->
            "AutoRollAtEnd"


abilityToElm : Compendium.Ability -> String
abilityToElm a =
    case a of
        Compendium.Str ->
            "Str"

        Compendium.Dex ->
            "Dex"

        Compendium.Con ->
            "Con"

        Compendium.Int_ ->
            "Int_"

        Compendium.Wis ->
            "Wis"

        Compendium.Cha ->
            "Cha"


maybeIntToElm : Maybe Int -> String
maybeIntToElm m =
    case m of
        Nothing ->
            "Nothing"

        Just n ->
            "Just " ++ String.fromInt n



-- ── string + indent helpers ────────────────────────────────────


elmString : String -> String
elmString s =
    let
        escaped =
            s
                |> String.replace "\\" "\\\\"
                |> String.replace "\"" "\\\""
                |> String.replace "\n" "\\n"
    in
    "\"" ++ escaped ++ "\""


indentAll : Int -> List String -> List String
indentAll n lines =
    let
        pad =
            String.repeat n " "
    in
    List.map (\line -> pad ++ line) lines


{-| Turn a display name into a camelCase Elm identifier. Strips
non-alphanumerics, lowercases the first codepoint, keeps the
rest of a run in its original case (so "DEX Save" becomes
`dEXSave`, which is ugly but valid — the reviewer will rename).
Callers pass an empty string when the preset has no name; the
[`emptyToDefault`](#emptyToDefault) fallback substitutes a
sane placeholder in that case.
-}
camelize : String -> String
camelize s =
    let
        parts =
            s
                |> String.words
                |> List.concatMap
                    (\w ->
                        String.split "'" w
                            |> List.concatMap (String.split "-")
                            |> List.concatMap (String.split "(")
                            |> List.concatMap (String.split ")")
                    )
                |> List.filter (not << String.isEmpty)
                |> List.map (String.filter isIdentChar)
                |> List.filter (not << String.isEmpty)

        toCamel idx w =
            if idx == 0 then
                lowercaseFirst w

            else
                capitaliseFirst w
    in
    parts
        |> List.indexedMap toCamel
        |> String.concat


isIdentChar : Char -> Bool
isIdentChar c =
    Char.isAlphaNum c


lowercaseFirst : String -> String
lowercaseFirst s =
    case String.uncons s of
        Just ( c, rest ) ->
            String.fromChar (Char.toLower c) ++ rest

        Nothing ->
            s


capitaliseFirst : String -> String
capitaliseFirst s =
    case String.uncons s of
        Just ( c, rest ) ->
            String.fromChar (Char.toUpper c) ++ rest

        Nothing ->
            s


emptyToDefault : String -> String -> String
emptyToDefault fallback s =
    if String.isEmpty s then
        fallback

    else
        s
