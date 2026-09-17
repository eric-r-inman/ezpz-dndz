module View.Inline.Replace exposing (view)

{-| Replace editor body. A swap preserves each replaced
creature's queue position and initiative.
-}

import Compendium
import Html exposing (Html, div, input, li, span, text, ul)
import Html.Attributes as Attr exposing (attribute, class, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
import Msg exposing (Msg(..))
import Set exposing (Set)
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Replace exposing (ReplaceLogEntry, ReplaceUi)
import View.Inline.ApplyButton as ApplyButton
import View.Inline.Field as Field
import View.LogRow


view : CompendiumDb -> Int -> { open : Bool, expanded : Set String } -> List ReplaceLogEntry -> ReplaceUi -> Html Msg
view db selectedCount logOpts log ui =
    div [ class "editor-body" ]
        [ searchRow ui
        , pickerList db ui
        , ApplyButton.row "Apply to:"
            [ ApplyButton.view
                { enabled = ui.pickedId /= Nothing
                , cls = "action-btn action-btn--green"
                , msg = ReplaceApply
                , tip =
                    if ui.pickedId == Nothing then
                        "Pick a replacement creature first"

                    else
                        "Swap in the picked creature for the target"
                , label = "Target"
                }
            , ApplyButton.view
                { enabled = ui.pickedId /= Nothing && selectedCount > 0
                , cls = "action-btn action-btn--green"
                , msg = ReplaceApplySelected
                , tip =
                    if ui.pickedId == Nothing then
                        "Pick a replacement creature first"

                    else if selectedCount == 0 then
                        "Select creatures first"

                    else
                        "Swap in the picked creature for every selected creature"
                , label = "Selected (" ++ String.fromInt selectedCount ++ ")"
                }
            ]
        , logSection logOpts log
        ]


searchRow : ReplaceUi -> Html Msg
searchRow ui =
    div [ class "cond-row" ]
        [ Html.label [ class "cond-label" ] [ text "Replace with:" ]
        , input
            [ class "cond-input cond-input--w20"
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


logSection : { open : Bool, expanded : Set String } -> List ReplaceLogEntry -> Html Msg
logSection opts entries =
    div [ class "cond-section" ]
        (Field.foldHead
            { open = opts.open
            , title = "Log (" ++ String.fromInt (List.length entries) ++ ")"
            , msg = ReplaceLogToggle
            , trail = []
            }
            :: (if not opts.open then
                    []

                else if List.isEmpty entries then
                    [ div [ class "log-empty" ] [ text "Nothing replaced yet." ] ]

                else
                    [ Html.Keyed.ul [ class "log-list" ]
                        (List.map (logRow opts.expanded) entries)
                    ]
               )
        )


logRow : Set String -> ReplaceLogEntry -> ( String, Html Msg )
logRow expanded e =
    let
        key =
            "rep-" ++ String.fromInt e.seq
    in
    ( key
    , View.LogRow.sentence
        { key = key
        , expanded = Set.member key expanded
        , kind = "Replace"
        , kindClass = "hp-change__log-kind--cond"
        , names = String.join ", " e.olds
        , detail = "→ " ++ String.join ", " e.news
        , flash = False
        , trail = []
        }
    )
