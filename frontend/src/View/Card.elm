module View.Card exposing (view)

{-| Per-creature combat card.

Three rows + two side rails + an optional legendary-pip column:

  - Row 1 (top): initiative circle, name (with optional
    compendium link), note pencil / inline note, AC readout,
    condition / save-notice chips.
  - Row 2 (mid): HP display (click-to-edit), bloodied marker,
    cover toggle, concentration / hiding / dodging / flying
    toggles, fly-height.
  - Row 3 (bot): Damage / Heal / Temp HP / Condition action
    buttons, ready/readied toggle, memo slot, timer slot.

The two side rails carry the queue-mutation buttons (select,
move up/down on the left; remove, duplicate on the right) and
the "make active" arrow.

The legendary-pip column lives between the center column and
the right rail, and is only present when the creature's
compendium source declared `legendary_actions` or has a
"Legendary Resistance" trait. To its left, a death-save
column appears whenever the creature is at 0 HP.

-}

import Effects
import Encounter exposing (Cover(..), Creature)
import Html exposing (Html, article, button, div, input, p, span, text)
import Html.Attributes as Attr exposing (attribute, autofocus, checked, class, id, title, type_, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn, stopPropagationOn)
import Json.Decode as Decode
import Msg
    exposing
        ( HpField(..)
        , HpKind(..)
        , Msg(..)
        )
import Set exposing (Set)
import Ui.HpChange exposing (HpEdit)
import View.Tooltips as Tooltips


view : String -> Maybe HpEdit -> Creature -> Html Msg
view activeName hpEdit creature =
    let
        isActive =
            creature.name == activeName

        isDead =
            Encounter.isDeathSaveDead creature.deathSaves

        cardClass =
            String.join " "
                (List.filterMap identity
                    [ Just "creature-card"
                    , if isActive then
                        Just "creature-card--active"

                      else
                        Nothing
                    , if isDead then
                        Just "creature-card--dead"

                      else
                        Nothing
                    , if creature.inactive then
                        Just "creature-card--inactive"

                      else
                        Nothing
                    ]
                )
    in
    article [ id (Effects.cardId creature.name), class cardClass ]
        [ div [ class "creature-card__rail creature-card__rail--left" ]
            [ div [ class "creature-card__rail-group" ]
                [ input
                    [ type_ "checkbox"
                    , class "creature-card__select"
                    , checked creature.selected
                    , selectionClickHandler creature.name
                    , attribute "aria-label" ("Select " ++ creature.name)
                    , Tooltips.attr Tooltips.queueSelectShiftClick
                    ]
                    []
                , button
                    [ class "icon-btn"
                    , onClick (MoveCreatureUp creature.name)
                    , Tooltips.attr Tooltips.queueMoveUp
                    , attribute "aria-label" "Move up in queue"
                    ]
                    [ text "↑" ]
                , button
                    [ class "icon-btn"
                    , onClick (MoveCreatureDown creature.name)
                    , Tooltips.attr Tooltips.queueMoveDown
                    , attribute "aria-label" "Move down in queue"
                    ]
                    [ text "↓" ]
                ]
            , div [ class "creature-card__rail-group" ]
                [ button
                    [ class "icon-btn icon-btn--accent"
                    , onClick (SetActive creature.name)
                    , Tooltips.attr Tooltips.queueMakeActive
                    , attribute "aria-label" "Make active"
                    ]
                    [ text "→" ]
                ]
            ]
        , div [ class "creature-card__center" ]
            [ rowTop creature hpEdit
            , rowMid creature hpEdit
            , rowBot creature
            ]
        , deathSaveColumn creature
        , legendaryColumns creature
        , div [ class "creature-card__rail creature-card__rail--right" ]
            [ div [ class "creature-card__rail-group" ]
                [ button
                    [ class "icon-btn icon-btn--danger"
                    , onClick (RemoveCreature creature.name)
                    , Tooltips.attr Tooltips.queueRemove
                    , attribute "aria-label" "Remove"
                    ]
                    [ text "×" ]
                ]
            , div [ class "creature-card__rail-group" ]
                [ button
                    [ class
                        ("icon-btn"
                            ++ (if creature.inactive then
                                    " icon-btn--toggled"

                                else
                                    ""
                               )
                        )
                    , onClick (ToggleInactive creature.name)
                    , Tooltips.attr
                        (if creature.inactive then
                            Tooltips.queueReactivate

                         else
                            Tooltips.queueInactive
                        )
                    , attribute "aria-label" "Toggle inactive"
                    , attribute "aria-pressed"
                        (if creature.inactive then
                            "true"

                         else
                            "false"
                        )
                    ]
                    [ text "∅" ]
                ]
            , div [ class "creature-card__rail-group" ]
                [ button
                    [ class "icon-btn"
                    , onClick (DuplicateOpen creature.name)
                    , Tooltips.attr Tooltips.queueDuplicate
                    , attribute "aria-label" "Duplicate"
                    ]
                    [ text "⧉" ]
                ]
            ]
        ]


{-| Click handler for the row 1 selection checkbox.

We intercept the raw `click` event so we can read the Shift modifier:
holding Shift while clicking dispatches `ShiftToggleSelected` (bulk
select-all / deselect-all), and a plain click toggles just the
clicked creature. We always `preventDefault` so the browser doesn't
auto-toggle the checkbox visual — its `checked` attribute is driven
straight from the model on the next render, keeping a single source
of truth and avoiding the double-toggle that an `onCheck` listener
plus the browser's default would cause.

-}
selectionClickHandler : String -> Html.Attribute Msg
selectionClickHandler name_ =
    preventDefaultOn "click"
        (Decode.field "shiftKey" Decode.bool
            |> Decode.map
                (\shift ->
                    if shift then
                        ( ShiftToggleSelected, True )

                    else
                        ( ToggleSelected name_, True )
                )
        )



-- ── ROW 1 ───────────────────────────────────────────────────────────────


rowTop : Creature -> Maybe HpEdit -> Html Msg
rowTop creature hpEdit =
    div [ class "creature-card__row creature-card__row--top" ]
        [ button
            [ class "init-circle init-circle--clickable"
            , onClick (InitiativeOpen creature.name)
            , Tooltips.attr Tooltips.initiativeManager
            , attribute "aria-label"
                ("Initiative " ++ String.fromInt creature.initiative ++ " — open initiative manager")
            ]
            [ text (String.fromInt creature.initiative) ]
        , creatureName creature
        , noteOrPencil creature
        , acReadout creature hpEdit
        , conditionChips creature
        ]


{-| The creature name on row 1 of each card. When the creature has
a `creatureId` back-reference to a compendium entry, the name is
rendered as a clickable element that pins that entry's stat block
in the side panel — and an underline-on-hover style hints at the
affordance. Legacy seed creatures (no compendium link) render as
a plain span.
-}
creatureName : Creature -> Html Msg
creatureName creature =
    case creature.creatureId of
        Just id_ ->
            span
                [ class "creature-name creature-name--default creature-name--linked"
                , onClick (PanelShowCreature id_ creature.name)
                , Tooltips.attr Tooltips.showStatBlock
                ]
                [ text creature.name ]

        Nothing ->
            span [ class "creature-name creature-name--default" ]
                [ text creature.name ]


{-| Note-or-pencil sliver of row 1.

Empty note: just the pencil ✏️ button as an "add a note" affordance.

Non-empty note: the note itself (clickable, opens the same edit
modal so the user can rename or clear it) followed by a pipe
separator before the AC readout. The pencil is intentionally
hidden in this state — the note is now the click target, and
showing both would make the user wonder which one to use.

-}
noteOrPencil : Creature -> Html Msg
noteOrPencil creature =
    if String.isEmpty creature.note then
        button
            [ class "icon-btn icon-btn--sm"
            , onClick (NoteEditOpen creature.name creature.note)
            , Tooltips.attr Tooltips.noteAdd
            , attribute "aria-label" "Add note"
            ]
            [ text "✏️" ]

    else
        span [ class "creature-note-wrap" ]
            [ button
                [ class "creature-note creature-note--clickable"
                , onClick (NoteEditOpen creature.name creature.note)
                , Tooltips.attr Tooltips.noteEdit
                , attribute "aria-label" ("Edit note: " ++ creature.note)
                ]
                [ text creature.note ]
            , span [ class "creature-note__sep" ] [ text "|" ]
            ]



-- ── LEGENDARY PIP COLUMN ────────────────────────────────────────────────


{-| Two narrow vertical columns of pips on the creature card,
between the center column and the right rail. Each column has a
bold header letter ("LA" / "LR") followed by 4 toggleable circular
pips. The 4th pip is the in-lair bonus and renders with a thinner
border (and a faint divider above it) to mark it as optional.

Conditional rendering — both columns spawn only when the
creature's compendium source has the matching feature, and the
flag was baked into the encounter creature at spawn time
(`Compendium.draftToInstance`):

  - `hasLegendaryActions = True` (compendium source had
    `legendary_actions /= Nothing`) → orange LA column.
  - `hasLegendaryResistance = True` (compendium source had a
    trait whose name contains "Legendary Resistance") → yellow
    LR column.

The LA pips reset to "all available" at the start of the
creature's turn — `Encounter.applyBeginOfTurn` clears the
`legendaryActionsUsed` set as part of the begin-of-turn hook.
LR pips do NOT auto-reset (legendary resistance is per long rest
in 5e, not per turn).

When the creature has neither feature, returns `text ""` so the
card flex row stays compact.

-}
legendaryColumns : Creature -> Html Msg
legendaryColumns creature =
    if not creature.hasLegendaryActions && not creature.hasLegendaryResistance then
        text ""

    else
        div [ class "creature-card__legendary" ]
            [ if creature.hasLegendaryActions then
                legendaryColumn
                    { creatureName = creature.name
                    , kind = "la"
                    , label = "LA"
                    , used = creature.legendaryActionsUsed
                    , onToggle = ToggleLegendaryActionPip creature.name
                    }

              else
                text ""
            , if creature.hasLegendaryResistance then
                legendaryColumn
                    { creatureName = creature.name
                    , kind = "lr"
                    , label = "LR"
                    , used = creature.legendaryResistanceUsed
                    , onToggle = ToggleLegendaryResistancePip creature.name
                    }

              else
                text ""
            ]


legendaryColumn :
    { creatureName : String
    , kind : String
    , label : String
    , used : Set Int
    , onToggle : Int -> Msg
    }
    -> Html Msg
legendaryColumn cfg =
    let
        pip idx =
            let
                filled =
                    Set.member idx cfg.used
            in
            button
                [ class
                    ("legendary-col__pip"
                        ++ (if filled then
                                " legendary-col__pip--filled"

                            else
                                ""
                           )
                        ++ (if idx == 3 then
                                " legendary-col__pip--lair"

                            else
                                ""
                           )
                    )
                , onClick (cfg.onToggle idx)
                , Tooltips.attr
                    (cfg.label
                        ++ " pip "
                        ++ String.fromInt (idx + 1)
                        ++ (if filled then
                                ": used"

                            else
                                ": available"
                           )
                    )
                , attribute "aria-label"
                    (cfg.label ++ " pip " ++ String.fromInt (idx + 1))
                , attribute "aria-pressed"
                    (if filled then
                        "true"

                     else
                        "false"
                    )
                ]
                []
    in
    div [ class ("legendary-col legendary-col--" ++ cfg.kind) ]
        [ div
            [ class "legendary-col__header"
            , Tooltips.attr (headerTooltipFor cfg.label)
            ]
            [ text cfg.label ]
        , pip 0
        , pip 1
        , pip 2
        , div [ class "legendary-col__sep" ] []
        , pip 3
        ]


{-| Map the column's bold-header letter to the static tooltip
that describes what the pips count. Tooltips live in
=View.Tooltips=; the helper here picks the right one without
making the column-builder caller pass it in.
-}
headerTooltipFor : String -> String
headerTooltipFor label =
    case label of
        "LA" ->
            Tooltips.legendaryActionColumn

        "LR" ->
            Tooltips.legendaryResistanceColumn

        _ ->
            ""



-- ── CONDITION CHIPS ─────────────────────────────────────────────────────


{-| Live render of a creature's conditions and any post-save
"Saved: <name>" notices on row 1 of the card. Empty for both →
empty text node so the row's flex gap collapses naturally.
Otherwise we render a leading separator pipe followed by chips
(active conditions first, then notices) so the eye lands on the
condition the GM is most likely to act on.
-}
conditionChips : Creature -> Html Msg
conditionChips creature =
    if List.isEmpty creature.conditions && List.isEmpty creature.saveNotices then
        text ""

    else
        span [ class "condition-chips-wrap" ]
            (span [ class "row-top__sep" ] [ text "|" ]
                :: List.map (conditionChip creature.name) creature.conditions
                ++ List.map (saveNoticeChip creature.name) creature.saveNotices
            )


{-| "Saved: <Condition>" notice rendered as a small green chip.
Posted after a successful AUTO-roll save (manual chip-roll
successes remove the condition silently). Auto-removes on the
bearer's next end-of-turn; the × button dismisses earlier.
-}
saveNoticeChip : String -> Encounter.SaveNotice -> Html Msg
saveNoticeChip target notice =
    span
        [ class "save-notice"
        , Tooltips.attr (Tooltips.savedAgainstNotice notice.conditionName)
        ]
        [ text ("Saved: " ++ notice.conditionName)
        , button
            [ class "save-notice__dismiss"
            , onClick (SaveNoticeDismiss target notice.id)
            , Tooltips.attr Tooltips.saveNoticeDismiss
            , attribute "aria-label" "Dismiss save notice"
            ]
            [ text "×" ]
        ]


{-| One condition chip. Layout (left → right):
[ name + note ][ optional save-roll button ] [ duration glyph ][ × ]

Clicking the name opens the edit modal; the × runs the remove Msg
directly (and stops propagation so it doesn't also open the
modal). The save-roll button (when the condition has a
`saveToEnd`) fires a 1d20 vs. the DC and removes the condition on
success.

-}
conditionChip : String -> Encounter.Condition -> Html Msg
conditionChip target cond =
    span
        [ class "condition-chip"
        , Tooltips.attr (chipTitle cond)
        ]
        [ button
            [ class "condition-chip__name"
            , onClick (ConditionOpenEdit target cond.id)
            , Tooltips.attr Tooltips.clickToEdit
            ]
            [ text cond.name
            , if String.isEmpty cond.note then
                text ""

              else
                span [ class "condition-chip__note" ]
                    [ text (" (" ++ cond.note ++ ")") ]
            ]
        , chipSaveButton target cond
        , chipDurationGlyph cond
        , button
            [ class "condition-chip__remove"
            , stopPropagationOn "click"
                (Decode.succeed ( ConditionRemoveChip target cond.id, True ))
            , Tooltips.attr Tooltips.chipRemoveModalRow
            , attribute "aria-label" "Remove condition"
            ]
            [ text "×" ]
        ]


{-| Tooltip text for the whole chip. Combines name, duration, and
(if present) the save-to-end terms so the GM can hover for full
context without opening the modal.
-}
chipTitle : Encounter.Condition -> String
chipTitle cond =
    Tooltips.chipFullTitle
        cond.name
        (Encounter.describeDuration cond.duration)
        (Maybe.map (\s -> { ability = s.ability, dc = s.dc }) cond.saveToEnd)


{-| Inline d20 button next to a chip when the condition has a
saving throw conditional. Click rolls 1d20 + bonus and removes
the chip on success. Hidden when no save is configured.
-}
chipSaveButton : String -> Encounter.Condition -> Html Msg
chipSaveButton target cond =
    case cond.saveToEnd of
        Just spec ->
            button
                [ class "condition-chip__save"
                , stopPropagationOn "click"
                    (Decode.succeed ( ConditionRollSave target cond.id, True ))
                , Tooltips.attr
                    (Tooltips.chipRollSave
                        { ability = spec.ability
                        , dc = spec.dc
                        , bonus = formatBonus spec.bonus
                        }
                    )
                , attribute "aria-label" ("Roll save for " ++ cond.name)
                ]
                [ text "🎲" ]

        Nothing ->
            text ""


{-| Compact duration glyph appended to a chip. Manual durations
get nothing (the GM removes by hand); UntilTurn shows ⏱
N (where N is "Bk" or first 3 chars of the ref creature's name);
Countdown shows ⏳N.
-}
chipDurationGlyph : Encounter.Condition -> Html Msg
chipDurationGlyph cond =
    case cond.duration of
        Encounter.DurationManual ->
            text ""

        Encounter.DurationUntilTurn _ _ ref ->
            span [ class "condition-chip__duration" ]
                [ text ("⏱ " ++ String.left 4 ref) ]

        Encounter.DurationCountdown _ remaining _ ->
            span [ class "condition-chip__duration" ]
                [ text ("⏳ " ++ String.fromInt remaining) ]


formatBonus : Int -> String
formatBonus n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n



-- ── ROW 2 ───────────────────────────────────────────────────────────────


rowMid : Creature -> Maybe HpEdit -> Html Msg
rowMid creature hpEdit =
    div [ class "creature-card__row creature-card__row--mid" ]
        [ hpDisplay creature hpEdit
        , bloodied creature
        , coverToggle creature
        , span [ class "status-toggles__sep" ] [ text "|" ]
        , boolToggle "🧠"
            "concentrating"
            creature.concentrating
            (ToggleConcentration creature.name)
        , span [ class "status-toggles__sep" ] [ text "|" ]
        , boolToggle "👤"
            "hiding"
            creature.hiding
            (ToggleHiding creature.name)
        , span [ class "status-toggles__sep" ] [ text "|" ]
        , boolToggle "🤸"
            "dodging"
            creature.dodging
            (ToggleDodging creature.name)
        , span [ class "status-toggles__sep" ] [ text "|" ]
        , span [ class "flying-group" ]
            [ boolToggle "🪽"
                "flying"
                creature.flying
                (ToggleFlying creature.name)
            , flyHeight creature
            ]
        ]


{-| Click-to-edit AC readout on row 1. Same inline-edit machinery
as the HP fields — clicking the number swaps it for an `<input>`
that commits on blur / Enter and cancels on Esc. Lets the GM
patch a single creature's AC (e.g. for a temporary Shield-spell
bonus) without touching the compendium template.
-}
acReadout : Creature -> Maybe HpEdit -> Html Msg
acReadout creature hpEdit =
    span [ class "ac-readout" ]
        [ Html.text "AC: "
        , hpEditable creature hpEdit ArmorClassField creature.armorClass "ac-readout__value"
        ]


{-| Card row 2 HP readout: green current / muted max, plus an
inline "+N" temp-HP marker when the creature is buffed. Both the
current and max values are click-to-edit: clicking swaps the span
for a small `<input>` (autofocus + onBlur commits, Enter commits,
Esc cancels). The temp HP doesn't get an inline editor — it's
not a value the GM normally types directly, and the Temp HP modal
is the canonical write path.
-}
hpDisplay : Creature -> Maybe HpEdit -> Html Msg
hpDisplay creature hpEdit =
    span [ class "hp-display" ]
        [ hpEditable creature hpEdit CurrentHpField creature.currentHp "hp-display__current"
        , span [ class "hp-display__sep" ] [ text "/" ]
        , hpEditable creature hpEdit MaxHpField creature.maxHp "hp-display__max"
        , if creature.tempHp > 0 then
            span
                [ class "hp-display__temp"
                , Tooltips.attr Tooltips.tempHp
                ]
                [ text ("+" ++ String.fromInt creature.tempHp) ]

          else
            text ""
        ]


{-| Render either a clickable value or the active inline-edit
input, depending on whether `hpEdit` is targeting this creature +
field. Same shape as the dice modifier field — the input value
mirrors `edit.text` (raw characters) so transient empty / "-"
states aren't clobbered.
-}
hpEditable : Creature -> Maybe HpEdit -> HpField -> Int -> String -> Html Msg
hpEditable creature hpEdit field current cls =
    let
        isEditing =
            case hpEdit of
                Just e ->
                    e.target == creature.name && e.field == field

                Nothing ->
                    False
    in
    if isEditing then
        input
            [ class "hp-display__edit"
            , type_ "number"
            , Attr.min "0"
            , Attr.max "9999"
            , value (Maybe.withDefault "" (Maybe.map .text hpEdit))
            , onInput HpEditChange
            , Html.Events.onBlur HpEditCommit
            , Html.Events.on "keydown" hpEditKeyDecoder
            , autofocus True
            ]
            []

    else
        span
            [ class (cls ++ " hp-display__editable")
            , onClick (HpEditStart creature.name field current)
            , Tooltips.attr Tooltips.clickToEdit
            ]
            [ text (String.fromInt current) ]


{-| Enter commits the inline HP edit, Esc cancels. Other keys
fall through to the input's normal handling.
-}
hpEditKeyDecoder : Decode.Decoder Msg
hpEditKeyDecoder =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                case key of
                    "Enter" ->
                        Decode.succeed HpEditCommit

                    "Escape" ->
                        Decode.succeed HpEditCancel

                    _ ->
                        Decode.fail "ignore"
            )


bloodied : Creature -> Html Msg
bloodied creature =
    if creature.bloodied then
        span
            [ class "bloodied"
            , Tooltips.attr Tooltips.bloodied
            , attribute "aria-label" "Bloodied"
            ]
            [ text "🩸" ]

    else
        text ""


{-| The 5e death-save tracker, rendered as a side-by-side pair of
vertical columns (✓ successes, ✗ failures) to the left of the
legendary-pip rail. Visibility is keyed off `currentHp == 0`
exclusively — the moment the creature is back above 0 HP they're
conscious, and the tracker shouldn't be on screen at all. The
HP-change engine already resets the counts on heal-to-positive,
so when the columns re-appear (next time they hit 0) they start
fresh.

Layout mirrors the legendary "LA"/"LR" columns but doubled: each
column has its own header + 3 pips, and below the pair sits the
shared 🎲 roll button. Once stable (3 successes) or dead (3
failures), the Roll button is replaced by a 🛡 / 💀 badge — the
GM can still un-set pips manually if they need to reset, but the
automated flow stops.

-}
deathSaveColumn : Creature -> Html Msg
deathSaveColumn creature =
    if creature.currentHp /= 0 then
        text ""

    else
        let
            ds =
                creature.deathSaves

            stable =
                Encounter.isDeathSaveStable ds

            dead =
                Encounter.isDeathSaveDead ds

            footer =
                if dead then
                    span
                        [ class "death-save-cols__badge death-save-cols__badge--dead"
                        , Tooltips.attr Tooltips.deathDead
                        ]
                        [ text "💀" ]

                else if stable then
                    span
                        [ class "death-save-cols__badge death-save-cols__badge--stable"
                        , Tooltips.attr Tooltips.deathStable
                        ]
                        [ text "🛡" ]

                else
                    button
                        [ class "death-save-cols__roll"
                        , onClick (DeathSaveRoll creature.name)
                        , Tooltips.attr Tooltips.deathRoll
                        , attribute "aria-label" "Roll death save"
                        ]
                        [ text "🎲" ]

            successColumn =
                div [ class "death-save-col death-save-col--success" ]
                    [ div [ class "death-save-col__header" ] [ text "✓" ]
                    , deathSavePip "success" (0 < ds.successes) (DeathSaveToggleSuccess creature.name 0) "Success" 1
                    , deathSavePip "success" (1 < ds.successes) (DeathSaveToggleSuccess creature.name 1) "Success" 2
                    , deathSavePip "success" (2 < ds.successes) (DeathSaveToggleSuccess creature.name 2) "Success" 3
                    ]

            failureColumn =
                div [ class "death-save-col death-save-col--failure" ]
                    [ div [ class "death-save-col__header" ] [ text "✗" ]
                    , deathSavePip "failure" (0 < ds.failures) (DeathSaveToggleFailure creature.name 0) "Failure" 1
                    , deathSavePip "failure" (1 < ds.failures) (DeathSaveToggleFailure creature.name 1) "Failure" 2
                    , deathSavePip "failure" (2 < ds.failures) (DeathSaveToggleFailure creature.name 2) "Failure" 3
                    ]
        in
        div
            [ class "death-save-cols"
            , attribute "role" "group"
            , attribute "aria-label" "Death saving throws"
            ]
            [ div [ class "death-save-cols__row" ]
                [ successColumn, failureColumn ]
            , footer
            ]


deathSavePip : String -> Bool -> Msg -> String -> Int -> Html Msg
deathSavePip kind filled onToggle kindLabel ordinal =
    button
        [ class
            ("death-save-col__pip death-save-col__pip--"
                ++ kind
                ++ (if filled then
                        " death-save-col__pip--filled"

                    else
                        ""
                   )
            )
        , onClick onToggle
        , Tooltips.attr
            (kindLabel
                ++ " "
                ++ String.fromInt ordinal
                ++ (if filled then
                        ": filled — click to clear"

                    else
                        ": empty — click to set"
                   )
            )
        , attribute "aria-label"
            (kindLabel ++ " pip " ++ String.fromInt ordinal)
        , attribute "aria-pressed"
            (if filled then
                "true"

             else
                "false"
            )
        ]
        []


{-| The `icon` argument is intentionally unused in the card row:
the GM already sees the toggle's text label and the title-row icon
(rendered separately in EncounterBar). Hiding the per-toggle icon
in the card buys horizontal space in row 2. The 🚫 prefix in the
off state replaces the older "not " / "no " wording so the off
state stays visually distinct without needing an icon glyph.
-}
boolToggle : String -> String -> Bool -> Msg -> Html Msg
boolToggle _ label isOn msg =
    let
        ( bodyText, cls, tip ) =
            if isOn then
                ( label
                , "status-toggle status-toggle--on"
                , Tooltips.statusOnTip label
                )

            else
                ( "🚫 " ++ label
                , "status-toggle"
                , Tooltips.statusOffTip label
                )
    in
    button
        [ class cls
        , onClick msg
        , Tooltips.attr tip
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if isOn then
                "true"

             else
                "false"
            )
        ]
        [ text bodyText ]


coverToggle : Creature -> Html Msg
coverToggle creature =
    let
        ( bodyText, label, modifier ) =
            case creature.cover of
                NoCover ->
                    ( "🚫 cover", "No cover", "status-toggle--off" )

                HalfCover ->
                    ( "½ cover", "Half cover", "status-toggle--on" )

                ThreeQuartersCover ->
                    ( "¾ cover", "Three-quarters cover", "status-toggle--on" )

                FullCover ->
                    ( "full cover", "Full cover", "status-toggle--on" )
    in
    button
        [ class ("status-toggle " ++ modifier)
        , onClick (CycleCover creature.name)
        , Tooltips.attr (Tooltips.coverCycleTip label)
        , attribute "aria-label" ("Cover: " ++ label)
        ]
        [ text bodyText ]


flyHeight : Creature -> Html Msg
flyHeight creature =
    if creature.flying then
        span [ class "fly-height" ]
            [ button
                [ class "fly-height__btn"
                , onClick (AdjustFlyHeight creature.name 5)
                , Tooltips.attr Tooltips.flyHeightUp
                , attribute "aria-label" "Increase flight height by 5 feet"
                ]
                [ text "▲" ]
            , span [ class "fly-height__value" ]
                [ text (String.fromInt creature.flyHeight) ]
            , button
                [ class "fly-height__btn"
                , onClick (AdjustFlyHeight creature.name -5)
                , Tooltips.attr Tooltips.flyHeightDown
                , attribute "aria-label" "Decrease flight height by 5 feet"
                ]
                [ text "▼" ]
            , span [ class "fly-height__unit" ] [ text "ft" ]
            , button
                [ class "icon-btn icon-btn--sm fly-height__fall"
                , onClick (RollFallDamage creature.name)
                , Tooltips.attr Tooltips.fallDamage
                , attribute "aria-label" "Roll falling damage"
                ]
                [ text "↯" ]
            ]

    else
        text ""



-- ── ROW 3 ───────────────────────────────────────────────────────────────


rowBot : Creature -> Html Msg
rowBot creature =
    div [ class "creature-card__row creature-card__row--bot" ]
        [ button
            [ class "action-btn action-btn--damage"
            , onClick (HpChangeOpen creature.name DamageKind)
            , Tooltips.attr Tooltips.damage
            ]
            [ text "Damage" ]
        , button
            [ class "action-btn action-btn--heal"
            , onClick (HpChangeOpen creature.name HealKind)
            , Tooltips.attr Tooltips.heal
            ]
            [ text "Heal" ]
        , button
            [ class "action-btn action-btn--temp"
            , onClick (HpChangeOpen creature.name TempHpKind)
            , Tooltips.attr Tooltips.addTempHp
            ]
            [ text "Temp HP" ]
        , button
            [ class "action-btn action-btn--condition"
            , onClick (ConditionOpenNew creature.name)
            , Tooltips.attr Tooltips.applyCondition
            ]
            [ text "Condition/Effect" ]
        , readiedToggle creature
        , memoSlot creature
        , timerSlot creature
        ]


{-| Row 3 memo slot. Empty memo → 📝 button that opens the
memo-edit modal. Non-empty memo → white-text inline display with
an × dismiss button (clearing the memo restores the icon).
-}
memoSlot : Creature -> Html Msg
memoSlot creature =
    if String.isEmpty creature.memo then
        button
            [ class "action-btn action-btn--icon"
            , onClick (MemoOpen creature.name)
            , Tooltips.attr Tooltips.memoAdd
            , attribute "aria-label" "Add memo"
            ]
            [ text "📝" ]

    else
        span
            [ class "memo-pill"
            , Tooltips.attr creature.memo
            ]
            [ button
                [ class "memo-pill__text"
                , onClick (MemoOpen creature.name)
                , Tooltips.attr Tooltips.memoEdit
                ]
                [ text creature.memo ]
            , button
                [ class "memo-pill__dismiss"
                , onClick (MemoClear creature.name)
                , Tooltips.attr Tooltips.memoClear
                , attribute "aria-label" "Clear memo"
                ]
                [ text "×" ]
            ]


{-| Row 3 timer slot. Three states:

  - No timer set → ⏱ button that opens the timer-setup modal.
  - Timer counting → display the remaining count + × dismiss.
  - Timer ringing (`remaining = 0`) → flashing 0 + × dismiss.
    The browser also plays a ping sound courtesy of the
    page-level `<audio>` element mounted by `View.Audio.ringer`.

-}
timerSlot : Creature -> Html Msg
timerSlot creature =
    case creature.timer of
        Nothing ->
            button
                [ class "action-btn action-btn--icon"
                , onClick (TimerOpen creature.name)
                , Tooltips.attr Tooltips.timerSet
                , attribute "aria-label" "Set timer"
                ]
                [ text "⏱️" ]

        Just t ->
            span
                [ class
                    (if t.ringing then
                        "timer-pill timer-pill--ringing"

                     else
                        "timer-pill"
                    )
                , Tooltips.attr (timerTooltip t)
                ]
                [ span [ class "timer-pill__count" ]
                    [ text (String.fromInt t.remaining) ]
                , if String.isEmpty t.note then
                    text ""

                  else
                    span [ class "timer-pill__note" ] [ text t.note ]
                , button
                    [ class "timer-pill__dismiss"
                    , onClick (TimerDismiss creature.name)
                    , Tooltips.attr Tooltips.timerCancel
                    , attribute "aria-label" "Cancel timer"
                    ]
                    [ text "×" ]
                ]


timerTooltip : Encounter.Timer -> String
timerTooltip t =
    let
        phaseWord =
            case t.phase of
                Encounter.AtBegin ->
                    "begin"

                Encounter.AtEnd ->
                    "end"
    in
    if t.ringing then
        Tooltips.timerRinging phaseWord

    else
        Tooltips.timerRunning
            { remaining = t.remaining
            , phaseWord = phaseWord
            }


readiedToggle : Creature -> Html Msg
readiedToggle creature =
    let
        ( bodyText, cls, label ) =
            if creature.readied then
                ( "✊ Readied"
                , "action-btn action-btn--readied"
                , Tooltips.releaseReadied
                )

            else
                ( "✋ Ready"
                , "action-btn action-btn--ready"
                , Tooltips.readyAction
                )
    in
    button
        [ class cls
        , onClick (ToggleReadied creature.name)
        , Tooltips.attr label
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if creature.readied then
                "true"

             else
                "false"
            )
        ]
        [ text bodyText ]
