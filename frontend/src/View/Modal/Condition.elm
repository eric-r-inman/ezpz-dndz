module View.Modal.Condition exposing (view)

{-| Condition / effect modal. Sections, top to bottom:
standard-condition radios, custom name input, note input, duration
choice (Manual / Until turn / Countdown) with the relevant
sub-controls, optional save-to-end block, multi-target apply scope,
and the action footer (Apply / Cancel / Delete-when-editing).
-}

import Encounter exposing (Encounter)
import Html exposing (Html, button, div, h3, input, span, text)
import Html.Attributes as Attr exposing (attribute, checked, class, disabled, for, id, maxlength, placeholder, title, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( DurationKind(..)
        , Msg(..)
        )
import Ui.Condition exposing (ConditionUi, SaveToEndUi)
import Update.Condition
import View.Modal
import View.PhaseToggle


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalCondition ui) ->
            let
                modalTitle =
                    (if ui.editingId == Nothing then
                        "Add Condition — "

                     else
                        "Edit Condition — "
                    )
                        ++ ui.target
            in
            View.Modal.view
                { close = ConditionClose
                , noOp = NoOp
                , title = modalTitle
                , extraClass = "modal--condition"
                , body =
                    [ standardSection ui
                    , customSection ui
                    , noteSection ui
                    , durationSection ui model
                    , saveSection ui
                    , applyScope ui model.encounter
                    , footer ui
                    ]
                }

        _ ->
            text ""


{-| Multi-target scope checkbox for the condition modal. Same
shape as the HP-change apply scope: hidden when no creatures are
selected, otherwise a toggle that splatters a fresh copy of the
new condition onto every selected creature (each gets its own id).

Hidden entirely when editing an existing condition — you're
modifying one specific row, not creating new ones in bulk.

-}
applyScope : ConditionUi -> Encounter -> Html Msg
applyScope ui enc =
    let
        selectedCount =
            List.length (List.filter .selected enc.creatures)
    in
    if ui.editingId /= Nothing || selectedCount == 0 then
        text ""

    else
        div [ class "cond-section" ]
            [ Html.label [ class "hp-change__checkbox" ]
                [ input
                    [ type_ "checkbox"
                    , checked ui.applyToSelected
                    , onClick ConditionApplyToSelectedToggle
                    ]
                    []
                , text
                    (" Apply to all selected creatures ("
                        ++ String.fromInt selectedCount
                        ++ ")"
                    )
                ]
            , div [ class "cond-section__caption" ]
                [ text "Each selected creature gets its own copy of the condition (separate ids, independent durations)." ]
            ]


standardSection : ConditionUi -> Html Msg
standardSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text "Standard 5e Conditions" ]
        , div [ class "cond-radio-grid" ]
            (List.map (standardRadio ui) Encounter.standardConditions)
        ]


standardRadio : ConditionUi -> String -> Html Msg
standardRadio ui label =
    let
        isSelected =
            ui.name == label
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
            , Attr.name "condition-radio"
            , checked isSelected
            , onClick (ConditionPickStandard label)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


customSection : ConditionUi -> Html Msg
customSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text "Custom Name" ]
        , input
            [ class "cond-input"
            , type_ "text"
            , value ui.customName
            , placeholder "e.g. Bardic Inspiration, On fire"
            , onInput ConditionCustomNameChanged
            ]
            []
        , div [ class "cond-section__caption" ]
            [ text "Typing here overrides the radio selection above." ]
        ]


noteSection : ConditionUi -> Html Msg
noteSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text ("Note (max " ++ String.fromInt Update.Condition.maxConditionNoteLength ++ " chars)") ]
        , input
            [ class "cond-input"
            , type_ "text"
            , value ui.note
            , maxlength Update.Condition.maxConditionNoteLength
            , placeholder "e.g. from Lyra"
            , onInput ConditionNoteChanged
            ]
            []
        ]


durationSection : ConditionUi -> Model -> Html Msg
durationSection ui model =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text "Duration" ]
        , div [ class "cond-radio-row" ]
            [ durationKindRadio ui DurKindManual "Manual"
            , durationKindRadio ui DurKindUntilTurn "Until turn"
            , durationKindRadio ui DurKindCountdown "Countdown"
            ]
        , case ui.durationKind of
            DurKindManual ->
                div [ class "cond-section__caption" ]
                    [ text "Stays until the GM clicks the chip's × to remove." ]

            DurKindUntilTurn ->
                durationUntilSubsection ui model

            DurKindCountdown ->
                durationCountdownSubsection ui
        ]


durationKindRadio : ConditionUi -> DurationKind -> String -> Html Msg
durationKindRadio ui kind label =
    Html.label
        [ class
            (if ui.durationKind == kind then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        ]
        [ input
            [ type_ "radio"
            , Attr.name "duration-kind"
            , checked (ui.durationKind == kind)
            , onClick (ConditionDurationKindSet kind)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


durationUntilSubsection : ConditionUi -> Model -> Html Msg
durationUntilSubsection ui model =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [] [ text "At" ]
            , View.PhaseToggle.view "until-phase" ui.untilPhase ConditionUntilPhaseSet
            , Html.label [] [ text "of" ]
            , Html.select
                [ class "cond-select"
                , onInput ConditionUntilCreatureChanged
                ]
                (List.map
                    (\c ->
                        Html.option
                            [ value c.name
                            , Attr.selected (c.name == ui.untilCreature)
                            ]
                            [ text c.name ]
                    )
                    model.encounter.creatures
                )
            , Html.label [] [ text "'s" ]
            , turnTargetToggle ui model
            , Html.label [] [ text "turn" ]
            ]
        ]


{-| Two-button current / next radio toggle inserted between the
reference creature and the word "turn" in the duration row.

The "current" button is disabled when `Update.Condition.currentTurnInvalid`
is true — i.e. begin-of-turn paired with the currently-active
creature, since their current begin-of-turn already fired.

-}
turnTargetToggle : ConditionUi -> Model -> Html Msg
turnTargetToggle ui model =
    let
        currentDisabled =
            Update.Condition.currentTurnInvalid model ui
    in
    span [ class "cond-phase-toggle" ]
        [ Html.label
            [ class
                (String.join " "
                    (List.filterMap identity
                        [ Just "cond-phase"
                        , if ui.untilTarget == Encounter.OnCurrentTurn then
                            Just "cond-phase--on"

                          else
                            Nothing
                        , if currentDisabled then
                            Just "cond-phase--disabled"

                          else
                            Nothing
                        ]
                    )
                )
            , title
                (if currentDisabled then
                    "The current begin-of-turn already fired for the active creature — pick 'next' instead"

                 else
                    "Expire on the first matching hook fire"
                )
            ]
            [ input
                [ type_ "radio"
                , Attr.name "until-target"
                , checked (ui.untilTarget == Encounter.OnCurrentTurn)
                , disabled currentDisabled
                , onClick (ConditionUntilTargetSet Encounter.OnCurrentTurn)
                ]
                []
            , text "current"
            ]
        , Html.label
            [ class
                (if ui.untilTarget == Encounter.OnNextTurn then
                    "cond-phase cond-phase--on"

                 else
                    "cond-phase"
                )
            , title "Skip the first matching hook fire and expire on the second"
            ]
            [ input
                [ type_ "radio"
                , Attr.name "until-target"
                , checked (ui.untilTarget == Encounter.OnNextTurn)
                , onClick (ConditionUntilTargetSet Encounter.OnNextTurn)
                ]
                []
            , text "next"
            ]
        ]


durationCountdownSubsection : ConditionUi -> Html Msg
durationCountdownSubsection ui =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [ for "cond-countdown-turns" ]
                [ text "Lasts" ]
            , input
                [ id "cond-countdown-turns"
                , class "cond-input cond-input--narrow"
                , type_ "number"
                , Attr.min "1"
                , Attr.max "99"
                , value ui.countdownTurnsText
                , onInput ConditionCountdownTurnsChanged
                ]
                []
            , Html.label [] [ text "turns, ticking at" ]
            , View.PhaseToggle.view "countdown-phase" ui.countdownPhase ConditionCountdownPhaseSet
            , Html.label [] [ text "of the bearer's turn" ]
            ]
        , div [ class "cond-section__caption" ]
            [ text
                ("If you set 'end' while it's already this creature's turn, "
                    ++ "the countdown skips this end-of-turn so they get a "
                    ++ "full first turn under the effect."
                )
            ]
        ]


saveSection : ConditionUi -> Html Msg
saveSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ Html.label []
                [ input
                    [ type_ "checkbox"
                    , checked (ui.saveToEnd /= Nothing)
                    , onClick ConditionSaveToggle
                    ]
                    []
                , text " Save-to-end"
                ]
            ]
        , case ui.saveToEnd of
            Nothing ->
                div [ class "cond-section__caption" ]
                    [ text "Optional: condition can end on a successful saving throw." ]

            Just s ->
                saveSubsection s
        ]


saveSubsection : SaveToEndUi -> Html Msg
saveSubsection s =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [ for "cond-save-ability" ] [ text "Ability" ]
            , Html.select
                [ id "cond-save-ability"
                , class "cond-select"
                , onInput ConditionSaveAbilityChanged
                ]
                (List.map
                    (\a ->
                        Html.option
                            [ value a
                            , Attr.selected (a == s.ability)
                            ]
                            [ text a ]
                    )
                    [ "STR", "DEX", "CON", "INT", "WIS", "CHA" ]
                )
            , Html.label [ for "cond-save-dc" ] [ text "DC" ]
            , input
                [ id "cond-save-dc"
                , class "cond-input cond-input--narrow"
                , type_ "number"
                , Attr.min "1"
                , Attr.max "40"
                , value s.dcText
                , onInput ConditionSaveDcChanged
                ]
                []
            , Html.label [ for "cond-save-bonus" ] [ text "Bonus" ]
            , input
                [ id "cond-save-bonus"
                , class "cond-input cond-input--narrow"
                , type_ "number"
                , Attr.min "-10"
                , Attr.max "20"
                , value s.bonusText
                , onInput ConditionSaveBonusChanged
                ]
                []
            ]
        , div [ class "cond-radio-stack" ]
            [ autoRollRadio s
                Encounter.AutoRollManual
                "Manual (no auto-roll — GM clicks 🎲 on the chip)"
            , autoRollRadio s
                Encounter.AutoRollAtBegin
                "Auto-roll at the bearer's beginning-of-turn"
            , autoRollRadio s
                Encounter.AutoRollAtEnd
                "Auto-roll at the bearer's end-of-turn"
            ]
        , div [ class "cond-section__caption" ]
            [ text (autoRollCaption s.autoRoll) ]
        ]


{-| One radio button in the auto-roll mode group. Shares the
.cond-radio chrome with the other radio groups in the modal.
-}
autoRollRadio : SaveToEndUi -> Encounter.AutoRollMode -> String -> Html Msg
autoRollRadio s mode label =
    let
        isSelected =
            s.autoRoll == mode
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
            , Attr.name "cond-save-autoroll"
            , checked isSelected
            , onClick (ConditionSaveAutoRollSet mode)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


{-| Caption text under the auto-roll radio group describing what
will actually happen in play. Updates live with the selection so
the GM can see the consequence without clicking submit.
-}
autoRollCaption : Encounter.AutoRollMode -> String
autoRollCaption mode =
    case mode of
        Encounter.AutoRollManual ->
            "The 🎲 button on the chip rolls manually — a reminder, not auto-applied."

        Encounter.AutoRollAtBegin ->
            "Save fires at the start of the bearer's turn; success removes the condition."

        Encounter.AutoRollAtEnd ->
            "Save fires at the end of the bearer's turn; success removes the condition."


footer : ConditionUi -> Html Msg
footer ui =
    let
        canSubmit =
            not (String.isEmpty (String.trim ui.name))

        applyLabel =
            if ui.editingId == Nothing then
                "Apply"

            else
                "Save Changes"
    in
    div [ class "cond-footer" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick ConditionSubmit
            , disabled (not canSubmit)
            , attribute "aria-disabled"
                (if canSubmit then
                    "false"

                 else
                    "true"
                )
            , title
                (if canSubmit then
                    applyLabel

                 else
                    "Pick a condition or type a custom name first"
                )
            ]
            [ text applyLabel ]
        , case ui.editingId of
            Just _ ->
                button
                    [ class "action-btn action-btn--damage"
                    , onClick ConditionDelete
                    , title "Remove this condition"
                    ]
                    [ text "Delete" ]

            Nothing ->
                text ""
        , button
            [ class "action-btn"
            , onClick ConditionClose
            ]
            [ text "Cancel" ]
        ]
