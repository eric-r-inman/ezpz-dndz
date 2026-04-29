module Dice exposing
    ( Dice, Sign(..), Expression, Roll, RollGroup, RolledDie, RollKind(..), Error(..), History, Segment(..), Source, manualSource
    , parse, expressionToString, scan
    , emptyHistory, push, historyEntries, maxHistoryEntries
    , generator, advantageGenerator, disadvantageGenerator, coinGenerator
    , rollCmd, advantageCmd, disadvantageCmd, coinCmd, batchRollCmd
    , encodeRoll, decodeRoll
    )

{-| Pure dice-roller domain layer.

Owns dice notation parsing, the random-roll evaluator, and a bounded
in-memory history of past rolls. Like `Encounter`, this module
imports nothing from `Html`, `Browser`, or `Url` — UI code dispatches
into it but never the other way round, so alternate UI layouts can
share the same engine.

The notation we parse mirrors what the original JS dice-roller
accepted, so port plans stay one-for-one:

  - Standard: `1d6`, `2d8+3`, `3d10-2`
  - Compound: `1d8 + 2d6`, `2d6 - 1d4 + 5`
  - Damage tagged: `2d6+3 fire damage`, `1d8 piercing`
  - Stat-block avg: `7 (1d8 + 3)` — the leading "7" and parens are
    stripped; the inner formula becomes the parsed expression.

Advantage / disadvantage / coin flip have their own generators rather
than custom syntax; the JS UI worked the same way.


# Types

@docs Dice, Sign, Expression, Roll, RollGroup, RolledDie, RollKind, Error, History, Segment, Source, manualSource


# Parsing

@docs parse, expressionToString, scan


# History

@docs emptyHistory, push, historyEntries, maxHistoryEntries


# Rolling — generators

For when you need a `Random.Generator` directly (testing, composition).

@docs generator, advantageGenerator, disadvantageGenerator, coinGenerator


# Rolling — Cmds

The convenient call site for `update`. Each `*Cmd` reads `Time.now`,
seeds the RNG with the millisecond timestamp, runs the appropriate
generator, and stamps the resulting `Roll` with that timestamp.

@docs rollCmd, advantageCmd, disadvantageCmd, coinCmd, batchRollCmd


# JSON

For wire-format persistence (the server stores the history file as
JSON). The shapes are stable; if you change them you'll need to
clear out any existing `dice-history.json`.

@docs encodeRoll, decodeRoll

-}

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Parser exposing ((|.), (|=), Parser)
import Random
import Task
import Time



-- TYPES


{-| Sign of a dice term in a compound expression. `1d8 + 2d6` reads
the second group as `Positive`; `2d6 - 1d4` reads the second as
`Negative`.
-}
type Sign
    = Positive
    | Negative


{-| One dice group: count + face count + sign.

`count` is clamped to 1..99 by the parser. `faces` accepts any
positive integer for forward compatibility, though the standard
buttons stick to 4 / 6 / 8 / 10 / 12 / 20 / 100.

-}
type alias Dice =
    { count : Int
    , faces : Int
    , sign : Sign
    }


{-| A parsed dice expression.

Holds zero-or-more dice groups, a signed integer constant, and an
optional damage type tag. Constants accumulate across the expression,
so `1d6 + 2 - 1` parses with `constant = 1`.

Examples (with `Positive` and `Negative` abbreviated `+` / `-`):

  - `1d6` → `{ dice = [1d6+], constant = 0, damageType = Nothing }`
  - `2d8+3` → `{ dice = [2d8+], constant = 3, damageType = Nothing }`
  - `2d6+3 fire` → `{ dice = [2d6+], constant = 3, damageType = Just "fire" }`
  - `1d8 + 2d6` → `{ dice = [1d8+, 2d6+], constant = 0, damageType = Nothing }`
  - `2d6 - 1d4` → `{ dice = [2d6+, 1d4-], constant = 0, damageType = Nothing }`

-}
type alias Expression =
    { dice : List Dice
    , constant : Int
    , damageType : Maybe String
    }


{-| One face from one rolled die. `kept = False` if the face was
dropped by a keep rule (advantage drops the lower of two d20s).
-}
type alias RolledDie =
    { face : Int
    , kept : Bool
    }


{-| All faces rolled for one Dice group, plus the group's signed sum.
-}
type alias RollGroup =
    { dice : Dice
    , rolled : List RolledDie
    , subtotal : Int
    }


{-| The five distinct roll kinds. `Standard` covers normal rolls
(including compound); `Advantage` / `Disadvantage` are d20-specific
shortcuts that always roll twice and keep one; `Coin` is the
50/50 flip the JS roller had.
-}
type RollKind
    = Standard
    | Advantage
    | Disadvantage
    | Coin


{-| Where a roll was triggered from. Lets the dice history show
"Damage → Brakka, Ogre Brute" rather than just "rolled 2d6+3."

  - `feature` is a short label like "Damage", "Heal", "Manual",
    "Stat block".
  - `target` is whoever the roll affects (a creature name) when that
    makes sense; `Nothing` for source-less rolls like the standalone
    dice modal.

This is intentionally a free-form record rather than an enum so the
domain layer doesn't have to know every possible feature in advance.
Each call site picks its own labels; the UI just renders them.

-}
type alias Source =
    { feature : String
    , target : Maybe String
    }


{-| The default source applied to rolls that haven't been tagged.
Used by the standalone dice modal and as a fallback when a persisted
roll predates the source field.
-}
manualSource : Source
manualSource =
    { feature = "Manual", target = Nothing }


{-| A complete roll result. The single source of truth a UI needs to
render a history row.

  - `formula` is precomputed for display; `expression` is the parsed
    structure if you need to re-roll the same thing.
  - `timestamp` is set by the `*Cmd` helpers using `Time.now`.

-}
type alias Roll =
    { kind : RollKind
    , expression : Expression
    , groups : List RollGroup
    , total : Int
    , formula : String
    , timestamp : Time.Posix
    , source : Source
    }


{-| Parser failures. The string is the original input so the UI can
show "couldn't read 'a-b-c'" verbatim.
-}
type Error
    = ParseError String



-- HISTORY


{-| Bounded list of recent rolls, newest first.
-}
type alias History =
    { entries : List Roll
    , max : Int
    }


{-| Default history size (matches the JS roller's 30).
-}
maxHistoryEntries : Int
maxHistoryEntries =
    30


{-| Empty history at the default cap.
-}
emptyHistory : History
emptyHistory =
    { entries = [], max = maxHistoryEntries }


{-| Push a fresh roll onto the history; truncate to `max`.
-}
push : Roll -> History -> History
push roll h =
    { h | entries = roll :: List.take (h.max - 1) h.entries }


{-| Read the entries (newest first).
-}
historyEntries : History -> List Roll
historyEntries h =
    h.entries



-- PARSING


{-| Parse a dice notation string into an `Expression`.

Returns `Err (ParseError input)` for unparseable input or for inputs
that resolve to a no-op (no dice and no constant).

-}
parse : String -> Result Error Expression
parse input =
    let
        cleaned =
            unwrapAverage (String.trim input)
    in
    if String.isEmpty cleaned then
        Err (ParseError input)

    else
        Parser.run expressionParser cleaned
            |> Result.mapError (\_ -> ParseError input)
            |> Result.andThen
                (\expr ->
                    if List.isEmpty expr.dice && expr.constant == 0 then
                        Err (ParseError input)

                    else
                        Ok expr
                )


{-| Stat-block dice notation often appears as `7 (1d8 + 3)` — the
average rounded, then the formula in parens. Strip the wrapper if it
matches; otherwise pass the input through unchanged.
-}
unwrapAverage : String -> String
unwrapAverage s =
    case Parser.run averageWrapParser s of
        Ok inner ->
            String.trim inner

        Err _ ->
            s


averageWrapParser : Parser String
averageWrapParser =
    Parser.succeed identity
        |. Parser.spaces
        |. Parser.int
        |. Parser.spaces
        |. Parser.symbol "("
        |= Parser.getChompedString (Parser.chompUntil ")")
        |. Parser.symbol ")"
        |. Parser.spaces
        |. Parser.end


{-| What one term of an expression resolves to before we fold it into
the accumulator. Either a dice group or a bare integer.
-}
type Term
    = TermDice Dice
    | TermConstant Int


{-| Loop accumulator while we're walking the expression. `first` flips
to `False` after the first term so subsequent terms know they need an
explicit sign; the first term may omit the sign.
-}
type alias Acc =
    { dice : List Dice
    , constant : Int
    , first : Bool
    }


emptyAcc : Acc
emptyAcc =
    { dice = [], constant = 0, first = True }


expressionParser : Parser Expression
expressionParser =
    Parser.succeed identity
        |. Parser.spaces
        |= Parser.loop emptyAcc loopStep


loopStep : Acc -> Parser (Parser.Step Acc Expression)
loopStep acc =
    Parser.oneOf
        -- The "consume another term" branch is wrapped in
        -- Parser.backtrackable so a missing trailing sign (e.g. " fire")
        -- doesn't block us from falling through to the Done branch.
        [ Parser.backtrackable
            (Parser.succeed (\sign term -> Parser.Loop (foldTerm sign term acc))
                |. Parser.spaces
                |= signFor acc.first
                |. Parser.spaces
                |= termParser
            )
        , Parser.succeed
            (\damageType ->
                Parser.Done
                    { dice = List.reverse acc.dice
                    , constant = acc.constant
                    , damageType = damageType
                    }
            )
            |= damageTypeParser
            |. Parser.end
        ]


{-| The first term may omit its sign (treated as positive); subsequent
terms must have one.
-}
signFor : Bool -> Parser Sign
signFor isFirst =
    if isFirst then
        Parser.oneOf
            [ Parser.succeed Negative |. Parser.symbol "-"
            , Parser.succeed Positive |. Parser.symbol "+"
            , Parser.succeed Positive
            ]

    else
        Parser.oneOf
            [ Parser.succeed Negative |. Parser.symbol "-"
            , Parser.succeed Positive |. Parser.symbol "+"
            ]


termParser : Parser Term
termParser =
    Parser.oneOf
        [ Parser.backtrackable diceParser |> Parser.map TermDice
        , Parser.int |> Parser.map TermConstant
        ]


diceParser : Parser Dice
diceParser =
    Parser.succeed
        (\c f ->
            { count = clampCount c
            , faces = clampFaces f
            , sign = Positive
            }
        )
        |= Parser.oneOf [ Parser.int, Parser.succeed 1 ]
        |. Parser.symbol "d"
        |= Parser.int


foldTerm : Sign -> Term -> Acc -> Acc
foldTerm sign term acc =
    case term of
        TermDice d ->
            { acc | dice = { d | sign = sign } :: acc.dice, first = False }

        TermConstant n ->
            { acc
                | constant = acc.constant + signedInt sign n
                , first = False
            }


signedInt : Sign -> Int -> Int
signedInt sign n =
    case sign of
        Positive ->
            n

        Negative ->
            -n


{-| The damage-type tail. Restricted to alpha + spaces so we don't
silently swallow malformed dice notation as a "damage type."
Strips a trailing " damage" word for cleanliness.
-}
damageTypeParser : Parser (Maybe String)
damageTypeParser =
    Parser.succeed identity
        |. Parser.spaces
        |= (Parser.getChompedString
                (Parser.chompWhile (\c -> Char.isAlpha c || c == ' '))
                |> Parser.map
                    (\s ->
                        let
                            cleaned =
                                stripTrailingDamage (String.trim s)
                        in
                        if String.isEmpty cleaned then
                            Nothing

                        else
                            Just cleaned
                    )
           )


stripTrailingDamage : String -> String
stripTrailingDamage s =
    let
        lower =
            String.toLower s
    in
    if String.endsWith " damage" lower then
        String.left (String.length s - 7) s |> String.trim

    else if lower == "damage" then
        ""

    else
        s


clampCount : Int -> Int
clampCount c =
    Basics.max 1 (Basics.min 99 c)


clampFaces : Int -> Int
clampFaces f =
    Basics.max 1 f



-- DISPLAY


{-| Render an `Expression` back to a notation string. Round-trips with
`parse` for normalized inputs (e.g. extra whitespace and the average
wrapper get dropped).
-}
expressionToString : Expression -> String
expressionToString expr =
    let
        dicePart =
            expr.dice
                |> List.indexedMap diceToken
                |> String.concat
                |> String.trim

        constPart =
            if expr.constant == 0 then
                ""

            else if expr.constant > 0 then
                if String.isEmpty dicePart then
                    String.fromInt expr.constant

                else
                    " + " ++ String.fromInt expr.constant

            else if String.isEmpty dicePart then
                String.fromInt expr.constant

            else
                " - " ++ String.fromInt (abs expr.constant)

        damagePart =
            case expr.damageType of
                Just s ->
                    " " ++ s

                Nothing ->
                    ""
    in
    dicePart ++ constPart ++ damagePart


diceToken : Int -> Dice -> String
diceToken idx d =
    let
        signStr =
            case ( idx, d.sign ) of
                ( 0, Positive ) ->
                    ""

                ( 0, Negative ) ->
                    "-"

                ( _, Positive ) ->
                    " + "

                ( _, Negative ) ->
                    " - "
    in
    signStr ++ String.fromInt d.count ++ "d" ++ String.fromInt d.faces



-- INLINE NOTATION SCANNER


{-| One slice of a stat-block trait body. View code renders a `Literal`
as plain text and a `DiceLink` as a clickable button that fires a
roll. The first field of `DiceLink` is the original matched substring
(so it shows the same notation the GM saw); the second is the parsed
form for actually rolling.
-}
type Segment
    = Literal String
    | DiceLink String Expression


{-| Walk a paragraph of text and split it into literal runs and
recognized dice-notation matches.

Two patterns are recognized, in priority order:

  - Stat-block average wrap: `13 (2d8 + 4)` — the whole substring
    becomes a single DiceLink, parsing the inner formula.
  - Plain dice notation: `1d6`, `2d8 + 3`, `3d10-2`. Whitespace
    around `+`/`-` is optional.

Anything else is preserved verbatim in `Literal` runs. The scanner
falls back to a single `Literal input` if anything goes wrong, so
view code never has to handle a parse-failure path.

-}
scan : String -> List Segment
scan input =
    Parser.run scanParser input
        |> Result.withDefault [ Literal input ]


{-| Loop accumulator while scanning. `segments` is in reverse order
and gets flipped on Done; `currentLit` accumulates non-dice characters
between matches and is flushed into a `Literal` whenever we hit a
match or the end of input.
-}
type alias ScanAcc =
    { segments : List Segment
    , currentLit : String
    }


emptyScanAcc : ScanAcc
emptyScanAcc =
    { segments = [], currentLit = "" }


scanParser : Parser (List Segment)
scanParser =
    Parser.loop emptyScanAcc scanStep


scanStep : ScanAcc -> Parser (Parser.Step ScanAcc (List Segment))
scanStep acc =
    Parser.oneOf
        [ Parser.succeed
            (Parser.Done (List.reverse (flushLit acc.currentLit acc.segments)))
            |. Parser.end
        , Parser.backtrackable averageWrapMatchParser
            |> Parser.map
                (\( matched, expr ) ->
                    Parser.Loop
                        { segments = DiceLink matched expr :: flushLit acc.currentLit acc.segments
                        , currentLit = ""
                        }
                )
        , Parser.backtrackable diceMatchParser
            |> Parser.map
                (\( matched, expr ) ->
                    Parser.Loop
                        { segments = DiceLink matched expr :: flushLit acc.currentLit acc.segments
                        , currentLit = ""
                        }
                )
        , Parser.getChompedString (Parser.chompIf (always True))
            |> Parser.map
                (\c ->
                    Parser.Loop
                        { segments = acc.segments
                        , currentLit = acc.currentLit ++ c
                        }
                )
        ]


flushLit : String -> List Segment -> List Segment
flushLit lit segments =
    if String.isEmpty lit then
        segments

    else
        Literal lit :: segments


{-| Match a "13 (2d8 + 4)" style average-wrapped formula. Captures the
whole matched substring so the rendered button preserves the leading
average; the inner formula is what we actually roll.
-}
averageWrapMatchParser : Parser ( String, Expression )
averageWrapMatchParser =
    Parser.getChompedString averageWrapInline
        |> Parser.andThen tryParseMatch


averageWrapInline : Parser ()
averageWrapInline =
    Parser.succeed ()
        |. Parser.int
        |. Parser.spaces
        |. Parser.symbol "("
        |. Parser.chompUntil ")"
        |. Parser.symbol ")"


{-| Match a bare "1d6" / "2d8 + 3" / "3d10-2" formula.
-}
diceMatchParser : Parser ( String, Expression )
diceMatchParser =
    Parser.getChompedString diceInline
        |> Parser.andThen tryParseMatch


diceInline : Parser ()
diceInline =
    Parser.succeed ()
        |. Parser.oneOf
            [ Parser.int |> Parser.map (always ())
            , Parser.succeed ()
            ]
        |. Parser.symbol "d"
        |. Parser.int
        |. Parser.oneOf
            [ Parser.succeed ()
                |. Parser.spaces
                |. Parser.oneOf [ Parser.symbol "+", Parser.symbol "-" ]
                |. Parser.spaces
                |. Parser.int
            , Parser.succeed ()
            ]


{-| Wraps `parse` so that a non-parseable match becomes a Parser
problem rather than an Ok value, letting the surrounding
backtrackable in scanStep fall through to the next alternative.
-}
tryParseMatch : String -> Parser ( String, Expression )
tryParseMatch matched =
    case parse matched of
        Ok expr ->
            Parser.succeed ( matched, expr )

        Err _ ->
            Parser.problem "not a dice expression"



-- GENERATORS


{-| Standard roll generator. The result's `timestamp` is filled in by
the `*Cmd` helpers; if you call this directly you'll see epoch.
-}
generator : Expression -> Random.Generator Roll
generator expr =
    sequenceGen (List.map groupGenerator expr.dice)
        |> Random.map (toStandardRoll expr)


groupGenerator : Dice -> Random.Generator RollGroup
groupGenerator d =
    Random.list d.count (Random.int 1 d.faces)
        |> Random.map
            (\faces ->
                let
                    rolled =
                        List.map (\f -> { face = f, kept = True }) faces

                    sum =
                        List.sum faces
                in
                { dice = d
                , rolled = rolled
                , subtotal = signedInt d.sign sum
                }
            )


toStandardRoll : Expression -> List RollGroup -> Roll
toStandardRoll expr groups =
    let
        diceSum =
            List.sum (List.map .subtotal groups)

        total =
            diceSum + expr.constant
    in
    { kind = Standard
    , expression = expr
    , groups = groups
    , total = total
    , formula = expressionToString expr
    , timestamp = Time.millisToPosix 0
    , source = manualSource
    }


{-| Roll 2d20 and keep the higher; add `modifier`. The `Roll`'s
`groups` carries both faces with `kept` flagged on whichever was
higher, so the UI can show "rolled 17 and 8, kept 17."
-}
advantageGenerator : Int -> Random.Generator Roll
advantageGenerator modifier =
    Random.map2 (toAdvOrDis Advantage modifier)
        (Random.int 1 20)
        (Random.int 1 20)


{-| Roll 2d20 and keep the lower; add `modifier`.
-}
disadvantageGenerator : Int -> Random.Generator Roll
disadvantageGenerator modifier =
    Random.map2 (toAdvOrDis Disadvantage modifier)
        (Random.int 1 20)
        (Random.int 1 20)


toAdvOrDis : RollKind -> Int -> Int -> Int -> Roll
toAdvOrDis kind modifier a b =
    let
        kept =
            case kind of
                Advantage ->
                    Basics.max a b

                Disadvantage ->
                    Basics.min a b

                _ ->
                    a

        rolled =
            [ { face = a, kept = a == kept }
            , { face = b, kept = b == kept }
            ]

        d =
            { count = 2, faces = 20, sign = Positive }

        group =
            { dice = d, rolled = rolled, subtotal = kept }

        expr =
            { dice = [ d ]
            , constant = modifier
            , damageType = Nothing
            }

        prefix =
            case kind of
                Advantage ->
                    "Adv: "

                Disadvantage ->
                    "Dis: "

                _ ->
                    ""
    in
    { kind = kind
    , expression = expr
    , groups = [ group ]
    , total = kept + modifier
    , formula = prefix ++ "1d20" ++ formatModifier modifier
    , timestamp = Time.millisToPosix 0
    , source = manualSource
    }


formatModifier : Int -> String
formatModifier m =
    if m == 0 then
        ""

    else if m > 0 then
        "+" ++ String.fromInt m

    else
        String.fromInt m


{-| Coin flip. Encoded as 1d2 internally so it shares the `Roll`
shape; the `formula` field holds "Coin → heads" or "Coin → tails"
for display.
-}
coinGenerator : Random.Generator Roll
coinGenerator =
    Random.int 1 2
        |> Random.map
            (\n ->
                let
                    rolled =
                        [ { face = n, kept = True } ]

                    d =
                        { count = 1, faces = 2, sign = Positive }

                    group =
                        { dice = d, rolled = rolled, subtotal = n }

                    label =
                        if n == 1 then
                            "Coin → heads"

                        else
                            "Coin → tails"
                in
                { kind = Coin
                , expression =
                    { dice = [ d ]
                    , constant = 0
                    , damageType = Nothing
                    }
                , groups = [ group ]
                , total = n
                , formula = label
                , timestamp = Time.millisToPosix 0
                , source = manualSource
                }
            )


{-| Sequence a list of generators into a generator of a list. We use
this so a compound expression like `1d8 + 2d6` produces the rolls in
order. elm/random doesn't ship a `traverse`-style helper.
-}
sequenceGen : List (Random.Generator a) -> Random.Generator (List a)
sequenceGen gens =
    case gens of
        [] ->
            Random.constant []

        g :: rest ->
            Random.map2 (::) g (sequenceGen rest)



-- CMD HELPERS


{-| Roll an expression and dispatch the result.

Reads `Time.now`, seeds the RNG with the millisecond, evaluates the
expression, and wraps the resulting `Roll` (with the timestamp) in a
single Msg. One Cmd, one Msg, deterministic per millisecond — which
is the only edge case worth knowing about: clicks within the same
millisecond produce identical rolls. In practice human reflexes don't
hit that.

-}
rollCmd : (Roll -> msg) -> Source -> Expression -> Cmd msg
rollCmd toMsg source expr =
    rollWithTime toMsg source (generator expr)


{-| Roll d20 with advantage and dispatch, tagged with `source`.
-}
advantageCmd : (Roll -> msg) -> Source -> Int -> Cmd msg
advantageCmd toMsg source modifier =
    rollWithTime toMsg source (advantageGenerator modifier)


{-| Roll d20 with disadvantage and dispatch, tagged with `source`.
-}
disadvantageCmd : (Roll -> msg) -> Source -> Int -> Cmd msg
disadvantageCmd toMsg source modifier =
    rollWithTime toMsg source (disadvantageGenerator modifier)


{-| Flip a coin and dispatch, tagged with `source`.
-}
coinCmd : (Roll -> msg) -> Source -> Cmd msg
coinCmd toMsg source =
    rollWithTime toMsg source coinGenerator


{-| Roll a batch of expressions in a single Cmd, returning one
labeled `Roll` per spec.

Each spec is `(label, source, expression)` — the label is whatever
opaque identifier the caller wants to associate with the spec
(typically a creature name) and is paired with the resulting `Roll`
so the receiver knows which input spec produced which output.

Why this exists: the per-call `rollCmd` seeds its RNG from the
millisecond timestamp, which is fine for human click cadences but
collides when rolling 8 things at once (every roll the same
millisecond → every roll the same seed → every roll identical).
Batch rolls share one timestamp and step a sequenced generator
once, so the rolls are all independent without any same-millisecond
worries.

-}
batchRollCmd :
    (List ( String, Roll ) -> msg)
    -> List ( String, Source, Expression )
    -> Cmd msg
batchRollCmd toMsg specs =
    Time.now
        |> Task.map
            (\now ->
                let
                    seed =
                        Random.initialSeed (Time.posixToMillis now)

                    -- Wrap each input in a generator that pre-stamps
                    -- the source label, so the sequenced generator
                    -- yields fully-attributed rolls in one step.
                    perSpecGen ( label, source, expr ) =
                        Random.map
                            (\roll ->
                                ( label
                                , { roll | source = source, timestamp = now }
                                )
                            )
                            (generator expr)

                    ( results, _ ) =
                        Random.step (sequenceGen (List.map perSpecGen specs)) seed
                in
                results
            )
        |> Task.perform toMsg


{-| Internal: drive a generator off `Time.now`, producing one Cmd.
Stamps the timestamp and the caller's `source` onto the resulting
Roll so the dice history can show "Damage → Brakka, Ogre Brute"
rather than just the bare formula.
-}
rollWithTime : (Roll -> msg) -> Source -> Random.Generator Roll -> Cmd msg
rollWithTime toMsg source gen =
    Time.now
        |> Task.map
            (\now ->
                let
                    seed =
                        Random.initialSeed (Time.posixToMillis now)

                    ( roll, _ ) =
                        Random.step gen seed
                in
                { roll | timestamp = now, source = source }
            )
        |> Task.perform toMsg



-- JSON


{-| Encode a `Roll` as JSON for persistence. Round-trips with
`decodeRoll`. The schema:

    {
      "kind": "standard" | "advantage" | "disadvantage" | "coin",
      "formula": "2d6+3",
      "total": 12,
      "timestamp": 1714502400000,    // millis since epoch
      "expression": { "dice": [...], "constant": 3, "damageType": null },
      "groups":     [{ "dice": ..., "rolled": [...], "subtotal": 9 }]
    }

-}
encodeRoll : Roll -> Encode.Value
encodeRoll roll =
    Encode.object
        [ ( "kind", encodeKind roll.kind )
        , ( "formula", Encode.string roll.formula )
        , ( "total", Encode.int roll.total )
        , ( "timestamp", Encode.int (Time.posixToMillis roll.timestamp) )
        , ( "expression", encodeExpression roll.expression )
        , ( "groups", Encode.list encodeGroup roll.groups )
        , ( "source", encodeSource roll.source )
        ]


{-| Decode a `Roll` from JSON. Tolerant of missing optional fields
where reasonable; outright fails on bad enum values so a corrupt
file surfaces immediately rather than degrading silently. The
`source` field is back-compat: legacy persisted rolls without it
default to `manualSource`.
-}
decodeRoll : Decoder Roll
decodeRoll =
    Decode.map7 Roll
        (Decode.field "kind" decodeKind)
        (Decode.field "expression" decodeExpression)
        (Decode.field "groups" (Decode.list decodeGroup))
        (Decode.field "total" Decode.int)
        (Decode.field "formula" Decode.string)
        (Decode.field "timestamp" (Decode.map Time.millisToPosix Decode.int))
        (Decode.oneOf
            [ Decode.field "source" decodeSource
            , Decode.succeed manualSource
            ]
        )


encodeSource : Source -> Encode.Value
encodeSource s =
    Encode.object
        [ ( "feature", Encode.string s.feature )
        , ( "target"
          , case s.target of
                Just t ->
                    Encode.string t

                Nothing ->
                    Encode.null
          )
        ]


decodeSource : Decoder Source
decodeSource =
    Decode.map2 Source
        (Decode.field "feature" Decode.string)
        (Decode.field "target" (Decode.nullable Decode.string))


encodeKind : RollKind -> Encode.Value
encodeKind kind =
    Encode.string
        (case kind of
            Standard ->
                "standard"

            Advantage ->
                "advantage"

            Disadvantage ->
                "disadvantage"

            Coin ->
                "coin"
        )


decodeKind : Decoder RollKind
decodeKind =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "standard" ->
                        Decode.succeed Standard

                    "advantage" ->
                        Decode.succeed Advantage

                    "disadvantage" ->
                        Decode.succeed Disadvantage

                    "coin" ->
                        Decode.succeed Coin

                    other ->
                        Decode.fail ("unknown roll kind: " ++ other)
            )


encodeSign : Sign -> Encode.Value
encodeSign sign =
    Encode.string
        (case sign of
            Positive ->
                "positive"

            Negative ->
                "negative"
        )


decodeSign : Decoder Sign
decodeSign =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "positive" ->
                        Decode.succeed Positive

                    "negative" ->
                        Decode.succeed Negative

                    other ->
                        Decode.fail ("unknown sign: " ++ other)
            )


encodeDice : Dice -> Encode.Value
encodeDice d =
    Encode.object
        [ ( "count", Encode.int d.count )
        , ( "faces", Encode.int d.faces )
        , ( "sign", encodeSign d.sign )
        ]


decodeDice : Decoder Dice
decodeDice =
    Decode.map3 Dice
        (Decode.field "count" Decode.int)
        (Decode.field "faces" Decode.int)
        (Decode.field "sign" decodeSign)


encodeExpression : Expression -> Encode.Value
encodeExpression e =
    Encode.object
        [ ( "dice", Encode.list encodeDice e.dice )
        , ( "constant", Encode.int e.constant )
        , ( "damageType"
          , case e.damageType of
                Just s ->
                    Encode.string s

                Nothing ->
                    Encode.null
          )
        ]


decodeExpression : Decoder Expression
decodeExpression =
    Decode.map3 Expression
        (Decode.field "dice" (Decode.list decodeDice))
        (Decode.field "constant" Decode.int)
        (Decode.field "damageType" (Decode.nullable Decode.string))


encodeRolledDie : RolledDie -> Encode.Value
encodeRolledDie d =
    Encode.object
        [ ( "face", Encode.int d.face )
        , ( "kept", Encode.bool d.kept )
        ]


decodeRolledDie : Decoder RolledDie
decodeRolledDie =
    Decode.map2 RolledDie
        (Decode.field "face" Decode.int)
        (Decode.field "kept" Decode.bool)


encodeGroup : RollGroup -> Encode.Value
encodeGroup g =
    Encode.object
        [ ( "dice", encodeDice g.dice )
        , ( "rolled", Encode.list encodeRolledDie g.rolled )
        , ( "subtotal", Encode.int g.subtotal )
        ]


decodeGroup : Decoder RollGroup
decodeGroup =
    Decode.map3 RollGroup
        (Decode.field "dice" decodeDice)
        (Decode.field "rolled" (Decode.list decodeRolledDie))
        (Decode.field "subtotal" Decode.int)
