module View.Inline.Replace exposing (view)

{-| Replace editor as a docked toolbar expansion: a compendium
search + picker list (the Quick Add row styling), the apply
scope, Apply, and the newest log row. The swap preserves each
replaced creature's queue position and initiative.
-}

import Compendium
import Html exposing (Html, button, div, em, h3, input, li, span, text, ul)
import Html.Attributes as Attr exposing (attribute, checked, class, disabled, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Replace exposing (ReplaceLogEntry, ReplaceUi)


view : CompendiumDb -> Int -> List ReplaceLogEntry -> ReplaceUi -> Html Msg
view db selectedCount log ui =
    div [ class "creature-card__inline" ]
        [ searchRow ui
        , pickerList db ui
        , applyScope selectedCount ui
        , div [ class "note-edit__buttons note-edit__buttons--start" ]
            [ button
                [ class "action-btn action-btn--green"
                , onClick ReplaceApply
                , disabled (ui.pickedId == Nothing)
                , attribute "aria-disabled"
                    (if ui.pickedId == Nothing then
                        "true"

                     else
                        "false"
                    )
                ]
                [ text "Apply" ]
            ]
        , latestLog log
        ]


searchRow : ReplaceUi -> Html Msg
searchRow ui =
    div [ class "cond-row" ]
        [ Html.label [] [ text "Replace with:" ]
        , input
            [ class "cond-input cond-input--search"
            , type_ "text"
            , value ui.searchText
            , placeholder "Search the compendium"
            , onInput ReplaceSearchChanged
            ]
            []
        ]


pickerList : CompendiumDb -> ReplaceUi -> Html Msg
pickerList db ui =
    case db of
        CompendiumDbLoaded loaded ->
            let
                creatures =
                    Compendium.search ui.searchText loaded
                        |> Compendium.sortByName
                        |> Compendium.toList
            in
            if List.isEmpty creatures then
                div [ class "cond-section__caption" ]
                    [ text "No matches." ]

            else
                ul [ class "quick-add__list quick-add__list--docked" ]
                    (List.map (row ui) creatures)

        CompendiumDbLoading ->
            div [ class "cond-section__caption" ] [ text "Loading the compendium…" ]

        CompendiumDbFailed _ ->
            div [ class "cond-section__caption" ] [ text "Couldn't load the compendium." ]


row : ReplaceUi -> Compendium.Creature -> Html Msg
row ui c =
    li
        [ class
            (if ui.pickedId == Just c.id then
                "quick-add__row quick-add__row--picked"

             else
                "quick-add__row"
            )
        , onClick (ReplacePick c.id)
        , attribute "role" "option"
        , attribute "aria-selected"
            (if ui.pickedId == Just c.id then
                "true"

             else
                "false"
            )
        ]
        [ span [ class "quick-add__name" ] [ text c.name ]
        , span [ class "quick-add__cr" ] [ text (crLabel c.challengeRating) ]
        ]


{-| Render the CR string with a "CR" prefix so a row reads
"Goblin CR 1/4"; empty CR falls back to a muted dash.
-}
crLabel : String -> String
crLabel raw =
    if String.isEmpty (String.trim raw) then
        "—"

    else
        "CR " ++ String.trim raw


applyScope : Int -> ReplaceUi -> Html Msg
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
                        , onClick ReplaceApplyToSelectedToggle
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


latestLog : List ReplaceLogEntry -> Html Msg
latestLog entries =
    case entries of
        newest :: _ ->
            ul [ class "hp-change__log-list hp-change__log-list--latest" ]
                [ li [ class "hp-change__log-entry hp-change__log-entry--wide" ]
                    [ span [ class "hp-change__log-kind hp-change__log-kind--cond" ]
                        [ text "Replace" ]
                    , span [ class "hp-change__log-target" ]
                        [ text (String.join ", " newest.olds) ]
                    , span [ class "hp-change__log-trans" ]
                        [ text ("→ " ++ String.join ", " newest.news) ]
                    ]
                ]

        [] ->
            text ""
