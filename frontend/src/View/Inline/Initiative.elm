module View.Inline.Initiative exposing (view)

{-| Initiative editor as a docked toolbar expansion: a
single-button queue sort, an auto-roll batch (one row each for
target / all / selected), and a custom value with its own apply
buttons.
-}

import Html exposing (Html, button, div, h3, input, span, text)
import Html.Attributes as Attr exposing (attribute, class, disabled, for, id, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg
    exposing
        ( Msg(..)
        , RollMode(..)
        , RollScope(..)
        )
import Ui.Initiative exposing (InitiativeUi)
import Util.Keyboard
import View.Tooltips as Tooltips


view : Int -> InitiativeUi -> Html Msg
view selectedCount ui =
    div [ class "creature-card__inline" ]
        [ quickSort
        , autoRoll ui selectedCount
        , custom ui selectedCount
        ]


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
        -- An unavailable row explains itself through the caller's
        -- override rather than the usual per-button hover text.
        tipFor standard =
            if enabled then
                standard

            else
                tipOverride
    in
    [ scopeButton
        { enabled = enabled
        , cls = "action-btn action-btn--green init-btn-block"
        , msg = InitiativeAutoRoll scope ModeStandard
        , tip =
            if String.isEmpty tipOverride then
                Tooltips.initRollStandard

            else
                tipOverride
        , label = label
        }
    , scopeButton
        { enabled = enabled
        , cls = "action-btn action-btn--blue init-btn-adv"
        , msg = InitiativeAutoRoll scope ModeAdvantage
        , tip = tipFor Tooltips.initRollAdvantage
        , label = "Advantage"
        }
    , scopeButton
        { enabled = enabled
        , cls = "action-btn action-btn--orange init-btn-adv"
        , msg = InitiativeAutoRoll scope ModeDisadvantage
        , tip = tipFor Tooltips.initRollDisadvantage
        , label = "Disadvantage"
        }
    , scopeButton
        { enabled = enabled
        , cls = "action-btn action-btn--yellow init-btn-adv"
        , msg = InitiativeAutoRollSurprised scope
        , tip =
            tipFor "Roll initiative at disadvantage and flag as Surprised (clears at the end of their first turn)"
        , label = "Disadv. & Surprised"
        }
    ]


{-| A button whose scope may be empty. Chrome swallows mouse
events on a disabled control, so the unavailable state hangs its
tooltip on a wrapper span and opts the button out of pointer
events — otherwise the hover text explaining why the button is
dead could never appear.
-}
scopeButton :
    { enabled : Bool
    , cls : String
    , msg : Msg
    , tip : String
    , label : String
    }
    -> Html Msg
scopeButton cfg =
    if cfg.enabled then
        button
            [ class cfg.cls
            , onClick cfg.msg
            , Tooltips.attr cfg.tip
            ]
            [ text cfg.label ]

    else
        span
            [ class "init-btn-wrap"
            , Tooltips.attr cfg.tip
            ]
            [ button
                [ class (cfg.cls ++ " init-btn-inert")
                , disabled True
                , attribute "aria-disabled" "true"
                ]
                [ text cfg.label ]
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
            [ scopeButton
                { enabled = selectedCount > 0
                , cls = "action-btn action-btn--green init-btn-block"
                , msg = InitiativeApplySelected
                , tip = selectedTitle selectedCount
                , label = "Apply & Sort: Selected" ++ selectedCountSuffix selectedCount
                }
            , scopeButton
                { enabled = selectedCount > 0
                , cls = "action-btn action-btn--yellow init-btn-block"
                , msg = InitiativeApplySelectedSurprised
                , tip =
                    if selectedCount == 0 then
                        Tooltips.initSelectedNone

                    else
                        "Apply the typed initiative to selected AND flag them as Surprised"
                , label = "Apply & Sort w/Surprised"
                }
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
