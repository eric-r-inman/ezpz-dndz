module View.HpLog exposing (entry, latest)

{-| Recent-HP-changes row rendering, shared between the dice
roller's log (where the rows are interleaved with the rolls) and
the Manage-HP editor (newest entry only) — the markup exists once
so the two mounts can't drift apart.
-}

import Html exposing (Html, button, li, span, text, ul)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import Html.Keyed
import Msg exposing (HpKind(..), Msg(..))
import Ui.HpChange exposing (HpChangeEntry)
import View.Tooltips as Tooltips


{-| Just the newest entry (undo-able), for the card expansion.
Renders nothing when the log is empty — the expansion shouldn't
grow a header for a list that isn't there.
-}
latest : Int -> List HpChangeEntry -> Html Msg
latest flashedSeq entries =
    case entries of
        newest :: _ ->
            -- Keyed on the entry's own counter so each application
            -- mounts a fresh row rather than patching the last
            -- one.  A patched row keeps its animation state, and
            -- the flash is the whole point: two identical applies
            -- in a row have to read as two.
            Html.Keyed.ul
                [ class "hp-change__log-list hp-change__log-list--latest" ]
                [ ( String.fromInt newest.seq
                  , row (rowClassFor flashedSeq newest) True newest
                  )
                ]

        [] ->
            text ""


{-| Render one log row. Only the newest entry carries an inline
undo button, so a misclick can't silently rewrite the middle of
the history.
-}
entry : Bool -> HpChangeEntry -> Html Msg
entry =
    row "hp-change__log-entry"


{-| A row the panel has already shown mounts unflashed. Folding
the panel destroys it, so without this an unfold would replay the
cue for a change that landed long before.
-}
rowClassFor : Int -> HpChangeEntry -> String
rowClassFor flashedSeq e =
    if e.seq > flashedSeq then
        "hp-change__log-entry hp-change__log-entry--flash"

    else
        "hp-change__log-entry"


{-| The row markup, under whichever class the mount wants. The
editor's single-row mount takes the flashing variant; the dice
roller's full log takes the plain one, because nothing there
answers a click the GM just made.
-}
row : String -> Bool -> HpChangeEntry -> Html Msg
row rowClass undoable e =
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

        names =
            String.join ", " (List.map .name e.targets)

        -- The before → after slug only reads cleanly for a single
        -- creature; a multi-target entry names everyone instead
        -- and leaves the per-creature arithmetic to the cards.
        transition =
            case e.targets of
                [ only ] ->
                    hpSnapshot only.beforeHp only.beforeTemp only.beforeMax
                        ++ " → "
                        ++ hpSnapshot only.afterHp only.afterTemp only.afterMax

                _ ->
                    ""
    in
    li [ class rowClass ]
        [ span [ class kindClass ] [ text kindLabel ]
        , span [ class "hp-change__log-target" ] [ text names ]
        , span [ class "hp-change__log-amount" ]
            [ text (String.fromInt e.amount) ]
        , span [ class "hp-change__log-trans" ] [ text transition ]
        , if undoable then
            button
                [ class "icon-btn icon-btn--sm hp-change__log-undo"
                , onClick HpChangeUndoLatest
                , Tooltips.attr
                    ("Undo: revert " ++ names ++ " to previous HP")
                , attribute "aria-label"
                    ("Undo " ++ kindLabel ++ " on " ++ names)
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
