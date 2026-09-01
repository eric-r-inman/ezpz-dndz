module View.Inline.Initiative exposing (view)

{-| Initiative editor body.

How to roll is a setting the action buttons read, so picking a
mode and picking who it applies to stay separate choices.

-}

import Html exposing (Html, div, h3, input, span, text)
import Html.Attributes as Attr exposing (checked, class, for, id, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg
    exposing
        ( Msg(..)
        , RollMode(..)
        , RollScope(..)
        )
import Ui.Initiative exposing (InitiativeUi)
import Util.Keyboard
import View.Inline.ApplyButton as ApplyButton
import View.Tooltips as Tooltips


view : Int -> InitiativeUi -> Html Msg
view selectedCount ui =
    div [ class "creature-card__inline" ]
        [ rollSection selectedCount ui
        , div [ class "cond-divider" ] []
        , manualSection selectedCount ui
        , div [ class "cond-divider" ] []
        , sortSection
        ]


rollSection : Int -> InitiativeUi -> Html Msg
rollSection selectedCount ui =
    div [ class "cond-section" ]
        [ div [ class "cond-row" ]
            [ Html.label [] [ text "Roll:" ]
            , modeRadio ui ModeStandard "Standard"
            , modeRadio ui ModeAdvantage "Advantage"
            , modeRadio ui ModeDisadvantage "Disadvantage"
            , surprisedToggle ui
            ]
        , div [ class "cond-section__caption" ]
            [ text "Rolls 1d20 plus the creature's initiative bonus, then sorts the queue." ]
        , div [ class "note-edit__buttons note-edit__buttons--start" ]
            [ ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--green"
                , msg = InitiativeAutoRoll ScopeTarget
                , tip = "Roll for " ++ ui.target
                , label = "Roll for Target"
                }
            , ApplyButton.view
                { enabled = selectedCount > 0
                , cls = "action-btn action-btn--green"
                , msg = InitiativeAutoRoll ScopeSelected
                , tip =
                    if selectedCount == 0 then
                        Tooltips.initSelectedNone

                    else
                        "Roll for every selected creature"
                , label = "Roll for Selected (" ++ String.fromInt selectedCount ++ ")"
                }
            , ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--green"
                , msg = InitiativeAutoRoll ScopeAll
                , tip = "Roll for the whole queue"
                , label = "Roll for All"
                }
            ]
        ]


manualSection : Int -> InitiativeUi -> Html Msg
manualSection selectedCount ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ] [ text "Set to:" ]
        , div [ class "cond-row" ]
            [ Html.label [ for "init-custom-value" ] [ text "Initiative:" ]
            , input
                [ id "init-custom-value"
                , class "cond-input cond-input--w20"
                , type_ "number"
                , Attr.min "-99"
                , Attr.max "99"
                , value ui.customValueText
                , onInput InitiativeCustomChanged
                , Html.Events.on "keydown" (Util.Keyboard.enterKey InitiativeApplyTarget)
                ]
                []
            ]
        , div [ class "note-edit__buttons note-edit__buttons--start" ]
            [ ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--green"
                , msg = InitiativeApplyTarget
                , tip = "Set " ++ ui.target ++ "'s initiative to the typed value"
                , label = "Apply to Target"
                }
            , ApplyButton.view
                { enabled = selectedCount > 0
                , cls = "action-btn action-btn--green"
                , msg = InitiativeApplySelected
                , tip =
                    if selectedCount == 0 then
                        Tooltips.initSelectedNone

                    else
                        "Set every selected creature to the typed value"
                , label = "Apply to Selected (" ++ String.fromInt selectedCount ++ ")"
                }
            ]
        ]


sortSection : Html Msg
sortSection =
    div [ class "cond-section" ]
        [ div [ class "note-edit__buttons note-edit__buttons--start" ]
            [ ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--blue"
                , msg = InitiativeQuickSort
                , tip = "Sort the queue by the initiatives it already has"
                , label = "🔄 Quick Sort Encounter"
                }
            ]
        ]


modeRadio : InitiativeUi -> RollMode -> String -> Html Msg
modeRadio ui mode label =
    let
        isSelected =
            ui.rollMode == mode
    in
    Html.label
        [ class
            (if isSelected then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        ]
        [ input
            [ type_ "radio"
            , Attr.name "initiative-roll-mode"
            , checked isSelected
            , onClick (InitiativeRollModeSet mode)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


{-| Rides with whichever action the GM clicks, rolled or typed,
so Surprised does not need its own copy of every button.
-}
surprisedToggle : InitiativeUi -> Html Msg
surprisedToggle ui =
    Html.label
        [ class
            (if ui.markSurprised then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        , Tooltips.attr "Also flag whoever this applies to as Surprised"
        ]
        [ input
            [ type_ "checkbox"
            , class
                (if ui.markSurprised then
                    "cond-check cond-check--on"

                 else
                    "cond-check"
                )
            , checked ui.markSurprised
            , onClick InitiativeSurprisedToggle
            ]
            []
        , span [ class "cond-radio__label" ] [ text "+ Surprised" ]
        ]
