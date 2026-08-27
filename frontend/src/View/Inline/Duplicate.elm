module View.Inline.Duplicate exposing (view)

{-| Duplicate editor as a docked toolbar expansion: flavor
radios, apply scope, Apply, and the newest log row.
-}

import Html exposing (Html, button, div, em, h3, input, li, span, text, ul)
import Html.Attributes as Attr exposing (attribute, checked, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (DuplicateMode(..), Msg(..))
import Ui.Duplicate exposing (DuplicateLogEntry, DuplicateUi)


view : Int -> List DuplicateLogEntry -> DuplicateUi -> Html Msg
view selectedCount log ui =
    div [ class "creature-card__inline" ]
        [ modeSection ui
        , applyScope selectedCount ui
        , div [ class "note-edit__buttons note-edit__buttons--start" ]
            [ button
                [ class "action-btn action-btn--green"
                , onClick DuplicateApply
                ]
                [ text "Apply" ]
            ]
        , latestLog log
        ]


modeSection : DuplicateUi -> Html Msg
modeSection ui =
    div [ class "cond-section" ]
        [ div [ class "cond-row" ]
            [ Html.label [] [ text "Copy as:" ]
            , modeRadio ui DupExact "Exact"
            , modeRadio ui DupFresh "Fresh"
            , modeRadio ui DupMinionHalf "Minion (½ max hp)"
            , modeRadio ui DupMinionOne "Minion (1 hp)"
            , modeRadio ui DupPudding "Pudding"
            ]
        , div [ class "cond-section__caption" ]
            [ text (modeCaption ui.mode) ]
        ]


modeRadio : DuplicateUi -> DuplicateMode -> String -> Html Msg
modeRadio ui mode label =
    Html.label
        [ class
            (if ui.mode == mode then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        ]
        [ input
            [ type_ "radio"
            , Attr.name "duplicate-mode"
            , checked (ui.mode == mode)
            , onClick (DuplicateModeSet mode)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


modeCaption : DuplicateMode -> String
modeCaption mode =
    case mode of
        DupExact ->
            "Clones the creature with all current state (HP, conditions, notes)."

        DupFresh ->
            "Re-instances from the compendium with fresh, unmodified state."

        DupMinionHalf ->
            "Fresh copy at half the normal hit point maximum."

        DupMinionOne ->
            "Fresh copy with 1 max hit point."

        DupPudding ->
            "Splits into two half-HP copies and removes the original."


applyScope : Int -> DuplicateUi -> Html Msg
applyScope selectedCount ui =
    if selectedCount == 0 then
        text ""

    else
        div [ class "cond-section" ]
            [ h3 [ class "cond-section__heading" ]
                [ Html.label []
                    [ input
                        [ type_ "checkbox"
                        , checked ui.applyToSelected
                        , onClick DuplicateApplyToSelectedToggle
                        ]
                        []
                    , text " Apply "
                    , em [] [ text "only" ]
                    , text
                        (" to selected creatures ("
                            ++ String.fromInt selectedCount
                            ++ ")"
                        )
                    ]
                ]
            ]


latestLog : List DuplicateLogEntry -> Html Msg
latestLog entries =
    case entries of
        newest :: _ ->
            ul [ class "hp-change__log-list hp-change__log-list--latest" ]
                [ li [ class "hp-change__log-entry hp-change__log-entry--wide" ]
                    [ span [ class "hp-change__log-kind hp-change__log-kind--cond" ]
                        [ text newest.modeLabel ]
                    , span [ class "hp-change__log-target" ]
                        [ text (String.join ", " newest.sources) ]
                    , span [ class "hp-change__log-trans" ]
                        [ text ("→ " ++ String.join ", " newest.created) ]
                    ]
                ]

        [] ->
            text ""
