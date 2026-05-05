module View.Modal.Initiative exposing (view)

{-| Initiative manager modal. Three stacked sections: a single-button
quick sort, an auto-roll batch (one button each for target / all /
selected), and a custom value entry with target / selected apply.
Closes on backdrop click or Cancel.
-}

import Html exposing (Html, button, div, h3, input, text)
import Html.Attributes as Attr exposing (attribute, class, disabled, for, id, title, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( Msg(..)
        , RollMode(..)
        , RollScope(..)
        )
import Ui.Initiative exposing (InitiativeUi)
import Util.Keyboard
import View.Modal


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalInitiative ui) ->
            let
                selectedCount =
                    List.length (List.filter .selected model.encounter.creatures)
            in
            View.Modal.view
                { close = InitiativeClose
                , noOp = NoOp
                , title = "Initiative — " ++ ui.target
                , extraClass = "modal--initiative"
                , body =
                    [ quickSort
                    , autoRoll ui selectedCount
                    , custom ui selectedCount
                    , footer
                    ]
                }

        _ ->
            text ""


quickSort : Html Msg
quickSort =
    div [ class "init-section" ]
        [ button
            [ class "action-btn action-btn--blue init-btn-block"
            , onClick InitiativeQuickSort
            ]
            [ text "🔄 Quick Sort Encounter" ]
        , div [ class "init-section__caption" ]
            [ text "Sort all creatures by their current initiative values" ]
        ]


autoRoll : InitiativeUi -> Int -> Html Msg
autoRoll ui selectedCount =
    div [ class "init-section" ]
        [ h3 [ class "init-section__heading" ]
            [ text "Auto-roll Initiative" ]
        , autoRollPair ScopeTarget
            ("🎲 Roll Initiative & Sort: " ++ ui.target)
            True
            ""
        , autoRollPair ScopeAll
            "🎲 Roll Initiative & Sort: All"
            True
            ""
        , autoRollPair ScopeSelected
            ("🎲 Roll Initiative & Sort: Selected" ++ selectedCountSuffix selectedCount)
            (selectedCount > 0)
            (selectedTitle selectedCount)
        , div [ class "init-section__caption" ]
            [ text "Rolls 1d20 + creature's initiative bonus from stat block" ]
        ]


{-| One row in the Auto-roll section: the main "& Sort" button on
the left, the Advantage sister button on the right. Both fire
`InitiativeAutoRoll` with the same scope; only the mode differs.
-}
autoRollPair : RollScope -> String -> Bool -> String -> Html Msg
autoRollPair scope label enabled tipOverride =
    let
        mainTitle =
            if String.isEmpty tipOverride then
                "Roll 1d20 + initiative bonus"

            else
                tipOverride

        advTitle =
            if enabled then
                "Roll 2d20, keep highest, + initiative bonus (5e advantage)"

            else
                tipOverride
    in
    div [ class "init-btn-row" ]
        [ button
            [ class "action-btn action-btn--green init-btn-block"
            , onClick (InitiativeAutoRoll scope ModeStandard)
            , disabled (not enabled)
            , attribute "aria-disabled"
                (if enabled then
                    "false"

                 else
                    "true"
                )
            , title mainTitle
            ]
            [ text label ]
        , button
            [ class "action-btn action-btn--green init-btn-adv"
            , onClick (InitiativeAutoRoll scope ModeAdvantage)
            , disabled (not enabled)
            , attribute "aria-disabled"
                (if enabled then
                    "false"

                 else
                    "true"
                )
            , title advTitle
            ]
            [ text "Advantage" ]
        ]


custom : InitiativeUi -> Int -> Html Msg
custom ui selectedCount =
    div [ class "init-section" ]
        [ h3 [ class "init-section__heading" ]
            [ text "Custom Initiative" ]
        , div [ class "init-section__row" ]
            [ Html.label [ for "init-custom-value" ]
                [ text "Initiative Value:" ]
            , input
                [ id "init-custom-value"
                , class "init-section__input"
                , type_ "number"
                , Attr.min "-99"
                , Attr.max "99"
                , value ui.customValueText
                , onInput InitiativeCustomChanged
                , Html.Events.on "keydown" (Util.Keyboard.enterKey InitiativeApplyTarget)
                ]
                []
            ]
        , button
            [ class "action-btn action-btn--green init-btn-block"
            , onClick InitiativeApplyTarget
            ]
            [ text ("Apply & Sort: " ++ ui.target) ]
        , button
            [ class "action-btn action-btn--green init-btn-block"
            , onClick InitiativeApplySelected
            , disabled (selectedCount == 0)
            , attribute "aria-disabled"
                (if selectedCount == 0 then
                    "true"

                 else
                    "false"
                )
            , title (selectedTitle selectedCount)
            ]
            [ text ("Apply & Sort: Selected" ++ selectedCountSuffix selectedCount) ]
        ]


{-| Tooltip for "Selected" buttons: explains why they're disabled
when no creatures are checked, and confirms the count when at least
one is. Saves the GM a click to figure out why nothing happens.
-}
selectedTitle : Int -> String
selectedTitle n =
    case n of
        0 ->
            "No creatures are selected — tick the row 1 checkbox on the cards you want first"

        1 ->
            "1 creature selected"

        _ ->
            String.fromInt n ++ " creatures selected"


selectedCountSuffix : Int -> String
selectedCountSuffix n =
    if n > 0 then
        " (" ++ String.fromInt n ++ ")"

    else
        ""


footer : Html Msg
footer =
    div [ class "init-footer" ]
        [ button
            [ class "action-btn"
            , onClick InitiativeClose
            ]
            [ text "Close" ]
        ]
