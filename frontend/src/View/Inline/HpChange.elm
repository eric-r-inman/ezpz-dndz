module View.Inline.HpChange exposing (Context, view)

{-| Manage HP as a drawer panel — every way of changing a
creature's pools on one surface, without covering the queue.

The verb buttons share a smart amount input: type a plain
integer (`8`) to apply that value directly, or a dice formula
(`2d6+3`) to roll and apply the total. Parse errors surface
inline underneath the input, and the input decides which path a
verb takes. Below them, behind a fold, the Roll or Set section
rolls a formula for each target's hit points or writes the pools
to typed values instead.

The editor's log holds every change, behind a fold of its own;
the dice roller's log shows only the ones a roll produced.

-}

import Dice
import Html exposing (Html, button, div, input, span, text)
import Html.Attributes as Attr exposing (attribute, autofocus, class, disabled, for, id, maxlength, placeholder, type_, value)
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
record: the selection drives the scope controls, and the log
renders with the fold state, the seq it last flashed, and the rows
the GM has unfolded.
-}
type alias Context =
    { selectedCount : Int
    , placeholderWarning : Bool
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
            [ amount ctx.selectedCount ui
            , parseErrorHint ui.parseError
            , freshRollOption ctx.selectedCount ui
            , actionButtons
            , ApplyButton.placeholderNotice ctx.placeholderWarning
            ]
        , rollOrSetSection ctx ui
        , View.HpLog.section
            { open = ctx.logOpen
            , flashedSeq = ctx.flashedSeq
            , expanded = ctx.expanded
            }
            ctx.log
        ]


{-| Hit points set outright rather than changed, behind a fold.
A formula in the Roll field, applied, rolls once per target and
sets that creature's hit points to the total, the way a monster's
hit dice roll stands in for its average; while it holds one the
pool fields below stand aside. Otherwise the pools are set to
what was typed, a blank field leaving its pool alone so one can
be set without restating the others.
-}
rollOrSetSection : Context -> HpChangeUi -> Html Msg
rollOrSetSection ctx ui =
    let
        rolling =
            not (String.isEmpty (String.trim ui.manualRollText))

        applyTip scope =
            if rolling then
                "Roll the formula for " ++ scope ++ " and set its hit points to the total"

            else
                "Set the typed pools on " ++ scope
    in
    div [ class "cond-section" ]
        (Field.foldHead
            { open = ctx.setOpen
            , title = "Roll or Set"
            , msg = HpChangeSetToggle
            , trail = []
            }
            :: (if not ctx.setOpen then
                    []

                else
                    [ div [ class "cond-row" ]
                        [ Html.label [ for "manual-roll", class "cond-label" ] [ text "Roll:" ]
                        , input
                            [ id "manual-roll"
                            , class "cond-input cond-input--w12"
                            , type_ "text"
                            , placeholder "e.g. 2d6+3"
                            , value ui.manualRollText
                            , onInput HpChangeManualRollChanged
                            , Html.Events.on "keydown" (Util.Keyboard.enterKey HpChangeManualApplyTarget)
                            , Tooltips.attr Tooltips.hpRoll
                            ]
                            []
                        , if rolling then
                            button
                                [ class "icon-btn icon-btn--sm icon-btn--red"
                                , type_ "button"
                                , onClick HpChangeManualRollClear
                                , Tooltips.attr Tooltips.hpRollClear
                                , attribute "aria-label" "Clear the roll"
                                ]
                                [ text "×" ]

                          else
                            text ""
                        ]
                    , parseErrorHint ui.manualRollError
                    , div
                        [ class
                            (if rolling then
                                "cond-row cond-row--pools cond-row--muted"

                             else
                                "cond-row cond-row--pools"
                            )
                        ]
                        [ Html.label [ class "cond-label" ] [ text "or Set:" ]
                        , poolField rolling "" "manual-hp" "HP" ui.manualHpText CurrentHpField
                        , poolField rolling split "manual-max-hp" "Max HP" ui.manualMaxHpText MaxHpField
                        , poolField rolling split "manual-temp-hp" "Temp HP" ui.manualTempHpText TempHpField
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


{-| One pool field, standing aside while the Roll field holds a
formula.
-}
poolField : Bool -> String -> String -> String -> String -> HpField -> Html Msg
poolField rolling extraClass fieldId label current field =
    span [ class ("cond-pair " ++ extraClass) ]
        [ Html.label [ for fieldId, class "cond-label" ] [ text label ]
        , input
            [ id fieldId
            , class "cond-input cond-input--pool"
            , type_ "number"
            , Attr.min "0"
            , Attr.max "999"
            , value current
            , disabled rolling
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
    div [ class "cond-row" ]
        [ Html.label [ class "cond-label", for "hp-amount" ]
            [ text "HP:" ]
        , input
            [ id "hp-amount"
            , class "cond-input cond-input--narrow"
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


{-| When the amount reads as a dice formula and a selection is
in play, offer a fresh roll per creature instead of one shared
total; an integer amount hides it, since there is nothing to
reroll.
-}
freshRollOption : Int -> HpChangeUi -> Html Msg
freshRollOption selectedCount ui =
    if selectedCount > 0 && isFormula ui.amountText then
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
        ]
