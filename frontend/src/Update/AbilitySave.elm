module Update.AbilitySave exposing (close, landed, open, roll)

{-| Update branches for the ability-save modal opened by clicking
an ability cell (STR, DEX, …) in the compendium stat block.

The modal is essentially three roll buttons (Roll / Advantage /
Disadvantage) wrapped around a captured save bonus. Submitting
fires a normal dice-history Cmd tagged `<ABILITY> Save → <name>`
so the result lands in the dice modal alongside everything else.

-}

import Dice
import Effects
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..), RollMode(..))
import Ui.AbilitySave exposing (AbilitySaveUi)
import Update.Dice


open : String -> String -> Int -> Int -> Int -> Model -> ( Model, Cmd Msg )
open creatureName ability bonus clickX clickY model =
    ( { model
        | modal =
            Just
                (ModalAbilitySave
                    (Ui.AbilitySave.fresh creatureName ability bonus clickX clickY)
                )
      }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


{-| Fire a save roll in the requested mode and close the modal.
The roll lands in `AbilitySaveLanded`, which routes it into the
shared dice history just like any other source.
-}
roll : RollMode -> Model -> ( Model, Cmd Msg )
roll mode model =
    case model.modal of
        Just (ModalAbilitySave ui) ->
            ( { model | modal = Nothing }
            , rollCmd mode ui
            )

        _ ->
            ( model, Cmd.none )


{-| Build the right Dice cmd for the chosen mode. Standard uses
the full `1d20 + bonus` expression; advantage / disadvantage
delegate to the dedicated 2d20 helpers so the kept-die labelling
shows up correctly in the history.

The result-handler Msg is partial-applied with the original
ability-cell click position so the floating popup spawns at the
cell when the dice land — even though the modal has already
closed by then.

-}
rollCmd : RollMode -> AbilitySaveUi -> Cmd Msg
rollCmd mode ui =
    let
        src =
            { feature = ui.ability ++ " Save"
            , target = Just ui.creatureName
            }

        landedCtor =
            AbilitySaveLanded ui.clickX ui.clickY
    in
    case mode of
        ModeStandard ->
            Dice.rollCmd landedCtor src (Effects.saveExpression ui.bonus)

        ModeAdvantage ->
            Dice.advantageCmd landedCtor src ui.bonus

        ModeDisadvantage ->
            Dice.disadvantageCmd landedCtor src ui.bonus


{-| Roll landed. Reuse the shared dice-history pipeline so the
"unread rolls" indicator and the server-side persistence happen
exactly the same way as a manual roll from the dice modal, AND
spawn a floating roll-result popup at the original ability-cell
click position so the GM gets the same inline feedback they
already get from clicking an inline dice link in a stat block.
-}
landed : Int -> Int -> Dice.Roll -> Model -> ( Model, Cmd Msg )
landed x y roll_ model =
    let
        ( withPopup, popupCmd ) =
            Update.Dice.spawnRollPopup
                { x = x, y = y, total = roll_.total }
                model

        ( pushed, flashCmd ) =
            Effects.pushDiceRoll roll_ withPopup
    in
    ( pushed
    , Cmd.batch [ Effects.persistDiceRoll roll_, popupCmd, flashCmd ]
    )
