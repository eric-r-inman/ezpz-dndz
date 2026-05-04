module Update.Dice exposing
    ( clearHistory
    , clearResponse
    , close
    , countChanged
    , flipCoin
    , historyLoaded
    , inputChanged
    , modifierChanged
    , open
    , persistResponse
    , rerun
    , resetSliders
    , rollAdvantage
    , rollDisadvantage
    , rollFaces
    , rollFromInput
    , rollFromStatBlock
    , rollLanded
    )

{-| Update branches for the dice roller modal: opening / closing,
slider state, free-text expression entry, the rainbow face buttons,
the advantage / disadvantage / coin shortcuts, the rerun action on
historical rolls, and the result-handling round-trip
(`DiceRollLanded` → push to history → persist).

The dice modal is always present in the model (no `Maybe`), so
`withDice` is a flat lens over `model.dice` rather than a
`Maybe.map`.

-}

import Dice
import Effects
import Http
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui.Dice exposing (DiceUi)


{-| Local lens for `model.dice`. Always present (no `Maybe.map`).
-}
withDice : (DiceUi -> DiceUi) -> Model -> Model
withDice fn model =
    { model | dice = fn model.dice }


{-| Open the modal. Clear the "unread rolls landed" flag whenever
the modal opens; whatever the user is about to see, they are now
caught up.
-}
open : Model -> ( Model, Cmd Msg )
open model =
    ( withDice (\d -> { d | open = True, inputError = Nothing, unread = False }) model
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( withDice (\d -> { d | open = False, inputError = Nothing }) model
    , Cmd.none
    )


inputChanged : String -> Model -> ( Model, Cmd Msg )
inputChanged text model =
    ( withDice (\d -> { d | input = text, inputError = Nothing }) model
    , Cmd.none
    )


countChanged : String -> Model -> ( Model, Cmd Msg )
countChanged text model =
    ( withDice (\d -> { d | count = parseClamp 1 99 1 text }) model
    , Cmd.none
    )


{-| Track the raw characters in `modifierText`; only update the
parsed `modifier` when the input is actually a number. Lets the
user type "-" before "-5" without losing the minus on re-render.
-}
modifierChanged : String -> Model -> ( Model, Cmd Msg )
modifierChanged text model =
    ( withDice
        (\d ->
            { d
                | modifierText = text
                , modifier =
                    String.toInt (String.trim text)
                        |> Maybe.map (Basics.max -999 >> Basics.min 999)
                        |> Maybe.withDefault d.modifier
            }
        )
        model
    , Cmd.none
    )


resetSliders : Model -> ( Model, Cmd Msg )
resetSliders model =
    ( withDice (\d -> { d | count = 1, modifier = 0, modifierText = "0" }) model
    , Cmd.none
    )


{-| Parse the free-text expression. On failure, stash the error in
the modal so the input can show "couldn't read 'xyz'"; on success,
fire the roll Cmd.
-}
rollFromInput : Model -> ( Model, Cmd Msg )
rollFromInput model =
    case Dice.parse model.dice.input of
        Ok expr ->
            ( withDice (\d -> { d | inputError = Nothing }) model
            , Dice.rollCmd DiceRollLanded Dice.manualSource expr
            )

        Err err ->
            ( withDice (\d -> { d | inputError = Just err }) model
            , Cmd.none
            )


{-| Each rainbow face button rolls (count)d(faces) + modifier using
the current sliders. No parse needed.
-}
rollFaces : Int -> Model -> ( Model, Cmd Msg )
rollFaces faces model =
    ( model
    , Dice.rollCmd DiceRollLanded Dice.manualSource (faceExpression model.dice faces)
    )


rollAdvantage : Model -> ( Model, Cmd Msg )
rollAdvantage model =
    ( model, Dice.advantageCmd DiceRollLanded Dice.manualSource model.dice.modifier )


rollDisadvantage : Model -> ( Model, Cmd Msg )
rollDisadvantage model =
    ( model, Dice.disadvantageCmd DiceRollLanded Dice.manualSource model.dice.modifier )


flipCoin : Model -> ( Model, Cmd Msg )
flipCoin model =
    ( model, Dice.coinCmd DiceRollLanded Dice.manualSource )


{-| Re-execute a historical roll using the same kind AND the
original source label, so a re-rolled "Damage → Brakka" still reads
as such in the history (rather than silently demoting to "Manual").
-}
rerun : Dice.Roll -> Model -> ( Model, Cmd Msg )
rerun roll model =
    case roll.kind of
        Dice.Standard ->
            ( model, Dice.rollCmd DiceRollLanded roll.source roll.expression )

        Dice.Advantage ->
            ( model, Dice.advantageCmd DiceRollLanded roll.source roll.expression.constant )

        Dice.Disadvantage ->
            ( model, Dice.disadvantageCmd DiceRollLanded roll.source roll.expression.constant )

        Dice.Coin ->
            ( model, Dice.coinCmd DiceRollLanded roll.source )


clearHistory : Model -> ( Model, Cmd Msg )
clearHistory model =
    ( withDice (\d -> { d | history = Dice.emptyHistory }) model
    , Effects.clearDiceHistory
    )


{-| A roll fired from anywhere in the app landed. Update the local
history immediately for snappy UI; fire the persistence POST in
parallel. The server response replaces the local view in
`DicePersistResponse` so the two stay in sync (and any older entries
surfacing from disk after init come through that same path).
-}
rollLanded : Dice.Roll -> Model -> ( Model, Cmd Msg )
rollLanded roll model =
    ( Effects.pushDiceRoll roll model
    , Effects.persistDiceRoll roll
    )


historyLoaded : Result Http.Error (List Dice.Roll) -> Model -> ( Model, Cmd Msg )
historyLoaded result model =
    case result of
        Ok rolls ->
            ( withDice
                (\d ->
                    { d
                        | history =
                            { entries = rolls
                            , max = Dice.maxHistoryEntries
                            }
                    }
                )
                model
            , Cmd.none
            )

        Err _ ->
            ( model, Cmd.none )


{-| Server is now the source of truth for what's persisted; reflect
its truncation/ordering back into the local UI so reroll buttons
match disk.
-}
persistResponse : Result Http.Error (List Dice.Roll) -> Model -> ( Model, Cmd Msg )
persistResponse result model =
    case result of
        Ok rolls ->
            ( withDice
                (\d ->
                    { d
                        | history =
                            { entries = rolls
                            , max = Dice.maxHistoryEntries
                            }
                    }
                )
                model
            , Cmd.none
            )

        Err _ ->
            ( model, Cmd.none )


{-| Server-side clear succeeded or didn't; either way the local
history has already been emptied in `clearHistory`.
-}
clearResponse : Result Http.Error () -> Model -> ( Model, Cmd Msg )
clearResponse _ model =
    ( model, Cmd.none )


{-| Click on inline dice notation in a stat-block trait. Open the
modal so the user sees the result land, and fire the roll through
the same code path as the modal's own buttons. The source is tagged
"Stat block" with the creature name so it shows up in the history
as "Stat block → Brakka, Ogre Brute".
-}
rollFromStatBlock : String -> Dice.Expression -> Model -> ( Model, Cmd Msg )
rollFromStatBlock creatureName expr model =
    ( withDice (\d -> { d | open = True, inputError = Nothing }) model
    , Dice.rollCmd DiceRollLanded
        { feature = "Stat block", target = Just creatureName }
        expr
    )


{-| Parse a string into an int, clamping to `lo..hi` and falling
back to `def` if the input doesn't parse. Used by the count slider.
-}
parseClamp : Int -> Int -> Int -> String -> Int
parseClamp lo hi def text =
    case String.toInt (String.trim text) of
        Just n ->
            Basics.max lo (Basics.min hi n)

        Nothing ->
            def


{-| Build the `Dice.Expression` that one rainbow face-button rolls.
Uses the modal's current count/modifier sliders.
-}
faceExpression : DiceUi -> Int -> Dice.Expression
faceExpression ui faces =
    { dice =
        [ { count = ui.count
          , faces = faces
          , sign = Dice.Positive
          }
        ]
    , constant = ui.modifier
    , damageType = Nothing
    }
