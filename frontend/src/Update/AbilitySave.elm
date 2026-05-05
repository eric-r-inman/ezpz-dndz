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


open : String -> String -> Int -> Model -> ( Model, Cmd Msg )
open creatureName ability bonus model =
    ( { model
        | modal =
            Just (ModalAbilitySave (Ui.AbilitySave.fresh creatureName ability bonus))
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
-}
rollCmd : RollMode -> AbilitySaveUi -> Cmd Msg
rollCmd mode ui =
    let
        src =
            { feature = ui.ability ++ " Save"
            , target = Just ui.creatureName
            }
    in
    case mode of
        ModeStandard ->
            Dice.rollCmd AbilitySaveLanded src (saveExpression ui.bonus)

        ModeAdvantage ->
            Dice.advantageCmd AbilitySaveLanded src ui.bonus

        ModeDisadvantage ->
            Dice.disadvantageCmd AbilitySaveLanded src ui.bonus


saveExpression : Int -> Dice.Expression
saveExpression bonus =
    { dice = [ { count = 1, faces = 20, sign = Dice.Positive } ]
    , constant = bonus
    , damageType = Nothing
    }


{-| Roll landed. Reuse the shared dice-history pipeline so the
"unread rolls" indicator and the server-side persistence happen
exactly the same way as a manual roll from the dice modal.
-}
landed : Dice.Roll -> Model -> ( Model, Cmd Msg )
landed roll_ model =
    ( Effects.pushDiceRoll roll_ model
    , Effects.persistDiceRoll roll_
    )
