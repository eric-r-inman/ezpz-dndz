module View.Inline.Duplicate exposing (view)

{-| Duplicate editor body.
-}

import Html exposing (Html, div, input, span, text)
import Html.Attributes as Attr exposing (checked, class, type_)
import Html.Events exposing (onClick)
import Html.Keyed
import Msg exposing (DuplicateMode(..), Msg(..))
import Set exposing (Set)
import Ui.Duplicate exposing (DuplicateLogEntry, DuplicateUi)
import View.Inline.ApplyButton as ApplyButton
import View.Inline.Field as Field
import View.LogRow


view : Int -> Bool -> { open : Bool, expanded : Set String } -> List DuplicateLogEntry -> DuplicateUi -> Html Msg
view selectedCount placeholderWarning logOpts log ui =
    div [ class "editor-body" ]
        [ modeSection ui
        , ApplyButton.row "Apply to:"
            [ ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--green"
                , msg = DuplicateApply
                , tip = "Copy the target creature"
                , label = "Target"
                }
            , ApplyButton.view
                { enabled = selectedCount > 0
                , cls = "action-btn action-btn--green"
                , msg = DuplicateApplySelected
                , tip =
                    if selectedCount == 0 then
                        "Select creatures first"

                    else
                        "Copy every selected creature"
                , label = "Selected (" ++ String.fromInt selectedCount ++ ")"
                }
            ]
        , ApplyButton.placeholderNotice placeholderWarning
        , logSection logOpts log
        ]


modeSection : DuplicateUi -> Html Msg
modeSection ui =
    div [ class "cond-section" ]
        [ div [ class "cond-row" ]
            [ Html.label [ class "cond-label" ] [ text "Copy as:" ]
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


logSection : { open : Bool, expanded : Set String } -> List DuplicateLogEntry -> Html Msg
logSection opts entries =
    div [ class "cond-section" ]
        (Field.foldHead
            { open = opts.open
            , title = "Log (" ++ String.fromInt (List.length entries) ++ ")"
            , msg = DuplicateLogToggle
            , trail = []
            }
            :: (if not opts.open then
                    []

                else if List.isEmpty entries then
                    [ div [ class "log-empty" ] [ text "Nothing duplicated yet." ] ]

                else
                    [ Html.Keyed.ul [ class "log-list" ]
                        (List.map (row opts.expanded) entries)
                    ]
               )
        )


row : Set String -> DuplicateLogEntry -> ( String, Html Msg )
row expanded e =
    let
        key =
            "dup-" ++ String.fromInt e.seq
    in
    ( key
    , View.LogRow.sentence
        { key = key
        , expanded = Set.member key expanded
        , kind = e.modeLabel
        , names = String.join ", " e.sources
        , detail = "→ " ++ String.join ", " e.created
        , trail = []
        }
    )
