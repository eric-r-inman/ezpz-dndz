module View.HpLog exposing (Row, entry, rowKey, section)

{-| Recent-HP-changes rendering, shared between the dice roller's
log (where the rolled rows are interleaved with the rolls) and the
Manage-HP editor's own log — the row markup exists once so the two
mounts can't drift apart.
-}

import Html exposing (Html, button, div, li, span, text)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import Html.Keyed
import Msg exposing (HpKind(..), Msg(..))
import Set exposing (Set)
import Ui.HpChange exposing (HpChangeEntry, HpLogKind(..))
import View.Inline.Field as Field
import View.LogRow
import View.Tooltips as Tooltips


{-| The Manage HP editor's log: a fold in the dice roller's style
over every entry, newest first, with the undo on the newest.
`flashedSeq` is the seq the editor last showed (a newer row
flashes; see `Model.flashedHpLogSeq`) and `expanded` the rows the
GM has unfolded.
-}
section : { open : Bool, flashedSeq : Int, expanded : Set String } -> List HpChangeEntry -> Html Msg
section opts entries =
    let
        rows =
            List.indexedMap
                (\i e ->
                    -- Keyed on the entry's own counter so each
                    -- application mounts a fresh row rather than
                    -- patching the last one; a patched row keeps
                    -- its animation state, and the flash is the
                    -- point: two identical applies have to read as
                    -- two.
                    ( String.fromInt e.seq
                    , entry
                        { undoable = i == 0
                        , flash = i == 0 && e.seq > opts.flashedSeq
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
            , msg = HpChangeLogToggle
            , trail = []
            }
            :: (if not opts.open then
                    []

                else if List.isEmpty entries then
                    [ div [ class "log-empty" ] [ text "No changes yet." ] ]

                else
                    [ Html.Keyed.ul [ class "log-list" ] rows ]
               )
        )


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
        ( kindLabel, kindClass ) =
            case e.kind of
                Applied DamageKind ->
                    ( "Damage", "hp-change__log-kind hp-change__log-kind--damage" )

                Applied HealKind ->
                    ( "Heal", "hp-change__log-kind hp-change__log-kind--heal" )

                Applied TempHpKind ->
                    ( "Temp HP", "hp-change__log-kind hp-change__log-kind--temp" )

                Applied MaxHpKind ->
                    ( "+Max HP", "hp-change__log-kind hp-change__log-kind--max" )

                SetPools ->
                    ( "Set", "hp-change__log-kind hp-change__log-kind--set" )

                RolledHp ->
                    ( "Roll", "hp-change__log-kind hp-change__log-kind--roll" )

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
            String.join " "
                (List.filterMap identity
                    [ Just "hp-change__log-entry"
                    , if opts.flash then
                        Just "hp-change__log-entry--flash"

                      else
                        Nothing
                    , if opts.expanded then
                        Just "hp-change__log-entry--open"

                      else
                        Nothing
                    ]
                )
    in
    li [ class rowClass ]
        [ View.LogRow.foldToggle (rowKey e) opts.expanded
        , span [ class kindClass ] [ text kindLabel ]
        , span [ class (View.LogRow.openable "hp-change__log-target" opts.expanded) ]
            [ text names ]
        , span [ class "hp-change__log-amount" ]
            [ text (Maybe.withDefault "" (Maybe.map String.fromInt e.amount)) ]
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
