module View.Inline.Replace exposing (view)

{-| Replace editor body. A swap preserves each replaced
creature's queue position and initiative.
-}

import Compendium
import Effects
import Html exposing (Html, div, input, li, span, text, ul)
import Html.Attributes as Attr exposing (attribute, class, id, placeholder, tabindex, type_, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn)
import Html.Keyed
import Msg exposing (Msg(..))
import Set exposing (Set)
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Replace exposing (ReplaceLogEntry, ReplaceUi)
import Util.Keyboard
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
                ul
                    [ class "quick-add__list quick-add__list--docked"
                    , attribute "role" "listbox"
                    , attribute "aria-label" "Replacement creature"
                    ]
                    (Util.Keyboard.neighbours creatures |> List.map (row ui (tabStop ui creatures)))

        CompendiumDbLoading ->
            div [ class "cond-section__caption" ] [ text "Loading the compendium…" ]

        CompendiumDbFailed _ ->
            div [ class "cond-section__caption" ] [ text "Couldn't load the compendium." ]


{-| The list's one tab stop. It is the picked creature while the
list still shows it, and the first row otherwise.
-}
tabStop : ReplaceUi -> List Compendium.Creature -> Maybe String
tabStop ui creatures =
    ui.pickedId
        |> Maybe.andThen (\picked -> List.filter (\c -> c.id == picked) creatures |> List.head)
        |> Maybe.map Just
        |> Maybe.withDefault (List.head creatures)
        |> Maybe.map .id


{-| An arrow key picks a neighbour. `ReplacePick` toggles a pick.
A neighbour is never the picked row. An arrow therefore always
picks.
-}
row :
    ReplaceUi
    -> Maybe String
    -> { previous : Maybe Compendium.Creature, option : Compendium.Creature, next : Maybe Compendium.Creature }
    -> Html Msg
row ui stop { previous, option, next } =
    li
        [ class
            (if ui.pickedId == Just option.id then
                "quick-add__row quick-add__row--picked"

             else
                "quick-add__row"
            )
        , id (Effects.replaceRowId option.id)
        , tabindex
            (if stop == Just option.id then
                0

             else
                -1
            )
        , onClick (ReplacePick option.id)
        , preventDefaultOn "keydown"
            (Util.Keyboard.listboxOptionKeys
                { pick = ReplacePick option.id
                , previous = Maybe.map (.id >> ReplacePick) previous
                , next = Maybe.map (.id >> ReplacePick) next
                }
            )
        , attribute "role" "option"
        , attribute "aria-selected"
            (if ui.pickedId == Just option.id then
                "true"

             else
                "false"
            )
        ]
        [ span [ class "quick-add__name" ] [ text option.name ]
        , span [ class "quick-add__cr" ] [ text (crLabel option.challengeRating) ]
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
