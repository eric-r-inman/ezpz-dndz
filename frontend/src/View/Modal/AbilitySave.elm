module View.Modal.AbilitySave exposing (view)

{-| Saving-throw roll modal triggered from clicking an ability
cell (STR, DEX, …) in the compendium stat block.

Three buttons inside — Roll / Advantage / Disadvantage — all fire
`AbilitySaveRoll` with the same captured bonus and tag the
resulting dice-history entry with the creature's name. No form
fields; this is a one-click decision.

Renders nothing when the modal isn't open.

-}

import Html exposing (Html, button, div, p, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..), RollMode(..))
import Ui.AbilitySave as AbilitySave exposing (AbilitySaveUi)
import View.Modal


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalAbilitySave ui) ->
            View.Modal.view
                { close = AbilitySaveClose
                , noOp = NoOp
                , title = ui.ability ++ " " ++ AbilitySave.kindLabel ui.kind ++ " — " ++ ui.creatureName
                , extraClass = "modal--ability-save"
                , chrome = model.modalChrome
                , body =
                    [ summary ui
                    , buttons
                    ]
                }

        _ ->
            text ""


summary : AbilitySaveUi -> Html Msg
summary ui =
    p [ class "ability-save__summary" ]
        [ text ("1d20 " ++ signed ui.bonus) ]


buttons : Html Msg
buttons =
    div [ class "ability-save__buttons" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick (AbilitySaveRoll ModeStandard)
            ]
            [ text "Roll" ]
        , button
            [ class "action-btn action-btn--green"
            , onClick (AbilitySaveRoll ModeAdvantage)
            ]
            [ text "Advantage" ]
        , button
            [ class "action-btn action-btn--orange"
            , onClick (AbilitySaveRoll ModeDisadvantage)
            ]
            [ text "Disadvantage" ]
        ]


signed : Int -> String
signed n =
    if n >= 0 then
        "+ " ++ String.fromInt n

    else
        "− " ++ String.fromInt (abs n)
