module View.Modal.HpChange exposing (view)

{-| Manage HP modal — one entry point handling Damage, Heal,
Temp HP, and +Max HP.

Single smart amount input: type a plain integer (`8`) to
apply that value directly, or a dice formula (`2d6+3`) to
roll and apply the total. Parse errors surface inline
underneath the input. No mode toggle — the input decides
which path to take when the GM clicks one of the four
verbs.

The `Ignore temporary HP` checkbox stays visible for all
verbs (it's only consulted when Damage is clicked) so the
GM doesn't have to swap modes just to pre-set the flag.

-}

import Dice
import Encounter exposing (Encounter)
import Html exposing (Html, button, div, input, li, span, text, ul)
import Html.Attributes as Attr exposing (attribute, checked, class, for, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( HpKind(..)
        , Msg(..)
        )
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi)
import Util.Keyboard
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalHpChange ui) ->
            View.Modal.view
                { close = HpChangeClose
                , noOp = NoOp
                , title = "Manage HP — " ++ ui.target
                , extraClass = "modal--hp-change"
                , chrome = model.modalChrome
                , body =
                    [ amount ui
                    , parseErrorHint ui
                    , ignoreTempToggle ui
                    , applyScope ui model.encounter
                    , actionButtons
                    , log model.hpChangeLog
                    ]
                }

        _ ->
            text ""


{-| Single amount input. Enter-key commits as `DamageKind`
because the modal has four commit paths; Enter isn't safely
overloadable across all of them. GMs who want Heal / Temp HP
/ +Max HP click the corresponding footer button. Placeholder
hint spells out both accepted formats so first-time users
don't have to guess.
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
            , onInput HpChangeAmountChanged
            , Html.Events.on "keydown" (Util.Keyboard.enterKey (HpChangeApplyAs DamageKind))
            ]
            []
        , div [ class "hp-change__caption" ]
            [ text "Enter a number, or a dice formula to roll." ]
        ]


{-| Inline parse-error hint. Only rendered when the amount
input isn't parseable as either an integer or a dice
expression — matches the previous dice-mode error banner but
in the single-input form.
-}
parseErrorHint : HpChangeUi -> Html Msg
parseErrorHint ui =
    case ui.parseError of
        Just (Dice.ParseError raw) ->
            div [ class "hp-change__error" ]
                [ text ("Couldn't parse: " ++ raw) ]

        Nothing ->
            text ""


{-| Ignore-temp-HP toggle. Always visible — GMs pre-checking
this before clicking Damage was the whole reason for hoisting
it above the action buttons. A caption spells out that it
only affects the Damage path, so the checkbox doesn't feel
like a footgun when the GM ends up clicking Heal or +Max HP.
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
        , div [ class "hp-change__caption" ]
            [ text "(applies to Damage only)" ]
        ]


{-| Multi-target scope checkbox. Hidden entirely when zero
creatures are selected — there's no useful "apply to all selected"
when there's no selection. When at least one is selected, renders
the toggle plus a count hint so the GM knows the blast radius.
-}
applyScope : HpChangeUi -> Encounter -> Html Msg
applyScope ui enc =
    let
        selectedCount =
            List.length (List.filter .selected enc.creatures)
    in
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
                [ text "Rolled amounts apply the same total to every selected creature (5e AoE convention)." ]
            ]


{-| Four action buttons — each commits the current amount
using that verb, then closes. Each verb is colour-coded to
match the existing damage / heal / temp affordances.
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


{-| Last-N HP-change log shown at the bottom of the modal. Includes
every kind (damage / heal / temp / +max) so the GM can see recent
table context without flipping between the modal verbs. Empty
state shows a small "No HP changes yet" line so the section
doesn't collapse to nothing on first open.
-}
log : List HpChangeEntry -> Html Msg
log entries =
    div [ class "hp-change__log" ]
        [ div [ class "hp-change__log-title" ]
            [ text ("Recent HP changes (" ++ String.fromInt (List.length entries) ++ ")") ]
        , if List.isEmpty entries then
            div [ class "hp-change__log-empty" ]
                [ text "No HP changes yet." ]

          else
            ul [ class "hp-change__log-list" ]
                (List.indexedMap logEntry entries)
        ]


{-| Render one log row. The newest entry (`index == 0`) carries
an inline undo button so the GM can revert the latest change in
one click; older rows render without it so a misclick can't
silently rewrite the middle of the history.
-}
logEntry : Int -> HpChangeEntry -> Html Msg
logEntry index entry =
    let
        kindLabel =
            case entry.kind of
                DamageKind ->
                    "Damage"

                HealKind ->
                    "Heal"

                TempHpKind ->
                    "Temp HP"

                MaxHpKind ->
                    "+Max HP"

        kindClass =
            case entry.kind of
                DamageKind ->
                    "hp-change__log-kind hp-change__log-kind--damage"

                HealKind ->
                    "hp-change__log-kind hp-change__log-kind--heal"

                TempHpKind ->
                    "hp-change__log-kind hp-change__log-kind--temp"

                MaxHpKind ->
                    "hp-change__log-kind hp-change__log-kind--max"

        beforeStr =
            hpSnapshot entry.beforeHp entry.beforeTemp entry.beforeMax

        afterStr =
            hpSnapshot entry.afterHp entry.afterTemp entry.afterMax
    in
    li [ class "hp-change__log-entry" ]
        [ span [ class kindClass ] [ text kindLabel ]
        , span [ class "hp-change__log-target" ] [ text entry.target ]
        , span [ class "hp-change__log-amount" ]
            [ text (String.fromInt entry.amount) ]
        , span [ class "hp-change__log-trans" ]
            [ text (beforeStr ++ " → " ++ afterStr) ]
        , if index == 0 then
            button
                [ class "icon-btn icon-btn--sm hp-change__log-undo"
                , onClick HpChangeUndoLatest
                , Tooltips.attr
                    ("Undo: revert " ++ entry.target ++ " to " ++ beforeStr)
                , attribute "aria-label"
                    ("Undo " ++ kindLabel ++ " on " ++ entry.target)
                ]
                [ text "↩" ]

          else
            text ""
        ]


{-| Render an HP+temp[+max] slug: "27/59" or "27/59 +5" when temp
HP is positive. Used for both before and after columns; the
maxHp is included implicitly via the "current/max" pair, so a
+Max HP row's before → after shift is legible without a
separate max field.
-}
hpSnapshot : Int -> Int -> Int -> String
hpSnapshot hp temp maxHp =
    let
        stem =
            String.fromInt hp ++ "/" ++ String.fromInt maxHp
    in
    if temp > 0 then
        stem ++ " +" ++ String.fromInt temp

    else
        stem
