module View.Inline.HpChange exposing (Context, view)

{-| Manage HP as a drawer panel — every way of changing a
creature's pools on one surface, without covering the queue.

An amount is either typed or rolled, and the two fields offering
that choice sit side by side with the one left alone greyed out,
so which of them a verb will commit is visible before it is
clicked. Parse errors surface inline underneath. Below them,
behind a fold, the Set HP section writes pools to absolute values
on the same typed-or-rolled terms.

The editor's log holds every change, behind a fold of its own;
the dice roller's log shows only the ones a roll produced.

-}

import Dice
import HpChange
import Html exposing (Html, button, div, input, span, text)
import Html.Attributes as Attr exposing (attribute, autofocus, class, disabled, for, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg exposing (HpField(..), HpKind(..), Msg(..))
import Set exposing (Set)
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi)
import Util.Keyboard
import View.HpLog
import View.Inline.ApplyButton as ApplyButton
import View.Inline.Field as Field
import View.Tooltips as Tooltips


{-| The model fragments the editor consumes beyond its own Ui
record.
-}
type alias Context =
    { selectedCount : Int
    , placeholderWarning : Bool
    , targetTempHp : Int
    , log : List HpChangeEntry
    , logOpen : Bool
    , setOpen : Bool
    , flashedSeq : Int
    , expanded : Set String
    }


view : Context -> HpChangeUi -> Html Msg
view ctx ui =
    div [ class "editor-body" ]
        [ div [ class "cond-section" ]
            [ amount ctx.selectedCount ctx.targetTempHp ui
            , parseErrorHint ui.parseError
            , freshRollOption ctx.selectedCount ui
            , actionButtons
            , ApplyButton.placeholderNotice ctx.placeholderWarning
            ]
        , setHpSection ctx ui
        , View.HpLog.section
            { open = ctx.logOpen
            , flashedSeq = ctx.flashedSeq
            , expanded = ctx.expanded
            }
            ctx.log
        ]


{-| Hit points set outright rather than changed, behind a fold.
The hit-points value is typed or rolled on the same terms as the
verb row's amount; the maximum and temporary fields sit below it
and apply either way. A blank field leaves its pool alone, so one
pool can be set without restating the others.
-}
setHpSection : Context -> HpChangeUi -> Html Msg
setHpSection ctx ui =
    let
        rolling =
            holdsText ui.manualRollText

        applyTip scope =
            if rolling then
                "Roll the formula for " ++ scope ++ " and set its hit points to the total"

            else
                "Set the typed pools on " ++ scope
    in
    div [ class "cond-section" ]
        (Field.foldHead
            { open = ctx.setOpen
            , title = "Set HP"
            , msg = HpChangeSetToggle
            , trail = []
            }
            :: (if not ctx.setOpen then
                    []

                else
                    [ div [ class "cond-row cond-row--pools" ]
                        [ poolField rolling "" "manual-hp" "Set HP to:" ui.manualHpText CurrentHpField
                        , fieldPair (holdsText ui.manualHpText)
                            split
                            "manual-roll"
                            "or Roll HP:"
                            [ class "cond-input cond-input--w12"
                            , type_ "text"
                            , placeholder "e.g. 2d6+3"
                            , value ui.manualRollText
                            , onInput HpChangeManualRollChanged
                            , Html.Events.on "keydown" (Util.Keyboard.enterKey HpChangeManualApplyTarget)
                            , Tooltips.attr Tooltips.hpRoll
                            ]
                            [ clearRoll ui.manualRollText HpChangeManualRollClear Tooltips.hpRollClear ]
                        ]
                    , parseErrorHint ui.manualRollError
                    , div [ class "cond-row cond-row--pools" ]
                        [ poolField False "" "manual-max-hp" "Set Max HP to:" ui.manualMaxHpText MaxHpField
                        , poolField False split "manual-temp-hp" "Set Temp HP to:" ui.manualTempHpText TempHpField
                        ]
                    , ApplyButton.row "Apply to:"
                        [ ApplyButton.view
                            { enabled = True
                            , cls = "action-btn action-btn--green"
                            , msg = HpChangeManualApplyTarget
                            , tip = applyTip "the target creature"
                            , label = "Target"
                            }
                        , ApplyButton.view
                            { enabled = ctx.selectedCount > 0
                            , cls = "action-btn action-btn--green"
                            , msg = HpChangeManualApplySelected
                            , tip =
                                if ctx.selectedCount == 0 then
                                    "Select creatures first"

                                else
                                    applyTip "every selected creature"
                            , label = "Selected (" ++ String.fromInt ctx.selectedCount ++ ")"
                            }
                        ]
                    , ApplyButton.placeholderNotice ctx.placeholderWarning
                    ]
               )
        )


{-| Extra air before a pair, separating it from the pair it
follows. The first pair trails the section heading rather than
another field, so it goes without.
-}
split : String
split =
    "cond-pair--split"


{-| One pool field, standing aside while the field beside it has
taken its job over.
-}
poolField : Bool -> String -> String -> String -> String -> HpField -> Html Msg
poolField muted extraClass fieldId label current field =
    fieldPair muted
        extraClass
        fieldId
        label
        [ class "cond-input cond-input--pool"
        , type_ "number"
        , Attr.min "0"
        , Attr.max "999"
        , value current
        , onInput (HpChangeManualChanged field)
        ]
        []


{-| A labelled field that greys out as a whole — label included —
once something else is supplying its value, so the field a click
will actually commit is the one still in full colour. Anything
trailing the field belongs to it, and rides along when a narrow
panel wraps the pair onto its own line.
-}
fieldPair : Bool -> String -> String -> String -> List (Html.Attribute Msg) -> List (Html Msg) -> Html Msg
fieldPair muted extraClass fieldId label attrs trail =
    span
        [ class
            (String.join " "
                (List.filterMap identity
                    [ Just "cond-pair"
                    , if String.isEmpty extraClass then
                        Nothing

                      else
                        Just extraClass
                    , if muted then
                        Just "cond-pair--muted"

                      else
                        Nothing
                    ]
                )
            )
        ]
        (Html.label [ for fieldId, class "cond-label" ] [ text label ]
            :: input (id fieldId :: disabled muted :: attrs) []
            :: trail
        )


{-| Empties a formula field, which is what hands the job back to
the number beside it.
-}
clearRoll : String -> Msg -> String -> Html Msg
clearRoll current msg tip =
    if holdsText current then
        button
            [ class "icon-btn icon-btn--sm icon-btn--red"
            , type_ "button"
            , onClick msg
            , Tooltips.attr tip
            , attribute "aria-label" "Clear the roll"
            ]
            [ text "×" ]

    else
        text ""


holdsText : String -> Bool
holdsText =
    not << String.isEmpty << String.trim


{-| The amount row. Enter commits as `DamageKind` because the
expansion has four commit paths; Enter isn't safely overloadable
across all of them. GMs who want Heal / Temp HP / +Max HP click
the corresponding button.
-}
amount : Int -> Int -> HpChangeUi -> Html Msg
amount selectedCount targetTempHp ui =
    div [ class "cond-row" ]
        [ fieldPair (holdsText ui.amountRollText)
            ""
            "hp-amount"
            "HP:"
            [ class "cond-input cond-input--pool"
            , type_ "number"
            , Attr.min "0"
            , Attr.max "999"
            , placeholder "12"
            , value ui.amountText
            , autofocus True
            , onInput HpChangeAmountChanged
            , Html.Events.on "keydown" (Util.Keyboard.enterKey (HpChangeApplyAs DamageKind))
            ]
            []
        , fieldPair (holdsText ui.amountText)
            split
            "hp-amount-roll"
            "or Roll:"
            [ class "cond-input cond-input--w12"
            , type_ "text"
            , placeholder "e.g. 2d6+3"
            , value ui.amountRollText
            , onInput HpChangeAmountRollChanged
            , Html.Events.on "keydown" (Util.Keyboard.enterKey (HpChangeApplyAs DamageKind))
            , Tooltips.attr Tooltips.hpAmountRoll
            ]
            [ clearRoll ui.amountRollText (HpChangeAmountRollChanged "") Tooltips.hpAmountRollClear ]
        , tempHpCap targetTempHp ui
        , applyScope selectedCount ui
        ]


{-| An amount that would leave the creature's existing temp HP
standing lands as nothing at all, so this names what it is up
against — "4 < 8" — beside the field, where a GM sees it before
committing rather than after. A formula reads as no amount, since
its total is not known until it is rolled.
-}
tempHpCap : Int -> HpChangeUi -> Html Msg
tempHpCap targetTempHp ui =
    let
        typed =
            String.toInt (String.trim ui.amountText)
                |> Maybe.withDefault 0

        relation =
            if typed == targetTempHp then
                " = "

            else
                " < "
    in
    if typed > 0 && targetTempHp > 0 && HpChange.keepsExistingTempHp typed targetTempHp then
        span [ class "hp-change__temp-cap" ]
            [ text (String.fromInt typed ++ relation ++ String.fromInt targetTempHp) ]

    else
        text ""


parseErrorHint : Maybe Dice.Error -> Html Msg
parseErrorHint error =
    case error of
        Just (Dice.ParseError raw) ->
            div [ class "cond-section__caption cond-section__caption--danger" ]
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
        Field.checkbox
            { checked = ui.applyToSelected
            , msg = HpChangeApplyToSelectedToggle
            , label = "Selected (" ++ String.fromInt selectedCount ++ ")"
            , extra = []
            }


{-| With a formula in hand and a selection in play, offer a fresh
roll per creature instead of one shared total; a typed amount
hides it, since there is nothing to reroll.
-}
freshRollOption : Int -> HpChangeUi -> Html Msg
freshRollOption selectedCount ui =
    if selectedCount > 0 && holdsText ui.amountRollText then
        div [ class "cond-row" ]
            [ Field.checkbox
                { checked = ui.freshRollPerTarget
                , msg = HpChangeFreshRollToggle
                , label = "New roll for each creature"
                , extra = []
                }
            ]

    else
        text ""


{-| The verb buttons, each committing the current amount, and the
reset beside them, which takes no amount at all. The editor stays
open afterwards so the GM can keep applying; the ringed trigger,
Escape, or the header-less toggle close it. Each verb is
colour-coded to match the existing damage / heal / temp
affordances.
-}
actionButtons : Html Msg
actionButtons =
    div [ class "cond-row" ]
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
        , button
            [ class "action-btn action-btn--orange"
            , onClick HpChangeResetToDefault
            , Tooltips.attr Tooltips.hpResetDefault
            , attribute "aria-label" Tooltips.hpResetDefault
            ]
            [ text "↩" ]
        ]
