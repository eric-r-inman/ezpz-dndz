module View.Inline.HpChange exposing (view)

{-| Manage HP as a drawer panel — every way of changing a
creature's pools on one surface, without covering the queue.

The verb buttons share a smart amount input: type a plain
integer (`8`) to apply that value directly, or a dice formula
(`2d6+3`) to roll and apply the total. Parse errors surface
inline underneath the input, and the input decides which path a
verb takes. Below them, the Manual section sets the pools to
typed values instead.

Only the newest log entry renders here (with its undo button);
the rest of the log lives in the dice roller.

-}

import Dice
import Html exposing (Html, button, div, h3, input, span, text)
import Html.Attributes as Attr exposing (autofocus, checked, class, for, id, maxlength, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg exposing (HpField(..), HpKind(..), Msg(..))
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi)
import Util.Keyboard
import View.HpLog
import View.Inline.ApplyButton as ApplyButton


view : Int -> View.HpLog.Latest -> List HpChangeEntry -> HpChangeUi -> Html Msg
view selectedCount latest log ui =
    div [ class "creature-card__inline" ]
        [ amount selectedCount ui
        , parseErrorHint ui
        , freshRollOption selectedCount ui
        , actionButtons
        , div [ class "cond-divider" ] []
        , manualSection selectedCount ui
        , View.HpLog.latest latest log
        ]


{-| Direct pool entry, for the times the GM knows the number
rather than the change: type into any of the three, then apply
to the target or the selection. Blank fields are left alone, so
one pool can be set without restating the others.
-}
manualSection : Int -> HpChangeUi -> Html Msg
manualSection selectedCount ui =
    div [ class "cond-section" ]
        [ div [ class "cond-row cond-row--pools" ]
            [ h3
                [ class "cond-section__heading cond-section__heading--inline" ]
                [ text "Manual:" ]
            , manualField "" "manual-hp" "HP" ui.manualHpText CurrentHpField
            , manualField split "manual-max-hp" "Max" ui.manualMaxHpText MaxHpField
            , manualField split "manual-temp-hp" "Temp" ui.manualTempHpText TempHpField
            ]
        , ApplyButton.row "Apply to:"
            [ ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--green"
                , msg = HpChangeManualApplyTarget
                , tip = "Set the typed pools on the target creature"
                , label = "Target"
                }
            , ApplyButton.view
                { enabled = selectedCount > 0
                , cls = "action-btn action-btn--green"
                , msg = HpChangeManualApplySelected
                , tip =
                    if selectedCount == 0 then
                        "Select creatures first"

                    else
                        "Set the typed pools on every selected creature"
                , label = "Selected (" ++ String.fromInt selectedCount ++ ")"
                }
            ]
        ]


{-| Extra air before a pair, separating it from the pair it
follows. The first pair trails the section heading rather than
another field, so it goes without.
-}
split : String
split =
    "hp-change__manual-field--split"


manualField : String -> String -> String -> String -> HpField -> Html Msg
manualField extraClass fieldId label current field =
    span [ class ("hp-change__manual-field " ++ extraClass) ]
        [ Html.label [ for fieldId, class "hp-change__manual-label" ] [ text label ]
        , input
            [ id fieldId
            , class "cond-input cond-input--pool"
            , type_ "number"
            , Attr.min "0"
            , Attr.max "9999"
            , value current
            , onInput (HpChangeManualChanged field)
            ]
            []
        ]


{-| The amount row: the field itself, then the scope checkbox
(only while something is selected) trailing it. Enter commits as
`DamageKind` because the expansion has four commit paths; Enter
isn't safely overloadable across all of them. GMs who want Heal
/ Temp HP / +Max HP click the corresponding button.
-}
amount : Int -> HpChangeUi -> Html Msg
amount selectedCount ui =
    div [ class "hp-change__row" ]
        [ Html.label [ class "hp-change__label", for "hp-amount" ]
            [ text "HP:" ]
        , input
            [ id "hp-amount"
            , class "hp-change__input"
            , type_ "text"
            , placeholder "12"
            , maxlength 3
            , value ui.amountText
            , autofocus True
            , onInput HpChangeAmountChanged
            , Html.Events.on "keydown" (Util.Keyboard.enterKey (HpChangeApplyAs DamageKind))
            ]
            []
        , applyScope selectedCount ui
        ]


parseErrorHint : HpChangeUi -> Html Msg
parseErrorHint ui =
    case ui.parseError of
        Just (Dice.ParseError raw) ->
            div [ class "hp-change__error" ]
                [ text ("Couldn't parse: " ++ raw) ]

        Nothing ->
            text ""


{-| Multi-target scope checkbox. Hidden entirely when zero
creatures are selected — there's no useful "apply to all
selected" when there's no selection.
-}
applyScope : Int -> HpChangeUi -> Html Msg
applyScope selectedCount ui =
    if selectedCount == 0 then
        text ""

    else
        Html.label [ class "hp-change__checkbox" ]
            [ input
                [ type_ "checkbox"
                , checked ui.applyToSelected
                , onClick HpChangeApplyToSelectedToggle
                ]
                []
            , text (" Selected (" ++ String.fromInt selectedCount ++ ")")
            ]


{-| When the amount reads as a dice formula and a selection is
in play, offer a fresh roll per creature instead of one shared
total; an integer amount hides it, since there is nothing to
reroll.
-}
freshRollOption : Int -> HpChangeUi -> Html Msg
freshRollOption selectedCount ui =
    if selectedCount > 0 && isFormula ui.amountText then
        div [ class "hp-change__row" ]
            [ Html.label [ class "hp-change__checkbox" ]
                [ input
                    [ type_ "checkbox"
                    , checked ui.freshRollPerTarget
                    , onClick HpChangeFreshRollToggle
                    ]
                    []
                , text " New roll for each creature"
                ]
            ]

    else
        text ""


{-| True when the amount text parses as a dice formula rather
than a plain integer.
-}
isFormula : String -> Bool
isFormula raw =
    let
        trimmed =
            String.trim raw
    in
    not (String.isEmpty trimmed)
        && (String.toInt trimmed == Nothing)
        && (case Dice.parse trimmed of
                Ok _ ->
                    True

                Err _ ->
                    False
           )


{-| Four action buttons — each commits the current amount using
that verb. The editor stays open afterwards so the GM can keep
applying; the ringed trigger, Escape, or the header-less toggle
close it. Each verb is colour-coded to match the existing
damage / heal / temp affordances.
-}
actionButtons : Html Msg
actionButtons =
    div [ class "hp-change__actions" ]
        [ button
            [ class "action-btn action-btn--damage"
            , onClick (HpChangeApplyAs DamageKind)
            ]
            [ text "Damage" ]
        , button
            [ class "action-btn action-btn--heal"
            , onClick (HpChangeApplyAs HealKind)
            ]
            [ text "Heal" ]
        , button
            [ class "action-btn action-btn--temp"
            , onClick (HpChangeApplyAs TempHpKind)
            ]
            [ text "+ Temp" ]
        , button
            [ class "action-btn action-btn--max"
            , onClick (HpChangeApplyAs MaxHpKind)
            ]
            [ text "+ Max" ]
        ]
