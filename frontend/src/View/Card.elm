module View.Card exposing (Context, deathSaveColumn, legendaryColumns, lifecycleBadge, lifecycleClasses, view)

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

import Dict exposing (Dict)
import Effects
import Encounter exposing (Cover(..), Creature)
import Encounter.SaveChain
import Html exposing (Html, article, button, div, input, p, span, text)
import Html.Attributes as Attr exposing (attribute, autofocus, checked, class, id, maxlength, type_, value)
import Html.Events exposing (on, onBlur, onClick, onInput, preventDefaultOn, stopPropagationOn)
import Json.Decode as Decode
import Model exposing (Surface(..))
import Msg
    exposing
        ( HpField(..)
        , Msg(..)
        )
import Set exposing (Set)
import Ui.Condition exposing (ConditionPreset)
import Ui.HpChange exposing (HpChangeEntry, HpEdit)
import Ui.Memo as MemoUi
import Ui.Note as NoteUi
import Ui.PlaceholderRename as Rename exposing (PlaceholderRenameState)
import Ui.SaveChain
import Ui.Timer exposing (TimerPreset)
import View.Inline.Condition
import View.Inline.HpChange
import View.Inline.SaveChain
import View.Inline.Timer
import View.Tooltips as Tooltips


{-| The model fragments a card render needs beyond its own
`Creature`. `surface` powers the inline surfaces: when the open
surface targets this card's creature, the card renders it — as
an expansion under row 3 (HP change, condition) or as an
in-place input where the memo pill / note pencil sits.
-}
type alias Context =
    { activeName : String
    , hpEdit : Maybe HpEdit
    , renameState : Maybe PlaceholderRenameState
    , surface : Maybe Surface
    , selectedCount : Int
    , conditionPresets : Dict String ConditionPreset
    , timerPresets : Dict String TimerPreset
    , saveChainPresets : Dict String Encounter.SaveChain.SaveChain
    , saveChainLog : List Ui.SaveChain.SaveChainLogEntry
    , creatureNames : List String
    , hpChangeLog : List HpChangeEntry
    }


view : Context -> Creature -> Html Msg
view ctx creature =
    let
        hpEdit =
            ctx.hpEdit

        renameState =
            ctx.renameState

        isActive =
            creature.name == ctx.activeName

        cardClass =
            String.join " " ("creature-card" :: lifecycleClasses isActive creature)
    in
    article [ id (Effects.cardId creature.name), class cardClass ]
        [ lifecycleBadge creature
        , div [ class "creature-card__rail creature-card__rail--left" ]
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

                -- Same group as the movers: an open inline editor
                -- makes the card tall, and the rail's space-evenly
                -- distribution would otherwise float this away
                -- from the buttons it belongs with.
                , button
                    [ class "icon-btn icon-btn--accent"
                    , onClick (SetActive creature.name)
                    , Tooltips.attr Tooltips.queueMakeActive
                    , attribute "aria-label" "Make active"
                    ]
                    [ text "→" ]
                ]
            ]
        , div [ class "creature-card__center" ]
            [ rowTop isActive creature hpEdit renameState (surfaceFor ctx creature)
            , rowMid creature hpEdit
            , rowBot creature (surfaceFor ctx creature)
            , inlineSurface ctx creature
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
                    , onClick (QuickAddOpenForReplace creature.name)
                    , Tooltips.attr "Replace creature"
                    , attribute "aria-label" "Replace creature"
                    ]
                    [ text "⇄" ]
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


{-| The open surface, but only when it targets this card's
creature — every inline mount point matches on the result, so
the "which card owns the open surface" question is answered
once.
-}
surfaceFor : Context -> Creature -> Maybe Surface
surfaceFor ctx creature =
    case ctx.surface of
        Just (SurfaceHpChange ui) ->
            if ui.target == creature.name then
                ctx.surface

            else
                Nothing

        Just (SurfaceCondition ui) ->
            if ui.target == creature.name then
                ctx.surface

            else
                Nothing

        Just (SurfaceMemoEdit ui) ->
            if ui.target == creature.name then
                ctx.surface

            else
                Nothing

        Just (SurfaceNoteEdit ui) ->
            if ui.target == creature.name then
                ctx.surface

            else
                Nothing

        Just (SurfaceTimerSetup ui) ->
            if ui.target == creature.name then
                ctx.surface

            else
                Nothing

        Just (SurfaceSaveChain ui) ->
            if ui.target == creature.name then
                ctx.surface

            else
                Nothing

        _ ->
            Nothing


{-| The expansion section under row 3 for the two form-sized
inline surfaces. Memo and note don't render here — they swap
in-place inputs into their row slots instead.
-}
inlineSurface : Context -> Creature -> Html Msg
inlineSurface ctx creature =
    case surfaceFor ctx creature of
        Just (SurfaceHpChange ui) ->
            View.Inline.HpChange.view ctx.selectedCount ctx.hpChangeLog ui

        Just (SurfaceCondition ui) ->
            View.Inline.Condition.view
                { creatureNames = ctx.creatureNames
                , selectedCount = ctx.selectedCount
                , presets = ctx.conditionPresets
                }
                ui

        Just (SurfaceTimerSetup ui) ->
            View.Inline.Timer.view ctx.timerPresets ui

        Just (SurfaceSaveChain ui) ->
            View.Inline.SaveChain.view
                { presets = ctx.saveChainPresets
                , selectedCount = ctx.selectedCount
                , log = ctx.saveChainLog
                }
                ui

        Just (SurfaceMemoEdit ui) ->
            compactEditor
                { title = "Memo"
                , inputValue = ui.text
                , maxLength = MemoUi.maxMemoLength
                , placeholder = "e.g. legendary res used"
                , ariaLabel = "Edit memo for " ++ creature.name
                , onChange = MemoChange
                , commit = MemoCommit
                , cancel = MemoCancel
                }

        Just (SurfaceNoteEdit ui) ->
            compactEditor
                { title = "Note"
                , inputValue = ui.text
                , maxLength = NoteUi.maxNoteLength
                , placeholder = "e.g. boss, summoned, ally"
                , ariaLabel = "Edit note for " ++ creature.name
                , onChange = NoteEditChange
                , commit = NoteEditCommit
                , cancel = NoteEditCancel
                }

        _ ->
            text ""


{-| Lifecycle modifier classes (active / dead / unconscious /
inactive) so both the classic-card and custom-card renderers
classify creatures identically. Order is fixed so a creature
that's BOTH dead and inactive still picks up both classes; CSS
specificity decides which visual wins (`--dead` overrides
`--unconscious` because death implies unconsciousness, and the
left-border / badge picks the most-severe colour).

  - **alive** (no class) — `currentHp > 0`.
  - **unconscious** — `currentHp == 0`, not yet 3 failed death
    saves. Amber border + "DOWN" badge so the GM doesn't lose
    track of a downed creature when the death-save pip strip is
    hidden by default.
  - **dead** — three failed death saves. Red border + 💀 badge,
    plus the existing grayscale / opacity treatment.
  - **inactive** — manually skipped via the ∅ rail toggle. Gray
    border + ⏭ badge.

-}
lifecycleClasses : Bool -> Creature -> List String
lifecycleClasses isActive creature =
    let
        isDead =
            Encounter.isDeathSaveDead creature.deathSaves

        isUnconscious =
            creature.currentHp == 0 && not isDead
    in
    List.filterMap identity
        [ if isActive then
            Just "creature-card--active"

          else
            Nothing
        , if isDead then
            Just "creature-card--dead"

          else if isUnconscious then
            Just "creature-card--unconscious"

          else
            Nothing
        , if creature.inactive then
            Just "creature-card--inactive"

          else
            Nothing
        ]


{-| Top-center status pill that floats above the card.
Renders nothing for alive, active-only creatures so the
encounter queue isn't visually noisy when everyone's healthy.
Inactive wins over unconscious on the label so a manually
skipped downed creature still reads as SKIPPED — that's the
GM's explicit choice.

The DOWN and DEAD variants are both clickable, forming a
reversible toggle on the same physical pill:

  - DOWN → DEAD (`MarkCreatureDead`) sets failures to 3.
  - DEAD → DOWN (`RevertCreatureToDown`) clears failures back
    to 0, preserving any successes the creature already had.

The predicate cascade does the rest — `isDeathSaveDead`
flips, the card class swaps between `--unconscious` and
`--dead`, the badge label and colour follow. SKIPPED stays a
non-interactive div; reversing it goes through the ∅ rail
toggle as before.

-}
lifecycleBadge : Creature -> Html Msg
lifecycleBadge creature =
    let
        isDead =
            Encounter.isDeathSaveDead creature.deathSaves

        isStable =
            Encounter.isDeathSaveStable creature.deathSaves

        baseClass slug =
            "creature-card__lifecycle creature-card__lifecycle--" ++ slug

        ( downLabel, downClass ) =
            -- A creature with three success pips has stabilised
            -- under 5e rules — they're not dying anymore.  Surface
            -- that on the badge so the GM doesn't need to peek at
            -- the pip strip to know the death-save clock stopped.
            -- The button still fires `MarkCreatureDead` because
            -- the GM may still want to mark them dead manually for
            -- narrative reasons; clicking remains the explicit
            -- override path.
            if isStable then
                ( "💤 DOWN, STABLE", "down-stable" )

            else
                ( "💤 DOWN", "down" )
    in
    if creature.inactive then
        div
            [ class (baseClass "inactive")
            , attribute "role" "status"
            ]
            [ text "⏭ SKIPPED" ]

    else if isDead then
        button
            [ class (baseClass "dead")
            , Attr.type_ "button"
            , onClick (RevertCreatureToDown creature.name)
            , Tooltips.attr Tooltips.lifecycleDeadToDown
            , attribute "aria-label"
                ("Mark " ++ creature.name ++ " not dead (revert)")
            ]
            [ text "💀 DEAD" ]

    else if creature.currentHp == 0 then
        button
            [ class (baseClass downClass)
            , Attr.type_ "button"
            , onClick (MarkCreatureDead creature.name)
            , Tooltips.attr Tooltips.lifecycleDownToDead
            , attribute "aria-label"
                ("Mark " ++ creature.name ++ " dead")
            ]
            [ text downLabel ]

    else
        text ""


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


rowTop : Bool -> Creature -> Maybe HpEdit -> Maybe PlaceholderRenameState -> Maybe Surface -> Html Msg
rowTop isActive creature hpEdit renameState surface =
    div [ class "creature-card__row creature-card__row--top" ]
        [ button
            [ class "init-circle init-circle--clickable"
            , onClick (InitiativeOpen creature.name)
            , Tooltips.attr Tooltips.initiativeManager
            , attribute "aria-label"
                ("Initiative " ++ String.fromInt creature.initiative ++ " — open initiative manager")
            ]
            [ text (String.fromInt creature.initiative) ]
        , surprisedIcon creature
        , creatureName creature renameState
        , noteOrPencil creature surface
        , acReadout creature hpEdit
        , rowTopChipCluster isActive creature
        ]


{-| Little surprised-face badge that sits to the left of the
creature name on row 1 when the creature is flagged Surprised.
Cleared automatically at the end of the creature's first turn
by `Encounter.Lifecycle.applyEndOfTurn`.
-}
surprisedIcon : Creature -> Html Msg
surprisedIcon creature =
    if creature.surprised then
        span
            [ class "creature-card__surprised"
            , Tooltips.attr "Surprised — can't take reactions or use legendary actions until the end of their next turn"
            , attribute "aria-label" "Surprised"
            ]
            [ text "😲" ]

    else
        text ""


{-| The creature name on row 1 of each card. Three render modes:

  - Compendium-linked: a `<button>` that pins the source stat
    block in the side panel.
  - Placeholder (name matches `Placeholder N` and no
    compendium link): a clickable `<button>` that opens the
    inline rename — OR, when this creature is currently being
    renamed, an `<input>` whose Enter/blur commits.
  - Legacy seed creatures (no compendium link, name doesn't
    match the placeholder pattern): a plain `<span>`. Unchanged
    behavior.

-}
creatureName : Creature -> Maybe PlaceholderRenameState -> Html Msg
creatureName creature renameState =
    case creature.creatureId of
        Just id_ ->
            -- Clickable name (pins the compendium stat block in
            -- the side panel) is a real `<button>` so keyboard
            -- users can Tab to it and press Enter/Space.  Native
            -- button chrome is reset by the existing
            -- `.creature-name--linked` styling.
            button
                [ class "creature-name creature-name--default creature-name--linked"
                , type_ "button"
                , onClick (PanelShowCreature id_ creature.name)
                , Tooltips.attr Tooltips.showStatBlock
                , attribute "aria-label"
                    ("Pin " ++ creature.name ++ "'s stat block to the side panel")
                ]
                [ text creature.name ]

        Nothing ->
            if creature.isPlaceholder then
                placeholderName creature renameState

            else
                span [ class "creature-name creature-name--default" ]
                    [ text creature.name ]


{-| `Placeholder N` cards: render either a click-to-rename
button or an active rename input depending on whether this
creature is the current rename target.
-}
placeholderName : Creature -> Maybe PlaceholderRenameState -> Html Msg
placeholderName creature renameState =
    case renameState of
        Just state ->
            if state.target == creature.name then
                input
                    [ class "creature-name creature-name--rename-input"
                    , value state.draft
                    , Attr.maxlength Rename.maxNameLength
                    , autofocus True
                    , attribute "aria-label" "Rename placeholder"
                    , onInput PlaceholderRenameChange
                    , onBlur PlaceholderRenameCommit
                    , on "keydown" renameKeyDecoder
                    ]
                    []

            else
                placeholderNameButton creature

        Nothing ->
            placeholderNameButton creature


placeholderNameButton : Creature -> Html Msg
placeholderNameButton creature =
    button
        [ class "creature-name creature-name--default creature-name--linked creature-name--placeholder"
        , type_ "button"
        , onClick (PlaceholderRenameOpen creature.name)
        , Tooltips.attr "Click to rename"
        , attribute "aria-label" ("Rename " ++ creature.name)
        ]
        [ text creature.name ]


{-| Keydown handler for the rename input: Enter commits, Esc
cancels. Other keys flow through to `onInput`.
-}
renameKeyDecoder : Decode.Decoder Msg
renameKeyDecoder =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                case key of
                    "Enter" ->
                        Decode.succeed PlaceholderRenameCommit

                    "Escape" ->
                        Decode.succeed PlaceholderRenameCancel

                    _ ->
                        Decode.fail "ignored"
            )


{-| Note-or-pencil sliver of row 1.

Empty note: just the pencil ✏️ button as an "add a note" affordance.

Non-empty note: the note itself (clickable, starts the edit)
followed by a pipe separator before the AC readout. The pencil is
intentionally hidden in this state — the note is now the click
target, and showing both would make the user wonder which one to
use.

While the note-edit surface targets this creature, the trigger
stays exactly where it is (highlighted, so re-clicking it cancels)
and the input itself renders in a compact strip below the card
rows — the row never reflows around an editor.

-}
noteOrPencil : Creature -> Maybe Surface -> Html Msg
noteOrPencil creature surface =
    let
        editing =
            case surface of
                Just (SurfaceNoteEdit _) ->
                    True

                _ ->
                    False
    in
    if String.isEmpty creature.note then
        button
            [ class (editorTriggerClass "icon-btn icon-btn--sm" editing)
            , onClick (NoteEditOpen creature.name creature.note)
            , Tooltips.attr
                (if editing then
                    Tooltips.inlineEditCancel

                 else
                    Tooltips.noteAdd
                )
            , attribute "aria-label" "Add note"
            , ariaExpanded editing
            ]
            [ text "✏️" ]

    else
        span [ class "creature-note-wrap" ]
            [ button
                [ class (editorTriggerClass "creature-note creature-note--clickable" editing)
                , onClick (NoteEditOpen creature.name creature.note)
                , Tooltips.attr
                    (if editing then
                        Tooltips.inlineEditCancel

                     else
                        Tooltips.noteEdit
                    )
                , attribute "aria-label" ("Edit note: " ++ creature.note)
                , ariaExpanded editing
                ]
                [ text creature.note ]
            , span [ class "creature-note__sep" ] [ text "|" ]
            ]


ariaExpanded : Bool -> Html.Attribute Msg
ariaExpanded expanded =
    attribute "aria-expanded"
        (if expanded then
            "true"

         else
            "false"
        )


{-| Enter commits, Escape cancels — the keyboard contract every
in-place card input shares.
-}
commitCancelKeyDecoder : Msg -> Msg -> Decode.Decoder Msg
commitCancelKeyDecoder commitMsg cancelMsg =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                case key of
                    "Enter" ->
                        Decode.succeed commitMsg

                    "Escape" ->
                        Decode.succeed cancelMsg

                    _ ->
                        Decode.fail "ignored key"
            )


{-| Compact editor strip for the memo and name-note surfaces,
rendered below the card rows so neither row reflows around an
input. Enter or the Add button commits; Escape or re-clicking
the trigger cancels. Deliberately no blur-commit (unlike the
AC / max-HP edits): committing on blur would fire before a
cancel click on the trigger could land, turning every cancel
into a commit.
-}
compactEditor :
    { title : String
    , inputValue : String
    , maxLength : Int
    , placeholder : String
    , ariaLabel : String
    , onChange : String -> Msg
    , commit : Msg
    , cancel : Msg
    }
    -> Html Msg
compactEditor cfg =
    div [ class "creature-card__inline creature-card__inline--compact" ]
        [ span [ class "creature-card__inline-title" ] [ text cfg.title ]
        , input
            [ class "note-edit__input note-edit__input--in-place"
            , type_ "text"
            , value cfg.inputValue
            , maxlength cfg.maxLength
            , Attr.placeholder cfg.placeholder
            , autofocus True
            , onInput cfg.onChange
            , on "keydown" (commitCancelKeyDecoder cfg.commit cfg.cancel)
            , attribute "aria-label" cfg.ariaLabel
            ]
            []
        , button
            [ class "action-btn action-btn--green"
            , onClick cfg.commit
            ]
            [ text "Add" ]
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
    let
        hasLA =
            creature.legendaryActionsCount > 0

        hasLR =
            creature.legendaryResistanceCount > 0
    in
    if not hasLA && not hasLR then
        text ""

    else
        div [ class "creature-card__legendary" ]
            [ if hasLA then
                legendaryColumn
                    { creatureName = creature.name
                    , kind = "la"
                    , label = "LA"
                    , baseCount = creature.legendaryActionsCount
                    , lairBonus = creature.legendaryActionsLairBonus
                    , used = creature.legendaryActionsUsed
                    , onToggle = ToggleLegendaryActionPip creature.name
                    }

              else
                text ""
            , if hasLR then
                legendaryColumn
                    { creatureName = creature.name
                    , kind = "lr"
                    , label = "LR"
                    , baseCount = creature.legendaryResistanceCount
                    , lairBonus = creature.legendaryResistanceLairBonus
                    , used = creature.legendaryResistanceUsed
                    , onToggle = ToggleLegendaryResistancePip creature.name
                    }

              else
                text ""
            ]


{-| One recharge-ability pill, sized to match the condition-chip
shape so it sits inline in row 1's chip cluster.

Three states:

  - **Ready** — green pill with the ability name + range. Click
    marks it spent (in case the GM resolves it manually).
  - **Spent on a non-active creature** — muted-gray pill,
    strikethrough. Click toggles back to ready (GM correction).
  - **Spent + active + `awaitingRoll`** — the prompt state.
    The pill splits into a clickable 🎲 (blinking) on the
    left, a `|` divider, and the ability name on the right.
    Clicking the dice fires the recharge d6 via
    `RollRechargeNow`; clicking the name resets the ability
    to ready without rolling. The `awaitingRoll` flag is
    flipped on by the begin-of-turn lifecycle hook, so
    spending an ability mid-turn does NOT raise the prompt
    on the same turn — the dice doesn't appear until the
    creature's next turn starts.

The recharge d6 used to auto-roll at the start of the
creature's turn; the active-spent prompt replaces that so the
GM gets to time the roll themselves.

-}
rechargeChip : Bool -> String -> Encounter.RechargeAbility -> Html Msg
rechargeChip isActive bearer ability =
    let
        rangeLabel =
            if ability.low == ability.high then
                String.fromInt ability.low

            else
                String.fromInt ability.low ++ "–" ++ String.fromInt ability.high
    in
    if not ability.ready && isActive && ability.awaitingRoll then
        rechargePromptChip bearer ability rangeLabel

    else
        rechargeStaticChip ability rangeLabel bearer


{-| Default chip rendering for ready (green) and spent-but-
inactive (muted) states. Single button, click toggles.
-}
rechargeStaticChip : Encounter.RechargeAbility -> String -> String -> Html Msg
rechargeStaticChip ability rangeLabel bearer =
    let
        stateModifier =
            if ability.ready then
                "recharge-chip--ready"

            else
                "recharge-chip--spent"

        tip =
            if ability.ready then
                ability.name ++ " — Recharge " ++ rangeLabel ++ " (ready; click to mark spent)"

            else
                ability.name ++ " — Recharge " ++ rangeLabel ++ " (spent; click to mark ready)"
    in
    button
        [ class ("recharge-chip " ++ stateModifier)
        , Attr.type_ "button"
        , onClick (ToggleRechargeAbility bearer ability.name)
        , Tooltips.attr tip
        , attribute "aria-label" tip
        , attribute "aria-pressed"
            (if ability.ready then
                "false"

             else
                "true"
            )
        ]
        [ text ability.name
        , span [ class "recharge-chip__range" ] [ text (" " ++ rangeLabel) ]
        ]


{-| The active-creature prompt: blinking 🎲 (roll) | name (reset).
The two clickable halves are independent <button>s wrapped in a
shared chip container so they share the pill's borders + tint.
-}
rechargePromptChip : String -> Encounter.RechargeAbility -> String -> Html Msg
rechargePromptChip bearer ability rangeLabel =
    let
        rollTip =
            "Roll Recharge " ++ rangeLabel ++ " for " ++ ability.name

        readyTip =
            "Mark " ++ ability.name ++ " ready (no roll)"
    in
    span [ class "recharge-chip recharge-chip--prompt" ]
        [ button
            [ class "recharge-chip__dice"
            , Attr.type_ "button"
            , onClick (RollRechargeNow bearer ability.name)
            , Tooltips.attr rollTip
            , attribute "aria-label" rollTip
            ]
            [ text "🎲" ]
        , span [ class "recharge-chip__pipe" ] [ text "|" ]
        , button
            [ class "recharge-chip__name-btn"
            , Attr.type_ "button"
            , onClick (ToggleRechargeAbility bearer ability.name)
            , Tooltips.attr readyTip
            , attribute "aria-label" readyTip
            ]
            [ text ability.name
            , span [ class "recharge-chip__range" ] [ text (" " ++ rangeLabel) ]
            ]
        ]


legendaryColumn :
    { creatureName : String
    , kind : String
    , label : String
    , baseCount : Int
    , lairBonus : Int
    , used : Set Int
    , onToggle : Int -> Msg
    }
    -> Html Msg
legendaryColumn cfg =
    let
        pip { idx, isLair } =
            let
                filled =
                    Set.member idx cfg.used

                lairTip =
                    if isLair then
                        ": Lair bonus"

                    else
                        ""
            in
            button
                [ class
                    ("legendary-col__pip"
                        ++ (if filled then
                                " legendary-col__pip--filled"

                            else
                                ""
                           )
                        ++ (if isLair then
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
                        ++ lairTip
                        ++ (if filled then
                                " (used)"

                            else
                                " (available)"
                           )
                    )
                , attribute "aria-label"
                    (cfg.label
                        ++ " pip "
                        ++ String.fromInt (idx + 1)
                        ++ (if isLair then
                                " (lair bonus)"

                            else
                                ""
                           )
                    )
                , attribute "aria-pressed"
                    (if filled then
                        "true"

                     else
                        "false"
                    )
                ]
                []

        basePips =
            List.range 0 (cfg.baseCount - 1)
                |> List.map (\i -> pip { idx = i, isLair = False })

        lairPips =
            if cfg.lairBonus > 0 then
                List.range cfg.baseCount (cfg.baseCount + cfg.lairBonus - 1)
                    |> List.map (\i -> pip { idx = i, isLair = True })

            else
                []

        separator =
            if cfg.lairBonus > 0 then
                [ div [ class "legendary-col__sep" ] [] ]

            else
                []
    in
    div [ class ("legendary-col legendary-col--" ++ cfg.kind) ]
        (div
            [ class "legendary-col__header"
            , Tooltips.attr (headerTooltipFor cfg.label)
            ]
            [ text cfg.label ]
            :: basePips
            ++ separator
            ++ lairPips
        )


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


{-| Row 1 chip cluster: a single `flex: 1 1 auto` container that
holds the condition / save-notice chips followed immediately by
the recharge chips, separated by a leading pipe. Combining them
into one wrap (rather than two siblings) keeps the recharge chip
hugged to the right of the condition chips instead of getting
pushed to the row's far edge by the wrap's flex-grow.

Renders nothing if the creature has neither conditions nor save
notices nor recharge abilities, so the row collapses cleanly for
PCs and most NPCs.

-}
rowTopChipCluster : Bool -> Creature -> Html Msg
rowTopChipCluster isActive creature =
    let
        hasAnyChip =
            not (List.isEmpty creature.conditions)
                || not (List.isEmpty creature.saveNotices)
                || not (List.isEmpty creature.rechargeAbilities)
    in
    if not hasAnyChip then
        text ""

    else
        span [ class "condition-chips-wrap" ]
            (span [ class "row-top__sep" ] [ text "|" ]
                :: List.map (rechargeChip isActive creature.name) creature.rechargeAbilities
                ++ List.map (conditionChip creature.name) creature.conditions
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


{-| One condition chip. Visible text is just the condition name +
optional `(note)`; per the release-polish pass the duration glyph
and the chip body itself stay minimal. Two action affordances sit
inside the chip:

  - The 🎲 save-roll button — only when the condition has a
    `saveToEnd` spec. Fires a 1d20 vs. the DC and removes the
    condition silently on success.
  - The × remove button — always present. One-click chip removal
    without opening the edit modal.

Both action buttons `stopPropagationOn "click"` so they don't
also bubble up and open the edit modal (which the chip name
itself triggers). The hover tooltip on the chip wrap composes
the full duration + save terms via `chipTitle`.

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
inline "+N" temp-HP marker when the creature is buffed. All three
values — current, max, and temp — are click-to-edit: clicking
swaps the value for a small `<input>` (autofocus + onBlur
commits, Enter commits, Esc cancels). Temp HP commits to a
direct GM override (`HpChange.setTempHp`), bypassing the
replace-if-higher rule that the Temp HP modal applies — that way
typing `0` here clears the temp pool, which is what a GM
clicking the chip generally wants.
-}
hpDisplay : Creature -> Maybe HpEdit -> Html Msg
hpDisplay creature hpEdit =
    span [ class "hp-display" ]
        [ hpEditable creature hpEdit CurrentHpField creature.currentHp "hp-display__current"
        , span [ class "hp-display__sep" ] [ text "/" ]
        , hpEditable creature hpEdit MaxHpField creature.maxHp "hp-display__max"
        , maxHpOriginal creature
        , tempHpEditable creature hpEdit
        ]


{-| Muted "(N)" hint after Max HP when the current value has
been changed from the baseline the creature entered the
encounter with. Nothing renders when the two match — the
common case for freshly-added compendium instances — so the
row stays quiet until the GM has actually mutated the pool.
-}
maxHpOriginal : Creature -> Html Msg
maxHpOriginal creature =
    if creature.originalMaxHp /= creature.maxHp && creature.originalMaxHp > 0 then
        span
            [ class "hp-display__max-orig"
            , Tooltips.attr
                ("Original max HP when added to the encounter: "
                    ++ String.fromInt creature.originalMaxHp
                )
            ]
            [ text (" (" ++ String.fromInt creature.originalMaxHp ++ ")") ]

    else
        text ""


{-| Click-to-edit affordance for the temp-HP chip. Mirrors
`hpEditable`, but only renders when temp HP is non-zero (zero
temp is the absence of a buff — no chip in the row), and the
display reads "+N" instead of the bare integer so the chip
keeps its established "this is a bonus pool" shape.
-}
tempHpEditable : Creature -> Maybe HpEdit -> Html Msg
tempHpEditable creature hpEdit =
    let
        isEditing =
            case hpEdit of
                Just e ->
                    e.target == creature.name && e.field == TempHpField

                Nothing ->
                    False
    in
    if isEditing then
        input
            [ class "hp-display__edit hp-display__edit--temp"
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

    else if creature.tempHp > 0 then
        button
            [ class "hp-display__temp hp-display__editable"
            , type_ "button"
            , onClick (HpEditStart creature.name TempHpField creature.tempHp)
            , Tooltips.attr Tooltips.tempHp
            , attribute "aria-label"
                (hpFieldAriaLabel TempHpField creature.name creature.tempHp)
            ]
            [ text ("+" ++ String.fromInt creature.tempHp) ]

    else
        text ""


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
        -- Trigger is a real `<button>` (not a `<span onClick>`) so
        -- keyboard users can Tab to it and press Enter/Space to
        -- enter edit mode.  The styling stays the same via the
        -- existing `.hp-display__editable` class — CSS resets the
        -- native button chrome.
        button
            [ class (cls ++ " hp-display__editable")
            , type_ "button"
            , onClick (HpEditStart creature.name field current)
            , Tooltips.attr Tooltips.clickToEdit
            , attribute "aria-label"
                (hpFieldAriaLabel field creature.name current)
            ]
            [ text (String.fromInt current) ]


{-| Screen-reader label for the inline HP / AC edit trigger.
SR users hear the field role + current value + creature name
when focus lands on the trigger, so they know what they're about
to edit.
-}
hpFieldAriaLabel : HpField -> String -> Int -> String
hpFieldAriaLabel field name current =
    let
        fieldName =
            case field of
                CurrentHpField ->
                    "Current HP"

                MaxHpField ->
                    "Max HP"

                ArmorClassField ->
                    "Armor Class"

                TempHpField ->
                    "Temporary HP"
    in
    fieldName
        ++ " "
        ++ String.fromInt current
        ++ " for "
        ++ name
        ++ ", click to edit"


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

    else if not creature.acceptingDeathSaves then
        -- Opt-in button.  Most downed enemies never need to roll
        -- death saves (the DM just narrates them dead), so the
        -- pip strip stays hidden until the GM explicitly asks
        -- for it.  Click flips `acceptingDeathSaves = True` and
        -- the full tracker renders on the next pass.
        div [ class "death-save-cols death-save-cols--opt-in" ]
            [ button
                [ class "death-save-cols__begin"
                , onClick (DeathSavesBegin creature.name)
                , Tooltips.attr Tooltips.deathBegin
                , attribute "aria-label" "Begin death saving throws"
                ]
                [ text "Death Saves" ]
            ]

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
in the card buys horizontal space in row 2. The `○` prefix in the
off state replaces the older "not " / "no " wording so the off
state stays visually distinct without needing an icon glyph.
The subtler outlined circle reads as "unlit" without shouting
"prohibited" the way the previous 🚫 emoji did.
-}
boolToggle : String -> String -> Bool -> Msg -> Html Msg
boolToggle _ label isOn msg =
    let
        ( dotGlyph, dotClass, cls ) =
            if isOn then
                ( "●"
                , "status-toggle__dot status-toggle__dot--on"
                , "status-toggle status-toggle--on"
                )

            else
                ( "○"
                , "status-toggle__dot"
                , "status-toggle"
                )

        tip =
            if isOn then
                Tooltips.statusOnTip label

            else
                Tooltips.statusOffTip label
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
        [ span [ class dotClass ] [ text dotGlyph ]
        , text (" " ++ label)
        ]


coverToggle : Creature -> Html Msg
coverToggle creature =
    let
        ( dotGlyph, dotClass ) =
            case creature.cover of
                NoCover ->
                    ( "○", "status-toggle__dot" )

                _ ->
                    ( "●", "status-toggle__dot status-toggle__dot--on" )

        ( bodyText, label, modifier ) =
            case creature.cover of
                NoCover ->
                    ( "cover", "No cover", "status-toggle--off" )

                HalfCover ->
                    ( "½ cover", "Half cover", "status-toggle--on" )

                ThreeQuartersCover ->
                    ( "¾ cover", "Three-quarters cover", "status-toggle--on" )

                FullCover ->
                    ( "total cover", "Total cover", "status-toggle--on" )
    in
    button
        [ class ("status-toggle " ++ modifier)
        , onClick (CycleCover creature.name)
        , Tooltips.attr (Tooltips.coverCycleTip label)
        , attribute "aria-label" ("Cover: " ++ label)
        ]
        [ span [ class dotClass ] [ text dotGlyph ]
        , text (" " ++ bodyText)
        ]


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


rowBot : Creature -> Maybe Surface -> Html Msg
rowBot creature surface =
    let
        hpEditing =
            case surface of
                Just (SurfaceHpChange _) ->
                    True

                _ ->
                    False

        conditionEditing =
            case surface of
                Just (SurfaceCondition _) ->
                    True

                _ ->
                    False

        saveChainEditing =
            case surface of
                Just (SurfaceSaveChain _) ->
                    True

                _ ->
                    False
    in
    div [ class "creature-card__row creature-card__row--bot" ]
        [ button
            [ class (editorTriggerClass "action-btn action-btn--manage-hp" hpEditing)
            , onClick (HpChangeOpen creature.name)
            , Tooltips.attr
                (if hpEditing then
                    Tooltips.inlineEditCancel

                 else
                    Tooltips.manageHp
                )
            , ariaExpanded hpEditing
            ]
            [ text "Manage HP" ]
        , button
            [ class (editorTriggerClass "action-btn action-btn--condition" conditionEditing)
            , onClick (ConditionOpenNew creature.name)
            , Tooltips.attr
                (if conditionEditing then
                    Tooltips.inlineEditCancel

                 else
                    Tooltips.applyCondition
                )
            , ariaExpanded conditionEditing
            ]
            [ text "Condition/Effect" ]
        , button
            [ class (editorTriggerClass "action-btn action-btn--save-chain" saveChainEditing)
            , onClick (SaveChainOpen creature.name)
            , Tooltips.attr
                (if saveChainEditing then
                    Tooltips.inlineEditCancel

                 else
                    Tooltips.saveChain
                )
            , ariaExpanded saveChainEditing
            ]
            [ text "Save Chain" ]
        , readiedToggle creature
        , reactionPip creature
        , memoSlot creature surface
        , timerSlot creature surface
        ]


{-| Append the open-editor highlight to a trigger's class list
while its own editor is expanded, so the GM can spot which
editor is open even after scrolling away and back.
-}
editorTriggerClass : String -> Bool -> String
editorTriggerClass base editing =
    if editing then
        base ++ " card-editor-open"

    else
        base


{-| Row 3 memo slot. Empty memo → 📝 button that starts the
edit. Non-empty memo → white-text inline display with an ×
dismiss button (clearing the memo restores the icon).

While the memo-edit surface targets this creature, the slot
stays exactly where it is (highlighted, so re-clicking it
cancels) and the input renders in a compact strip below the
card rows — the button row never reflows around an editor.

-}
memoSlot : Creature -> Maybe Surface -> Html Msg
memoSlot creature surface =
    let
        editing =
            case surface of
                Just (SurfaceMemoEdit _) ->
                    True

                _ ->
                    False
    in
    if String.isEmpty creature.memo then
        button
            [ class (editorTriggerClass "action-btn action-btn--icon action-btn--memo-empty" editing)
            , onClick (MemoOpen creature.name)
            , Tooltips.attr
                (if editing then
                    Tooltips.inlineEditCancel

                 else
                    Tooltips.memoAdd
                )
            , attribute "aria-label" "Add memo"
            , ariaExpanded editing
            ]
            [ span [ class "action-btn__icon" ] [ text "📝" ]
            , span [ class "action-btn__text" ] [ text "Memo" ]
            ]

    else
        memoPill creature editing


memoPill : Creature -> Bool -> Html Msg
memoPill creature editing =
    span
        [ class (editorTriggerClass "memo-pill" editing)
        , Tooltips.attr creature.memo
        ]
        [ button
            [ class "memo-pill__text"
            , onClick (MemoOpen creature.name)
            , Tooltips.attr
                (if editing then
                    Tooltips.inlineEditCancel

                 else
                    Tooltips.memoEdit
                )
            , ariaExpanded editing
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
timerSlot : Creature -> Maybe Surface -> Html Msg
timerSlot creature surface =
    let
        editing =
            case surface of
                Just (SurfaceTimerSetup _) ->
                    True

                _ ->
                    False
    in
    case creature.timer of
        Nothing ->
            button
                [ class (editorTriggerClass "action-btn action-btn--icon action-btn--timer-empty" editing)
                , onClick (TimerOpen creature.name)
                , Tooltips.attr
                    (if editing then
                        Tooltips.inlineEditCancel

                     else
                        Tooltips.timerSet
                    )
                , attribute "aria-label" "Set timer"
                , ariaExpanded editing
                ]
                [ span [ class "action-btn__icon" ] [ text "⏱️" ]
                , span [ class "action-btn__text" ] [ text "Timer" ]
                ]

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
        ( iconGlyph, wordLabel, cls ) =
            if creature.readied then
                ( "✊", "Readied", "action-btn action-btn--readied" )

            else
                ( "✋", "Ready", "action-btn action-btn--ready" )

        tooltip =
            if creature.readied then
                Tooltips.releaseReadied

            else
                Tooltips.readyAction
    in
    button
        [ class cls
        , onClick (ToggleReadied creature.name)
        , Tooltips.attr tooltip
        , attribute "aria-label" tooltip
        , attribute "aria-pressed"
            (if creature.readied then
                "true"

             else
                "false"
            )
        ]
        -- Icon prefix wrapped in its own span so the Accessible
        -- theme can drop the unicode glyph and let the word stand
        -- on its own.  Modern / Dark leave the span visible.
        [ span [ class "action-btn__icon-prefix" ] [ text (iconGlyph ++ " ") ]
        , text wordLabel
        ]


{-| One-per-round reaction pip. ⚡ when available, gray ⚡ when
expended. When the source creature has `hasSpecialReactions =
True`, the lightning glyph is replaced with a bold yellow `!`
and the tooltip points the GM at the stat block — the standard
single-reaction UX can't model Hydra's extra heads, Marilith's
per-turn reactions, Vampire's Misty Escape, etc.

Mirrors the legendary-resistance pip pattern but with a single
slot. Auto-resets at the start of the creature's next turn via
`Encounter.Lifecycle.applyBeginOfTurn`; the click is wired
manually so the GM can flip it ad-hoc.

-}
reactionPip : Creature -> Html Msg
reactionPip creature =
    let
        ( baseCls, tooltip ) =
            if creature.reactionUsed then
                ( "action-btn action-btn--reaction action-btn--reaction-spent"
                , Tooltips.reactionSpent
                )

            else
                ( "action-btn action-btn--reaction action-btn--reaction-ready"
                , Tooltips.reactionReady
                )

        cls =
            if creature.hasSpecialReactions then
                baseCls ++ " action-btn--reaction-special"

            else
                baseCls

        ( iconGlyph, iconTooltip ) =
            if creature.hasSpecialReactions then
                ( "! ", "Special reaction mechanics (see stat block)" )

            else
                ( "⚡ ", tooltip )
    in
    button
        [ class cls
        , onClick (ToggleReaction creature.name)
        , Tooltips.attr iconTooltip
        , attribute "aria-label" iconTooltip
        , attribute "aria-pressed"
            (if creature.reactionUsed then
                "true"

             else
                "false"
            )
        ]
        -- Same icon-prefix split as `readiedToggle` so the
        -- Accessible theme hides the glyph and the word
        -- "Reaction" stands on its own.
        [ span [ class "action-btn__icon-prefix" ] [ text iconGlyph ]
        , text "Reaction"
        ]
