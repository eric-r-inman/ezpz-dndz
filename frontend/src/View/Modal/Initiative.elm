module View.Modal.Initiative exposing (view)

{-| Initiative manager modal. Three stacked sections: a single-button
quick sort, an auto-roll batch (one button each for target / all /
selected), and a custom value entry with target / selected apply.
Closes on backdrop click or Cancel.
-}

import Html exposing (Html, button, div, h3, input, text)
import Html.Attributes as Attr exposing (attribute, class, disabled, for, id, type_, value)
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
import View.Tooltips as Tooltips


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
                , chrome = model.modalChrome
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
        , div [ class "init-btn-grid" ]
            (List.concat
                [ autoRollPair ScopeTarget
                    "Roll initiative & Sort: This"
                    True
                    ("Roll for " ++ ui.target)
                , autoRollPair ScopeAll
                    "Roll initiative & Sort: All"
                    True
                    ""
                , autoRollPair ScopeSelected
                    "Roll initiative & Sort: Selected"
                    (selectedCount > 0)
                    (selectedTitle selectedCount)
                ]
            )
        , div [ class "init-section__caption" ]
            [ text "Rolls 1d20 + creature's initiative bonus from stat block" ]
        ]


{-| Four buttons of one auto-roll row: the main "& Sort" button
on the left, Advantage (blue), Disadvantage (orange), and the
"Disadv. & Surprised" yellow button on the right. Returned as a
flat list so the caller can drop them straight into a four-column
grid — the main-button widths line up across all three rows so
the four-column layout reads as a clean grid.
-}
autoRollPair : RollScope -> String -> Bool -> String -> List (Html Msg)
autoRollPair scope label enabled tipOverride =
    let
        mainTitle =
            if String.isEmpty tipOverride then
                Tooltips.initRollStandard

            else
                tipOverride

        advTitle =
            if enabled then
                Tooltips.initRollAdvantage

            else
                tipOverride

        disTitle =
            if enabled then
                Tooltips.initRollDisadvantage

            else
                tipOverride

        surpriseTitle =
            if enabled then
                "Roll initiative at disadvantage and flag as Surprised (clears at the end of their first turn)"

            else
                tipOverride

        ariaDisabled =
            attribute "aria-disabled"
                (if enabled then
                    "false"

                 else
                    "true"
                )
    in
    [ button
        [ class "action-btn action-btn--green init-btn-block"
        , onClick (InitiativeAutoRoll scope ModeStandard)
        , disabled (not enabled)
        , ariaDisabled
        , Tooltips.attr mainTitle
        ]
        [ text label ]
    , button
        [ class "action-btn action-btn--blue init-btn-adv"
        , onClick (InitiativeAutoRoll scope ModeAdvantage)
        , disabled (not enabled)
        , ariaDisabled
        , Tooltips.attr advTitle
        ]
        [ text "Advantage" ]
    , button
        [ class "action-btn action-btn--orange init-btn-adv"
        , onClick (InitiativeAutoRoll scope ModeDisadvantage)
        , disabled (not enabled)
        , ariaDisabled
        , Tooltips.attr disTitle
        ]
        [ text "Disadvantage" ]
    , button
        [ class "action-btn action-btn--yellow init-btn-adv"
        , onClick (InitiativeAutoRollSurprised scope)
        , disabled (not enabled)
        , ariaDisabled
        , Tooltips.attr surpriseTitle
        ]
        [ text "Disadv. & Surprised" ]
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
        , div [ class "init-custom-row" ]
            [ button
                [ class "action-btn action-btn--green init-btn-block"
                , onClick InitiativeApplyTarget
                ]
                [ text ("Apply & Sort: " ++ ui.target) ]
            , button
                [ class "action-btn action-btn--yellow init-btn-block"
                , onClick InitiativeApplyTargetSurprised
                , Tooltips.attr "Apply the typed initiative AND flag this creature as Surprised"
                ]
                [ text "Apply & Sort w/Surprised" ]
            ]
        , div [ class "init-custom-row" ]
            [ button
                [ class "action-btn action-btn--green init-btn-block"
                , onClick InitiativeApplySelected
                , disabled (selectedCount == 0)
                , attribute "aria-disabled"
                    (if selectedCount == 0 then
                        "true"

                     else
                        "false"
                    )
                , Tooltips.attr (selectedTitle selectedCount)
                ]
                [ text ("Apply & Sort: Selected" ++ selectedCountSuffix selectedCount) ]
            , button
                [ class "action-btn action-btn--yellow init-btn-block"
                , onClick InitiativeApplySelectedSurprised
                , disabled (selectedCount == 0)
                , attribute "aria-disabled"
                    (if selectedCount == 0 then
                        "true"

                     else
                        "false"
                    )
                , Tooltips.attr
                    (if selectedCount == 0 then
                        Tooltips.initSelectedNone

                     else
                        "Apply the typed initiative to selected AND flag them as Surprised"
                    )
                ]
                [ text "Apply & Sort w/Surprised" ]
            ]
        ]


{-| Tooltip for "Selected" buttons: explains why they're disabled
when no creatures are checked, and confirms the count when at least
one is. Saves the GM a click to figure out why nothing happens.
-}
selectedTitle : Int -> String
selectedTitle n =
    case n of
        0 ->
            Tooltips.initSelectedNone

        1 ->
            Tooltips.initSelectedOne

        _ ->
            Tooltips.initSelectedMany n


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
