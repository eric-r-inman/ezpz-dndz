module View.PhaseToggle exposing (view)

{-| Two-radio "begin / end" toggle used by the condition modal
(`untilPhase` and `countdownPhase` sub-controls) and the timer
modal (`phase`). Shared widget so both sites render identically.
-}

import Encounter exposing (TurnPhase(..))
import Html exposing (Html, input, span, text)
import Html.Attributes exposing (checked, class, type_)
import Html.Events exposing (onCheck)


{-| `groupName` becomes the radio group `name` attribute so multiple
toggles on the same modal don't share state. `current` drives both
the visual highlight and the radio's `checked` attribute. `toMsg`
fires when either radio is picked, by pointer or by the arrow keys.
The radios are hidden from sight only, so Tab and a screen reader
still reach them.
-}
view : String -> TurnPhase -> (TurnPhase -> msg) -> Html msg
view groupName current toMsg =
    span [ class "cond-phase-toggle" ]
        [ Html.label
            [ class
                (if current == AtBegin then
                    "cond-phase cond-phase--on"

                 else
                    "cond-phase"
                )
            ]
            [ input
                [ type_ "radio"
                , class "visually-hidden"
                , Html.Attributes.name groupName
                , checked (current == AtBegin)
                , onCheck (always (toMsg AtBegin))
                ]
                []
            , text "beginning"
            ]
        , Html.label
            [ class
                (if current == AtEnd then
                    "cond-phase cond-phase--on"

                 else
                    "cond-phase"
                )
            ]
            [ input
                [ type_ "radio"
                , class "visually-hidden"
                , Html.Attributes.name groupName
                , checked (current == AtEnd)
                , onCheck (always (toMsg AtEnd))
                ]
                []
            , text "end"
            ]
        ]
