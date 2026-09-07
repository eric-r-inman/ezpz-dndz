module View.HpLog exposing (Latest, Row, entry, latest, rowKey)

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
import Set exposing (Set)
import Ui.HpChange exposing (HpChangeEntry)
import View.LogRow
import View.Tooltips as Tooltips


{-| Just the newest entry (undo-able), for the card expansion.
Renders nothing when the log is empty — the expansion shouldn't
grow a header for a list that isn't there.
-}
latest : Latest -> List HpChangeEntry -> Html Msg
latest opts entries =
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
                  , entry
                        { undoable = True
                        , flash = newest.seq > opts.flashedSeq
                        , expanded = Set.member (rowKey newest) opts.expanded
                        }
                        newest
                  )
                ]

        [] ->
            text ""


{-| What the editor's single-row mount needs to know: the seq it
last showed (a row past it flashes; see `Model.flashedHpLogSeq`)
and which rows the GM has unfolded.
-}
type alias Latest =
    { flashedSeq : Int
    , expanded : Set String
    }


{-| How one row renders. `flash` is the editor's cue for an apply
that just landed; the dice roller's list never sets it, because
nothing there answers a click the GM just made.
-}
type alias Row =
    { undoable : Bool
    , flash : Bool
    , expanded : Bool
    }


{-| The row's identity in `Model.expandedLogRows`.
-}
rowKey : HpChangeEntry -> String
rowKey e =
    "hp-" ++ String.fromInt e.seq


{-| Render one log row. Only the newest entry carries an inline
undo button, so a misclick can't silently rewrite the middle of
the history.
-}
entry : Row -> HpChangeEntry -> Html Msg
entry opts e =
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

        rowClass =
            if opts.flash then
                "hp-change__log-entry hp-change__log-entry--flash"

            else
                "hp-change__log-entry"
    in
    li [ class rowClass ]
        [ View.LogRow.foldToggle (rowKey e) opts.expanded
        , span [ class kindClass ] [ text kindLabel ]
        , span [ class (View.LogRow.openable "hp-change__log-target" opts.expanded) ]
            [ text names ]
        , span [ class "hp-change__log-amount" ]
            [ text (String.fromInt e.amount) ]
        , span [ class (View.LogRow.openable "hp-change__log-trans" opts.expanded) ]
            [ text transition ]
        , if opts.undoable then
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
