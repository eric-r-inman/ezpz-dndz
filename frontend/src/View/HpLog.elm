module View.HpLog exposing (latest, list)

{-| Recent-HP-changes log rendering, shared between the dice
modal (the full capped list) and the creature card's inline
Manage-HP expansion (newest entry only, with its undo button).

Extracted from the retired Manage-HP modal so the row markup
exists once — both mounts must agree on what an entry looks
like or the "same log, two homes" story falls apart.

-}

import Html exposing (Html, button, div, li, span, text, ul)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import Msg exposing (HpKind(..), Msg(..))
import Ui.HpChange exposing (HpChangeEntry)
import View.Tooltips as Tooltips


{-| The full log section: title with count, then every retained
entry (capped upstream at `Ui.HpChange.maxHpLogEntries`). Empty
state shows a small "No HP changes yet" line so the section
doesn't collapse to nothing.
-}
list : List HpChangeEntry -> Html Msg
list entries =
    div [ class "hp-change__log" ]
        [ div [ class "hp-change__log-title" ]
            [ text ("Recent HP changes (" ++ String.fromInt (List.length entries) ++ ")") ]
        , if List.isEmpty entries then
            div [ class "hp-change__log-empty" ]
                [ text "No HP changes yet." ]

          else
            ul [ class "hp-change__log-list" ]
                (List.indexedMap entry entries)
        ]


{-| Just the newest entry (undo-able), for the card expansion.
Renders nothing when the log is empty — the expansion shouldn't
grow a header for a list that isn't there.
-}
latest : List HpChangeEntry -> Html Msg
latest entries =
    case entries of
        newest :: _ ->
            ul [ class "hp-change__log-list hp-change__log-list--latest" ]
                [ entry 0 newest ]

        [] ->
            text ""


{-| Render one log row. The newest entry (`index == 0`) carries
an inline undo button so the GM can revert the latest change in
one click; older rows render without it so a misclick can't
silently rewrite the middle of the history.
-}
entry : Int -> HpChangeEntry -> Html Msg
entry index e =
    let
        kindLabel =
            case e.kind of
                DamageKind ->
                    "Damage"

                HealKind ->
                    "Heal"

                TempHpKind ->
                    "Temp HP"

                MaxHpKind ->
                    "+Max HP"

        kindClass =
            case e.kind of
                DamageKind ->
                    "hp-change__log-kind hp-change__log-kind--damage"

                HealKind ->
                    "hp-change__log-kind hp-change__log-kind--heal"

                TempHpKind ->
                    "hp-change__log-kind hp-change__log-kind--temp"

                MaxHpKind ->
                    "hp-change__log-kind hp-change__log-kind--max"

        beforeStr =
            hpSnapshot e.beforeHp e.beforeTemp e.beforeMax

        afterStr =
            hpSnapshot e.afterHp e.afterTemp e.afterMax
    in
    li [ class "hp-change__log-entry" ]
        [ span [ class kindClass ] [ text kindLabel ]
        , span [ class "hp-change__log-target" ] [ text e.target ]
        , span [ class "hp-change__log-amount" ]
            [ text (String.fromInt e.amount) ]
        , span [ class "hp-change__log-trans" ]
            [ text (beforeStr ++ " → " ++ afterStr) ]
        , if index == 0 then
            button
                [ class "icon-btn icon-btn--sm hp-change__log-undo"
                , onClick HpChangeUndoLatest
                , Tooltips.attr
                    ("Undo: revert " ++ e.target ++ " to " ++ beforeStr)
                , attribute "aria-label"
                    ("Undo " ++ kindLabel ++ " on " ++ e.target)
                ]
                [ text "↩" ]

          else
            text ""
        ]


{-| Render an HP+temp[+max] slug: "27/59" or "27/59 +5" when temp
HP is positive. The maxHp is included implicitly via the
"current/max" pair, so a +Max HP row's before → after shift is
legible without a separate max field.
-}
hpSnapshot : Int -> Int -> Int -> String
hpSnapshot hp temp maxHp =
    let
        stem =
            String.fromInt hp ++ "/" ++ String.fromInt maxHp
    in
    if temp > 0 then
        stem ++ " +" ++ String.fromInt temp

    else
        stem
