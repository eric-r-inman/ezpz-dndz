module View.Inline.DurationPicker exposing (view)

{-| The Condition editor's duration picker, drawn for a value the
Save Chain editor holds as an `EffectDuration`: the same chips,
the same sub-rows, and one Msg shape for every control so the
effect and immunity pickers differ only in where their edits go.

@docs view

-}

import Encounter
import Encounter.SaveChain exposing (EffectDuration(..), TurnRef(..))
import Html exposing (Html, div, input, span, text)
import Html.Attributes as Attr exposing (checked, class, for, id, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg exposing (DurationEdit(..), DurationKind(..), Msg)
import Ui.DurationEdit as DurationEdit
import View.PhaseToggle


{-| `groupName` keeps this picker's radios apart from every other
picker's; `creatureNames` fills the "until" select behind the two
role entries.
-}
type alias Config =
    { groupName : String
    , creatureNames : List String
    , value : EffectDuration
    , toMsg : DurationEdit -> Msg
    }


view : Config -> Html Msg
view cfg =
    div [ class "cond-duration" ]
        [ div [ class "cond-row" ]
            [ Html.label [ class "cond-label" ] [ text "Duration:" ]
            , kindChip cfg DurKindManual "Manual"
            , kindChip cfg DurKindUntilTurn "Next turn"
            , kindChip cfg DurKindThisTurn "This turn"
            , kindChip cfg DurKindCountdown "Countdown"
            , radioChip cfg.groupName
                (DurationEdit.isOneMinute cfg.value)
                (cfg.toMsg DurationOneMinutePicked)
                "1 Minute"
            ]
        , subsection cfg
        ]


{-| The Countdown chip yields its highlight to 1 Minute, which is
a countdown underneath.
-}
kindChip : Config -> DurationKind -> String -> Html Msg
kindChip cfg kind label =
    radioChip cfg.groupName
        (DurationEdit.kindOf cfg.value == kind && not (DurationEdit.isOneMinute cfg.value))
        (cfg.toMsg (DurationKindPicked kind))
        label


radioChip : String -> Bool -> Msg -> String -> Html Msg
radioChip groupName isSelected msg label =
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
            , Attr.name groupName
            , checked isSelected
            , onClick msg
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


subsection : Config -> Html Msg
subsection cfg =
    case cfg.value of
        LastsUntilRemoved ->
            text ""

        LastsOneMinute ->
            div [ class "cond-section__caption" ]
                [ text "Expires at the end of the bearer's 10th turn." ]

        LastsThisTurn ->
            div [ class "cond-section__caption" ]
                [ text "Expires at the end of the bearer's current turn." ]

        LastsUntilTurn phase ref ->
            div [ class "cond-subsection" ]
                [ div [ class "cond-row" ]
                    [ Html.label [ class "cond-label" ] [ text "At" ]
                    , View.PhaseToggle.view (cfg.groupName ++ "-until-phase")
                        phase
                        (DurationUntilPhasePicked >> cfg.toMsg)
                    , Html.label [ class "cond-label" ] [ text "of" ]
                    , Html.select
                        [ class "cond-select"
                        , onInput (DurationUntilRefPicked >> cfg.toMsg)
                        ]
                        (refOptions cfg.creatureNames ref)
                    , Html.label [ class "cond-label" ] [ text "'s next turn" ]
                    ]
                ]

        LastsForTurns phase turns ->
            let
                turnsId =
                    cfg.groupName ++ "-turns"
            in
            div [ class "cond-subsection" ]
                [ div [ class "cond-row" ]
                    [ Html.label [ for turnsId, class "cond-label" ] [ text "Lasts" ]
                    , input
                        [ id turnsId
                        , class "cond-input cond-input--narrow"
                        , type_ "number"
                        , Attr.min "1"
                        , Attr.max "99"
                        , value (String.fromInt turns)
                        , onInput (DurationTurnsTyped >> cfg.toMsg)
                        ]
                        []
                    , Html.label [ class "cond-label" ] [ text "turns, ticking at" ]
                    , View.PhaseToggle.view (cfg.groupName ++ "-countdown-phase")
                        phase
                        (DurationCountdownPhasePicked >> cfg.toMsg)
                    , Html.label [ class "cond-label" ] [ text "of the bearer's turn" ]
                    ]
                , div [ class "cond-section__caption" ]
                    [ Html.em [] [ text "Countdown timer begins when active creature's turn ends." ] ]
                ]


refOptions : List String -> TurnRef -> List (Html Msg)
refOptions names current =
    let
        option ref label =
            Html.option
                [ value (DurationEdit.turnRefValue ref)
                , Attr.selected (ref == current)
                ]
                [ text label ]
    in
    option TurnOfBearer "the target"
        :: option TurnOfActive "the active creature"
        :: List.map (\name -> option (TurnOf name) name) names
