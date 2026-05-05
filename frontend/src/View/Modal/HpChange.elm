module View.Modal.HpChange exposing (view)

{-| HP-change modal (Damage / Heal / Temp HP). Reuses the dice
modal's backdrop / panel shell — the chrome is the same, only the
body differs. Closes on backdrop click, ✕, or Cancel.
-}

import Dice
import Encounter exposing (Creature, Encounter)
import HpChange
import Html exposing (Html, button, div, input, li, span, text, ul)
import Html.Attributes as Attr exposing (attribute, checked, class, for, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( HpInputMode(..)
        , HpKind(..)
        , Msg(..)
        )
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi)
import Util.Keyboard
import View.Modal


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalHpChange ui) ->
            let
                target =
                    List.filter (\c -> c.name == ui.target) model.encounter.creatures
                        |> List.head

                verb =
                    case ui.kind of
                        DamageKind ->
                            "Damage"

                        HealKind ->
                            "Heal"

                        TempHpKind ->
                            "Temp HP"
            in
            View.Modal.view
                { close = HpChangeClose
                , noOp = NoOp
                , title = verb ++ " — " ++ ui.target
                , extraClass = "modal--hp-change"
                , body =
                    [ modeToggle ui
                    , amount ui
                    , options ui
                    , applyScope ui model.encounter
                    , case target of
                        Just c ->
                            preview ui c

                        Nothing ->
                            text ""
                    , footer
                    , log model.hpChangeLog
                    ]
                }

        _ ->
            text ""


modeToggle : HpChangeUi -> Html Msg
modeToggle ui =
    div [ class "hp-change__mode" ]
        [ modeRadio "Manual" (ui.mode == ManualMode) (HpChangeModeSet ManualMode)
        , modeRadio "Roll dice" (ui.mode == DiceMode) (HpChangeModeSet DiceMode)
        ]


modeRadio : String -> Bool -> Msg -> Html Msg
modeRadio label isOn msg =
    button
        [ class
            (if isOn then
                "hp-change__mode-btn hp-change__mode-btn--active"

             else
                "hp-change__mode-btn"
            )
        , onClick msg
        , attribute "aria-pressed"
            (if isOn then
                "true"

             else
                "false"
            )
        ]
        [ text label ]


amount : HpChangeUi -> Html Msg
amount ui =
    case ui.mode of
        ManualMode ->
            div [ class "hp-change__row" ]
                [ Html.label [ for "hp-amount" ] [ text "Amount" ]
                , input
                    [ id "hp-amount"
                    , class "hp-change__input"
                    , type_ "number"
                    , Attr.min "0"
                    , Attr.max "999"
                    , value ui.amountText
                    , onInput HpChangeAmountChanged
                    , Html.Events.on "keydown" (Util.Keyboard.enterKey HpChangeApply)
                    ]
                    []
                ]

        DiceMode ->
            div []
                [ div [ class "hp-change__row" ]
                    [ Html.label [ for "hp-expression" ] [ text "Expression" ]
                    , input
                        [ id "hp-expression"
                        , class "hp-change__input"
                        , type_ "text"
                        , placeholder "e.g. 2d6+3"
                        , value ui.expression
                        , onInput HpChangeExpressionChanged
                        , Html.Events.on "keydown" (Util.Keyboard.enterKey HpChangeApply)
                        ]
                        []
                    ]
                , case ui.parseError of
                    Just (Dice.ParseError raw) ->
                        div [ class "hp-change__error" ]
                            [ text ("Couldn't parse: " ++ raw) ]

                    Nothing ->
                        text ""
                ]


options : HpChangeUi -> Html Msg
options ui =
    case ui.kind of
        DamageKind ->
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
                ]

        _ ->
            text ""


{-| Multi-target scope checkbox. Hidden entirely when zero
creatures are selected — there's no useful "apply to all selected"
when there's no selection. When at least one is selected, renders
the toggle plus a count hint so the GM knows the blast radius.

Dice mode comes with an inline note explaining that all selected
creatures share the same rolled total (the 5e Fireball
single-roll-per-AOE convention).

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
            , if ui.applyToSelected && ui.mode == DiceMode then
                div [ class "hp-change__caption" ]
                    [ text "All selected creatures take the same rolled total (one roll, shared across the AOE)." ]

              else
                text ""
            ]


{-| Preview of the manual-mode arithmetic: shows what the change
would do to the target's HP if Apply were clicked right now. In
dice mode the result depends on the roll, so we show the expression
that will be rolled instead of a numeric prediction.
-}
preview : HpChangeUi -> Creature -> Html Msg
preview ui c =
    let
        before =
            hpBeforeText c
    in
    div [ class "hp-change__preview" ]
        [ div [ class "hp-change__preview-label" ] [ text "Preview" ]
        , div [ class "hp-change__preview-body" ]
            (case ui.mode of
                ManualMode ->
                    let
                        change =
                            buildPreviewChange ui ui.amount

                        after =
                            HpChange.apply change c
                    in
                    [ text before
                    , span [ class "hp-change__preview-arrow" ] [ text " → " ]
                    , text (hpAfterText after)
                    ]

                DiceMode ->
                    [ text before
                    , span [ class "hp-change__preview-arrow" ] [ text " → " ]
                    , span [ class "hp-change__preview-roll" ]
                        [ text
                            (if String.isEmpty (String.trim ui.expression) then
                                "(enter an expression)"

                             else
                                "roll " ++ String.trim ui.expression
                            )
                        ]
                    ]
            )
        ]


buildPreviewChange : HpChangeUi -> Int -> HpChange.Change
buildPreviewChange ui amount_ =
    case ui.kind of
        DamageKind ->
            HpChange.Damage { amount = amount_, ignoreTemp = ui.ignoreTemp }

        HealKind ->
            HpChange.Heal amount_

        TempHpKind ->
            HpChange.TempHp amount_


hpBeforeText : Creature -> String
hpBeforeText c =
    String.fromInt c.currentHp
        ++ "/"
        ++ String.fromInt c.maxHp
        ++ (if c.tempHp > 0 then
                " (+" ++ String.fromInt c.tempHp ++ " temp)"

            else
                ""
           )


hpAfterText : Creature -> String
hpAfterText c =
    String.fromInt c.currentHp
        ++ "/"
        ++ String.fromInt c.maxHp
        ++ (if c.tempHp > 0 then
                " (+" ++ String.fromInt c.tempHp ++ " temp)"

            else
                ""
           )


footer : Html Msg
footer =
    div [ class "hp-change__footer" ]
        [ button
            [ class "action-btn"
            , onClick HpChangeClose
            ]
            [ text "Cancel" ]
        , button
            [ class "action-btn action-btn--green"
            , onClick HpChangeApply
            ]
            [ text "Apply" ]
        ]


{-| Last-N HP-change log shown at the bottom of the modal. Includes
every kind (damage / heal / temp) so the GM can see recent table
context without flipping between the three modal verbs. Empty
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

        kindClass =
            case entry.kind of
                DamageKind ->
                    "hp-change__log-kind hp-change__log-kind--damage"

                HealKind ->
                    "hp-change__log-kind hp-change__log-kind--heal"

                TempHpKind ->
                    "hp-change__log-kind hp-change__log-kind--temp"

        beforeStr =
            hpSnapshot entry.beforeHp entry.beforeTemp

        afterStr =
            hpSnapshot entry.afterHp entry.afterTemp
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
                , Attr.title
                    ("Undo: revert " ++ entry.target ++ " to " ++ beforeStr)
                , attribute "aria-label"
                    ("Undo " ++ kindLabel ++ " on " ++ entry.target)
                ]
                [ text "↩" ]

          else
            text ""
        ]


{-| Render an HP+temp pair for the log: "27/59" or "27/59 +5" when
temp HP is positive. Reused for both before and after columns.
-}
hpSnapshot : Int -> Int -> String
hpSnapshot hp temp =
    if temp > 0 then
        String.fromInt hp ++ " +" ++ String.fromInt temp

    else
        String.fromInt hp
