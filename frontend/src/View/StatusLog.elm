module View.StatusLog exposing (section)

{-| The status editor's log, in the condition log's shape: a fold
over every apply, newest first, each row unfolding to its full
text, with the undo on the newest.

@docs section

-}

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import Html.Keyed
import Msg exposing (Msg(..))
import Set exposing (Set)
import Ui.Status exposing (StatusLogEntry)
import View.Inline.Field as Field
import View.LogRow
import View.Tooltips as Tooltips


section : { open : Bool, expanded : Set String } -> List StatusLogEntry -> Html Msg
section opts entries =
    let
        rows =
            List.indexedMap
                (\i e ->
                    ( String.fromInt e.seq
                    , entry
                        { undoable = i == 0
                        , expanded = Set.member (rowKey e) opts.expanded
                        }
                        e
                    )
                )
                entries
    in
    div [ class "cond-section" ]
        (Field.foldHead
            { open = opts.open
            , title = "Log (" ++ String.fromInt (List.length entries) ++ ")"
            , msg = StatusLogToggle
            , trail = []
            }
            :: (if not opts.open then
                    []

                else if List.isEmpty entries then
                    [ div [ class "log-empty" ] [ text "No statuses applied yet." ] ]

                else
                    [ Html.Keyed.ul [ class "log-list" ] rows ]
               )
        )


{-| The row's identity in `Model.expandedLogRows`.
-}
rowKey : StatusLogEntry -> String
rowKey e =
    "status-" ++ String.fromInt e.seq


{-| Only the newest entry carries the undo, so a misclick can't
rewrite the middle of the history.
-}
entry : { undoable : Bool, expanded : Bool } -> StatusLogEntry -> Html Msg
entry opts e =
    let
        names =
            String.join ", " (List.map .name e.targets)
    in
    View.LogRow.sentence
        { key = rowKey e
        , expanded = opts.expanded
        , kind = "Status"
        , kindClass = "hp-change__log-kind--cond"
        , names = names
        , detail = e.summary
        , flash = False
        , trail =
            if opts.undoable then
                [ button
                    [ class "icon-btn icon-btn--sm hp-change__log-undo"
                    , onClick StatusUndoLatest
                    , Tooltips.attr ("Undo: put " ++ names ++ " back as they were")
                    , attribute "aria-label" ("Undo status on " ++ names)
                    ]
                    [ text "↩" ]
                ]

            else
                []
        }
