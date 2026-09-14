module View.ConditionLog exposing (section)

{-| The condition editor's log, in the Manage HP log's shape: a
fold over every application, newest first, each row unfolding to
its full text, with the undo on the newest.

@docs section

-}

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import Html.Keyed
import Msg exposing (Msg(..))
import Set exposing (Set)
import Ui.Condition exposing (ConditionLogEntry)
import View.Inline.Field as Field
import View.LogRow
import View.Tooltips as Tooltips


section : { open : Bool, expanded : Set String } -> List ConditionLogEntry -> Html Msg
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
            , msg = ConditionLogToggle
            , trail = []
            }
            :: (if not opts.open then
                    []

                else if List.isEmpty entries then
                    [ div [ class "log-empty" ] [ text "No conditions applied yet." ] ]

                else
                    [ Html.Keyed.ul [ class "log-list" ] rows ]
               )
        )


{-| The row's identity in `Model.expandedLogRows`.
-}
rowKey : ConditionLogEntry -> String
rowKey e =
    "cond-" ++ String.fromInt e.seq


{-| Only the newest entry carries the undo, so a misclick can't
rewrite the middle of the history.
-}
entry : { undoable : Bool, expanded : Bool } -> ConditionLogEntry -> Html Msg
entry opts e =
    let
        names =
            String.join ", " (List.map .name e.targets)
    in
    View.LogRow.sentence
        { key = rowKey e
        , expanded = opts.expanded
        , kind = e.conditionName
        , names = names
        , detail =
            if String.isEmpty e.note then
                e.summary

            else
                e.summary ++ " · " ++ e.note
        , trail =
            if opts.undoable then
                [ button
                    [ class "icon-btn icon-btn--sm hp-change__log-undo"
                    , onClick ConditionUndoLatest
                    , Tooltips.attr ("Undo: remove " ++ e.conditionName ++ " from " ++ names)
                    , attribute "aria-label" ("Undo " ++ e.conditionName ++ " on " ++ names)
                    ]
                    [ text "↩" ]
                ]

            else
                []
        }
