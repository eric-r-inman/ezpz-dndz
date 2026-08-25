module View.Inline.HpChange exposing (view)

{-| Manage HP as an inline card expansion — one surface handling
Damage, Heal, Temp HP, and +Max HP without covering the queue.

Single smart amount input: type a plain integer (`8`) to apply
that value directly, or a dice formula (`2d6+3`) to roll and
apply the total. Parse errors surface inline underneath the
input. No mode toggle — the input decides which path to take
when the GM clicks one of the four verbs.

Only the newest log entry renders here (with its undo button);
the full list lives in the dice roller via `View.HpLog`.

-}

import Dice
import Html exposing (Html, button, div, input, text)
import Html.Attributes exposing (attribute, autofocus, checked, class, for, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg exposing (HpKind(..), Msg(..))
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi)
import Util.Keyboard
import View.HpLog


view : Int -> List HpChangeEntry -> HpChangeUi -> Html Msg
view selectedCount log ui =
    div [ class "creature-card__inline" ]
        [ header ui
        , amount ui
        , parseErrorHint ui
        , ignoreTempToggle ui
        , applyScope selectedCount ui
        , actionButtons
        , View.HpLog.latest log
        ]


{-| Expansion header: a small title plus the collapse button.
The title repeats the target name so the expansion still reads
correctly if the GM has scrolled the card's name row out of
view.
-}
header : HpChangeUi -> Html Msg
header ui =
    div [ class "creature-card__inline-header" ]
        [ div [ class "creature-card__inline-title" ]
            [ text ("Manage HP — " ++ ui.target) ]
        , button
            [ class "icon-btn icon-btn--sm creature-card__inline-close"
            , onClick HpChangeClose
            , attribute "aria-label" "Close Manage HP"
            ]
            [ text "×" ]
        ]


{-| Single amount input. Enter-key commits as `DamageKind`
because the expansion has four commit paths; Enter isn't safely
overloadable across all of them. GMs who want Heal / Temp HP
/ +Max HP click the corresponding button.
-}
amount : HpChangeUi -> Html Msg
amount ui =
    div [ class "hp-change__row" ]
        [ Html.label [ for "hp-amount" ] [ text "Amount" ]
        , input
            [ id "hp-amount"
            , class "hp-change__input"
            , type_ "text"
            , placeholder "12 or 2d6+3"
            , value ui.amountText
            , autofocus True
            , onInput HpChangeAmountChanged
            , Html.Events.on "keydown" (Util.Keyboard.enterKey (HpChangeApplyAs DamageKind))
            ]
            []
        , div [ class "hp-change__caption" ]
            [ text "Enter a number, or a dice formula to roll." ]
        ]


parseErrorHint : HpChangeUi -> Html Msg
parseErrorHint ui =
    case ui.parseError of
        Just (Dice.ParseError raw) ->
            div [ class "hp-change__error" ]
                [ text ("Couldn't parse: " ++ raw) ]

        Nothing ->
            text ""


{-| Ignore-temp-HP toggle. Always visible so the GM can pre-set
the flag before clicking Damage; the caption spells out that it
only affects the Damage path.
-}
ignoreTempToggle : HpChangeUi -> Html Msg
ignoreTempToggle ui =
    div [ class "hp-change__row" ]
        [ Html.label [ class "hp-change__checkbox" ]
            [ input
                [ type_ "checkbox"
                , checked ui.ignoreTemp
                , onClick HpChangeIgnoreTempToggle
                ]
                []
            , text " Ignore temporary HP"
            ]
        , Html.span [ class "hp-change__caption hp-change__caption--inline" ]
            [ text "(applies to Damage only)" ]
        ]


{-| Multi-target scope checkbox. Hidden entirely when zero
creatures are selected — there's no useful "apply to all
selected" when there's no selection.
-}
applyScope : Int -> HpChangeUi -> Html Msg
applyScope selectedCount ui =
    if selectedCount == 0 then
        text ""

    else
        div [ class "hp-change__row" ]
            [ Html.label [ class "hp-change__checkbox" ]
                [ input
                    [ type_ "checkbox"
                    , checked ui.applyToSelected
                    , onClick HpChangeApplyToSelectedToggle
                    ]
                    []
                , text
                    (" Apply to all selected creatures ("
                        ++ String.fromInt selectedCount
                        ++ ")"
                    )
                ]
            , div [ class "hp-change__caption" ]
                [ text "Rolled amounts apply the same total to every selected creature." ]
            ]


{-| Four action buttons — each commits the current amount using
that verb, then collapses the expansion. Each verb is
colour-coded to match the existing damage / heal / temp
affordances.
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
            [ text "Temp HP" ]
        , button
            [ class "action-btn action-btn--max"
            , onClick (HpChangeApplyAs MaxHpKind)
            ]
            [ text "Max HP" ]
        ]
