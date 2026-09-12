module View.Inline.Initiative exposing (view)

{-| Initiative editor body.

How to roll is a setting the action buttons read, so picking a
mode and picking who it applies to stay separate choices.

-}

import Html exposing (Html, div, input, span, text)
import Html.Attributes as Attr exposing (checked, class, for, id, maxlength, type_, value)
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
    div [ class "editor-body" ]
        [ rollSection selectedCount ui
        , manualSection selectedCount ui
        , sortSection
        ]


rollSection : Int -> InitiativeUi -> Html Msg
rollSection selectedCount ui =
    div [ class "cond-section" ]
        [ div [ class "cond-row" ]
            [ Html.label [ class "cond-label" ] [ text "Roll:" ]
            , modeToggle ui ModeAdvantage "Advantage"
            , modeToggle ui ModeDisadvantage "Disadvantage"
            ]
        , ApplyButton.row "Roll & sort:"
            [ ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--green"
                , msg = InitiativeAutoRoll ScopeTarget
                , tip = "Roll for " ++ ui.target
                , label = "Target"
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
                , label = "Selected (" ++ String.fromInt selectedCount ++ ")"
                }
            , ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--green"
                , msg = InitiativeAutoRoll ScopeAll
                , tip = "Roll for the whole queue"
                , label = "All"
                }
            ]
        ]


manualSection : Int -> InitiativeUi -> Html Msg
manualSection selectedCount ui =
    div [ class "cond-section" ]
        [ div [ class "cond-row" ]
            [ Html.label [ for "init-custom-value", class "cond-label" ] [ text "or Set:" ]
            , input
                [ id "init-custom-value"
                , class "cond-input cond-input--2ch"
                , type_ "text"
                , maxlength 2
                , value ui.customValueText
                , onInput InitiativeCustomChanged
                , Html.Events.on "keydown" (Util.Keyboard.enterKey InitiativeApplyTarget)
                ]
                []
            ]
        , ApplyButton.row "Apply to:"
            [ ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--green"
                , msg = InitiativeApplyTarget
                , tip = "Set " ++ ui.target ++ "'s initiative to the typed value"
                , label = "Target"
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
                , label = "Selected (" ++ String.fromInt selectedCount ++ ")"
                }
            ]
        ]


sortSection : Html Msg
sortSection =
    div [ class "cond-section" ]
        [ div [ class "note-edit__buttons init-quicksort-row" ]
            [ ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--blue"
                , msg = InitiativeQuickSort
                , tip = "Sort the queue by the initiatives it already has"
                , label = "🔄 Quick Sort Encounter"
                }
            ]
        ]


{-| Advantage / Disadvantage: re-clicking the active one clears
it back to a standard roll instead of requiring a third
"Standard" button to undo it. The two stay mutually exclusive
since `rollMode` only ever holds one value.
-}
modeToggle : InitiativeUi -> RollMode -> String -> Html Msg
modeToggle ui mode label =
    let
        isSelected =
            ui.rollMode == mode

        nextMode =
            if isSelected then
                ModeStandard

            else
                mode
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
            , onClick (InitiativeRollModeSet nextMode)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]
