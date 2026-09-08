module Update.Dice exposing
    ( attackRollTriggered
    , clearHistory
    , clearResponse
    , countChanged
    , flipCoin
    , historyLoaded
    , historyToggle
    , inputChanged
    , markRead
    , modifierChanged
    , openPanel
    , persistResponse
    , rerun
    , rerunMenuClose
    , rerunMenuToggle
    , rerunNoModifier
    , resetSliders
    , rollAdvantage
    , rollDisadvantage
    , rollFaces
    , rollFromInput
    , rollFromOtherTab
    , rollFromStatBlock
    , rollLanded
    , rollPopupExpired
    , spawnRollPopup
    , statBlockRollLanded
    , tripleRollCmd
    , tripleRollLanded
    )

{-| Update branches for the dice roller panel, and the
round-trip a landed roll makes through history and persistence.

The roller's state is always present in the model (no `Maybe`),
so `withDice` is a flat lens over `model.dice` rather than a
`Maybe.map`.

-}

import Auth
import Dice
import Effects
import Http
import Json.Decode as Decode
import Model exposing (Model, RollPopup)
import Msg exposing (Msg(..))
import Process
import Task
import Ui.Dice exposing (DiceUi)


{-| Local lens for `model.dice`. Always present (no `Maybe.map`).
-}
withDice : (DiceUi -> DiceUi) -> Model -> Model
withDice fn model =
    { model | dice = fn model.dice }


markRead : Model -> Model
markRead model =
    withDice (\d -> { d | unread = False })
        { model | flashedRollSeq = model.dice.history.pushed }


{-| The rail's 🎲 icon: unfold the Dice Roller and scroll it to
the top of the column, whether it was already open, folded, or
buried under other panels. It has no per-creature target, so
there is nothing to re-aim.
-}
openPanel : Model -> ( Model, Cmd Msg )
openPanel model =
    let
        nextModel =
            Model.unfoldDrawer Model.diceLens model
    in
    ( nextModel
    , Model.drawerIndexOf Model.diceLens nextModel
        |> Maybe.map Effects.scrollDrawerIndexToTop
        |> Maybe.withDefault Cmd.none
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
    let
        ( closed, _ ) =
            rerunMenuClose model
    in
    case roll.kind of
        Dice.Standard ->
            ( closed, Dice.rollCmd DiceRollLanded roll.source roll.expression )

        Dice.Advantage ->
            ( closed, Dice.advantageCmd DiceRollLanded roll.source roll.expression.constant )

        Dice.Disadvantage ->
            ( closed, Dice.disadvantageCmd DiceRollLanded roll.source roll.expression.constant )

        Dice.Coin ->
            ( closed, Dice.coinCmd DiceRollLanded roll.source )


{-| "Reroll, no modifier" — re-execute a historical roll with the
flat constant on the expression stripped to zero. A 2d6+2 becomes
2d6; an Advantage d20+5 becomes Advantage d20+0; a Coin flip has
no modifier concept so this collapses to a regular [`rerun`](#rerun).
-}
rerunNoModifier : Dice.Roll -> Model -> ( Model, Cmd Msg )
rerunNoModifier roll model =
    let
        expr =
            roll.expression

        stripped =
            { roll | expression = { expr | constant = 0 } }
    in
    rerun stripped model


{-| Fold the Recent-rolls list away or back.
-}
historyToggle : Model -> ( Model, Cmd Msg )
historyToggle model =
    ( withDice (\d -> { d | historyOpen = not d.historyOpen }) model
    , Cmd.none
    )


{-| Toggle the re-roll dropdown for one history entry. Clicking
the already-open entry's button closes the menu; clicking a
different entry's button replaces the open target.
-}
rerunMenuToggle : Int -> Model -> ( Model, Cmd Msg )
rerunMenuToggle idx model =
    let
        next =
            withDice
                (\d ->
                    if d.rerunMenuOpenFor == Just idx then
                        { d | rerunMenuOpenFor = Nothing }

                    else
                        { d | rerunMenuOpenFor = Just idx }
                )
                model
    in
    ( next, Cmd.none )


{-| Close the re-roll dropdown (no-op when nothing is open).
Fired by the global click-outside / Esc subscriptions in
`Main.subscriptions` and by both menu items after they dispatch.
-}
rerunMenuClose : Model -> ( Model, Cmd Msg )
rerunMenuClose model =
    ( withDice (\d -> { d | rerunMenuOpenFor = Nothing }) model, Cmd.none )


{-| Clear takes the HP changes with the rolls. They render as one
list, so leaving half the rows standing would read as a failed
click — and the roll count restarts here, which the surviving
stamps would then sort against wrongly.
-}
clearHistory : Model -> ( Model, Cmd Msg )
clearHistory model =
    let
        cleared =
            withDice (\d -> { d | history = Dice.emptyHistory })
                -- The roll count restarts with the history, so
                -- the mark the flash compares against restarts
                -- with it.
                { model | hpChangeLog = [], flashedRollSeq = 0 }

        cmd =
            case model.auth of
                Auth.AuthAuthenticated _ ->
                    Effects.clearDiceHistory

                -- Anonymous: the update-loop wrapper notices the
                -- history just went from N entries to 0 and fires
                -- the localStorage persist with an empty list, so
                -- no explicit Cmd here.  Loading mirrors that.
                _ ->
                    Cmd.none
    in
    ( cleared, cmd )


{-| A roll fired from anywhere in the app landed. Update the local
history immediately for snappy UI; fire the persistence POST in
parallel. The server response replaces the local view in
`DicePersistResponse` so the two stay in sync (and any older entries
surfacing from disk after init come through that same path).
-}
rollLanded : Dice.Roll -> Model -> ( Model, Cmd Msg )
rollLanded roll model =
    let
        ( pushed, broadcastCmd ) =
            Effects.pushDiceRoll roll model
    in
    ( pushed
    , Cmd.batch [ persistRollFor model.auth roll, broadcastCmd ]
    )


{-| A peer tab fired a roll and broadcast it over the
BroadcastChannel. Push it into our local history so the user
sees a single shared log across all open tabs, but skip both
the broadcast (avoids an echo loop) and the persist (the
originating tab has already POSTed / written localStorage).
Decode failures silently no-op; we don't want a malformed
peer payload to wedge the receiving tab.
-}
rollFromOtherTab : Decode.Value -> Model -> ( Model, Cmd Msg )
rollFromOtherTab raw model =
    case Decode.decodeValue Dice.decodeRoll raw of
        Ok roll ->
            Effects.pushIncomingDiceRoll roll model

        Err _ ->
            ( model, Cmd.none )


{-| Per-session router for the after-roll persist Cmd.

  - Authenticated → `POST /api/dice/history` with this single roll;
    the response re-syncs the local view.
  - Anonymous → no HTTP; the update-loop wrapper in `Main.update`
    diffs `model.dice.history.entries` and writes the full list to
    `localStorage` via the `persistLocalDiceHistory` port.
  - Loading → skip; the post-probe handler will sort things out
    and the user shouldn't be rolling during the boot probe
    anyway.

-}
persistRollFor : Auth.AuthState -> Dice.Roll -> Cmd Msg
persistRollFor auth roll =
    case auth of
        Auth.AuthAuthenticated _ ->
            Effects.persistDiceRoll roll

        _ ->
            Cmd.none


historyLoaded : Result Http.Error (List Dice.Roll) -> Model -> ( Model, Cmd Msg )
historyLoaded result model =
    case result of
        Ok rolls ->
            ( withDice
                (\d ->
                    { d
                        | history =
                            -- The only place the count restarts,
                            -- which is safe because this answers
                            -- the boot probe, before any HP entry
                            -- has been stamped against it.  A
                            -- second caller would renumber rolls
                            -- the HP log already points at.
                            { entries = rolls
                            , max = Dice.maxHistoryEntries
                            , pushed = List.length rolls
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
                            -- The count carries over rather than
                            -- restarting at what came back: the
                            -- server sends its truncated list, and
                            -- resetting to that length would
                            -- renumber rolls the HP log has
                            -- already been stamped against.
                            { entries = rolls
                            , max = Dice.maxHistoryEntries
                            , pushed = d.history.pushed
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


{-| Click on inline dice notation in a stat-block trait. Fire the
roll through the same code path as the panel's own buttons, but
do NOT open the panel — the result lands silently in the dice
history and the panel marks its title unread, so the GM can open
the log when they want to see it.
The source is tagged "Stat block" with the creature name so it
shows up in the history as "Stat block → Brakka, Ogre Brute".

`x` / `y` are the click position captured from the DOM event so
the spawned floating popup can anchor to where the user clicked.
The result lands in `StatBlockRollLanded` (rather than the shared
`DiceRollLanded`) so we know to spawn a popup; manual rolls in
the dice modal route through `DiceRollLanded` as before.

-}
rollFromStatBlock : String -> Dice.Expression -> Int -> Int -> Model -> ( Model, Cmd Msg )
rollFromStatBlock creatureName expr x y model =
    ( model
    , Dice.rollCmd (StatBlockRollLanded x y)
        { feature = "Stat block", target = Just creatureName }
        expr
    )


{-| Result handler for stat-block dice-link clicks. Pushes the
roll to history (same as `rollLanded` for manual rolls) AND
spawns a floating popup at the captured cursor position.
-}
statBlockRollLanded : Int -> Int -> Dice.Roll -> Model -> ( Model, Cmd Msg )
statBlockRollLanded x y roll model =
    let
        ( withPopup, popupCmd ) =
            spawnRollPopup { x = x, y = y, total = roll.total, color = Model.PopupPlain } model

        ( pushed, broadcastCmd ) =
            Effects.pushDiceRoll roll withPopup
    in
    ( pushed
    , Cmd.batch [ persistRollFor model.auth roll, popupCmd, broadcastCmd ]
    )


{-| Add a floating popup at the given screen position with the
given roll total, returning the modified model + the auto-expire
Cmd. Shared by every roll source that wants the floating-popup
feedback (stat-block dice links, triple-rolls). The caller is
responsible for any other roll-landed bookkeeping (push to dice
history, persist, etc.) and for batching `popupCmd` with whatever
else the source needs to fire.
-}
spawnRollPopup : { x : Int, y : Int, total : Int, color : Model.PopupColor } -> Model -> ( Model, Cmd Msg )
spawnRollPopup { x, y, total, color } model =
    let
        popup : RollPopup
        popup =
            { id = model.nextRollPopupId
            , x = x
            , y = y
            , total = total
            , color = color
            }
    in
    ( { model
        | rollPopups = popup :: model.rollPopups
        , nextRollPopupId = model.nextRollPopupId + 1
      }
    , Process.sleep popupLifetimeMs
        |> Task.perform (\_ -> RollPopupExpired popup.id)
    )


{-| Drop the named popup from the model. Fired by the
`Process.sleep` chain `popupLifetimeMs` after the popup spawns,
so the model doesn't accumulate stale popups indefinitely.
-}
rollPopupExpired : Int -> Model -> ( Model, Cmd Msg )
rollPopupExpired id model =
    ( { model | rollPopups = List.filter (\p -> p.id /= id) model.rollPopups }
    , Cmd.none
    )


{-| An attack-roll click in a stat block (the inline "+N to hit"
link): the same standard + advantage + disadvantage triple-roll
as an ability check or saving throw (see `Update.AbilitySave`),
tagged "Attack" rather than an ability's check/save label.
-}
attackRollTriggered : String -> Int -> Int -> Int -> Model -> ( Model, Cmd Msg )
attackRollTriggered creatureName mod x y model =
    ( model, tripleRollCmd "Attack" creatureName mod x y )


{-| Roll `1d20 + bonus` three ways at once — standard, advantage,
and disadvantage — tagged with `feature` for the dice-history
label ("Attack", "STR check", "DEX saving throw", …). One batched
Cmd rather than three separate ones, so the three rolls don't
share a same-millisecond RNG seed (see `Dice.batchRollCmd`).
`x` / `y` are the triggering click's position, carried through to
`TripleRollLanded` so the floating popups anchor there.
-}
tripleRollCmd : String -> String -> Int -> Int -> Int -> Cmd Msg
tripleRollCmd feature creatureName bonus x y =
    let
        source =
            { feature = feature, target = Just creatureName }
    in
    Dice.batchRollCmd (TripleRollLanded x y)
        [ ( creatureName, source, Dice.generator (Effects.saveExpression bonus) )
        , ( creatureName, source, Dice.advantageGenerator bonus )
        , ( creatureName, source, Dice.disadvantageGenerator bonus )
        ]


{-| Result handler for a triple-roll: push all three rolls to
history/persistence exactly as any other roll, spawn three
floating popups colour-coded by roll mode and spread out
side-by-side at the click position so they read as a set, and set
the rail's badge-strip override so the three totals stay visible
— colour-coded the same way — even after the popups fade. Any
single roll landing after this (from any source) clears the
override; see `Effects.pushIncomingDiceRoll`.
-}
tripleRollLanded : Int -> Int -> List ( String, Dice.Roll ) -> Model -> ( Model, Cmd Msg )
tripleRollLanded x y results model =
    let
        rolls =
            List.map Tuple.second results

        pushOne roll ( m, cmds ) =
            let
                ( pushed, broadcastCmd ) =
                    Effects.pushDiceRoll roll m
            in
            ( pushed, persistRollFor m.auth roll :: broadcastCmd :: cmds )

        ( afterPush, pushCmds ) =
            List.foldl pushOne ( model, [] ) rolls

        spawnOne roll ( m, cmds ) =
            let
                ( withPopup, popupCmd ) =
                    spawnRollPopup
                        { x = x + popupOffset roll.kind
                        , y = y
                        , total = roll.total
                        , color = popupColor roll.kind
                        }
                        m
            in
            ( withPopup, popupCmd :: cmds )

        ( afterPopups, popupCmds ) =
            List.foldl spawnOne ( afterPush, [] ) rolls

        d =
            afterPopups.dice
    in
    ( { afterPopups | dice = { d | rollBadgeOverride = Just rolls } }
    , Cmd.batch (pushCmds ++ popupCmds)
    )


popupColor : Dice.RollKind -> Model.PopupColor
popupColor kind =
    case kind of
        Dice.Advantage ->
            Model.PopupAdvantage

        Dice.Disadvantage ->
            Model.PopupDisadvantage

        _ ->
            Model.PopupStandard


{-| Horizontal spread so a triple-roll's three popups float up
side by side instead of stacked exactly on top of one another.
-}
popupOffset : Dice.RollKind -> Int
popupOffset kind =
    case kind of
        Dice.Advantage ->
            -36

        Dice.Disadvantage ->
            36

        _ ->
            0


{-| Roll-popup lifetime in milliseconds. Must match the CSS
`animation-duration` on `.roll-popup` so the DOM node stays
alive through the full float-and-fade animation.
-}
popupLifetimeMs : Float
popupLifetimeMs =
    1200


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
