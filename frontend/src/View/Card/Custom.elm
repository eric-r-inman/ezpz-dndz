module View.Card.Custom exposing (view)

{-| **Prototype** layout-driven creature card for the running
encounter.

Where [`View.Card`](View-Card) renders a fixed three-row + two-
rail structure, this renderer walks `model.cardLayout` and
dispatches each widget through [`renderWidget`](#renderWidget).
Same outer chrome classes (`.creature-card`, `--active`,
`--dead`, `--inactive`) so the encounter panel's `.creature-grid`
styles still apply.

Interactivity coverage in this prototype:

  - **Action buttons** (Damage / Heal / Temp HP / Condition)
    fire their respective `HpChangeOpen` / `ConditionOpenNew`
    Msgs identically to the classic card.
  - **Status toggles** (cover, concentrating, hiding, dodging,
    flying, readied action, skip) fire their `Toggle*` Msgs.
  - **Row controls** (×, ⧉, ∅, panel pin, selection checkbox)
    fire their respective Msgs.
  - **Memo / Timer slots** fire open / dismiss Msgs.
  - **HP / AC / inline edit** are read-only — the click-to-edit
    machinery from `View.Card` is not yet ported. GMs adjust
    HP via the Damage / Heal / Temp HP modals.
  - **Death saves + LA / LR pip strips** render the current
    pip state but the pips are display-only (no click-to-roll).

The prototype's "Coming soon" pills from
[`Card.Preview`](Card-Preview) don't apply here — every widget
has at least a render, even if some are read-only.

-}

import Card.Layout as Layout
    exposing
        ( CardLayout
        , CardRow
        , CardWidget(..)
        , RowAlignment(..)
        )
import Char
import Compendium
import Effects
import Encounter
    exposing
        ( Condition
        , Cover(..)
        , Creature
        , Timer
        )
import Encounter.DeathSaves as DeathSaves
import Html
    exposing
        ( Html
        , article
        , button
        , div
        , input
        , span
        , text
        )
import Html.Attributes as Attr
    exposing
        ( attribute
        , checked
        , class
        , id
        , type_
        )
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import Set
import Ui.HpChange exposing (HpEdit)
import View.Card
import View.Tooltips as Tooltips



-- ── ENTRY ────────────────────────────────────────────────────────────────────


view : CardLayout -> String -> Maybe HpEdit -> Compendium.Db -> Creature -> Html Msg
view layout activeName _ db creature =
    let
        isActive =
            creature.name == activeName

        cardClass =
            String.join " "
                ("creature-card"
                    :: "creature-card--custom"
                    :: View.Card.lifecycleClasses isActive creature
                )
    in
    article
        [ id (Effects.cardId creature.name), class cardClass ]
        (View.Card.lifecycleBadge creature :: renderColumns db creature layout)


{-| Render the five-column shell. Left rail, right rail, and
the two side columns are HARDCODED structural slots — the layout
data only controls the centre rows and whether the side columns
appear. This matches the non-custom card's geometry exactly and
keeps the always-present icons (move / select / make-active /
×, inactive, replace, duplicate, panel pin) immune to the
customisation editor.
-}
renderColumns : Compendium.Db -> Creature -> CardLayout -> List (Html Msg)
renderColumns db creature layout =
    List.filterMap identity
        [ Just (leftRail db creature)
        , Just
            (div [ class "creature-card-custom__center" ]
                (List.map (renderRow db creature) layout.centerRows)
            )
        , if layout.deathSavesEnabled then
            Just (View.Card.deathSaveColumn creature)

          else
            Nothing
        , if layout.legendaryEnabled then
            Just (View.Card.legendaryColumns creature)

          else
            Nothing
        , Just (rightRail db creature)
        ]


leftRail : Compendium.Db -> Creature -> Html Msg
leftRail db creature =
    div [ class "creature-card-custom__rail creature-card-custom__rail--left" ]
        [ renderWidget db creature WidgetSelectCheckbox
        , renderWidget db creature WidgetMoveUpButton
        , renderWidget db creature WidgetMoveDownButton
        , renderWidget db creature WidgetMakeActiveButton
        ]


rightRail : Compendium.Db -> Creature -> Html Msg
rightRail db creature =
    -- Panel-pin icon is intentionally omitted; clicking the
    -- creature name (via WidgetName) already pins the stat
    -- block in the side panel, so a separate pushpin would be
    -- a redundant control.
    div [ class "creature-card-custom__rail creature-card-custom__rail--right" ]
        [ renderWidget db creature WidgetRemoveButton
        , renderWidget db creature WidgetSkipToggle
        , renderWidget db creature WidgetReplaceButton
        , renderWidget db creature WidgetDuplicateButton
        ]



-- ── ROWS ─────────────────────────────────────────────────────────────────────


renderRow : Compendium.Db -> Creature -> CardRow -> Html Msg
renderRow db creature row =
    div
        [ class
            ("creature-card-custom__row "
                ++ alignmentClass row.alignment
            )
        ]
        (List.map (renderWidget db creature) row.widgets)


alignmentClass : RowAlignment -> String
alignmentClass a =
    case a of
        AlignLeft ->
            "creature-card-custom__row--align-left"

        AlignCenter ->
            "creature-card-custom__row--align-center"

        AlignRight ->
            "creature-card-custom__row--align-right"

        AlignSpaceBetween ->
            "creature-card-custom__row--align-space-between"



-- ── WIDGET DISPATCH ──────────────────────────────────────────────────────────


renderWidget : Compendium.Db -> Creature -> CardWidget -> Html Msg
renderWidget db creature widget =
    case widget of
        WidgetName ->
            -- Reuses the non-custom `.creature-name` /
            -- `.creature-name--linked` class chain so every theme
            -- override (font size, weight, hover underline) the
            -- non-custom card uses applies here for free.
            case creature.creatureId of
                Just cid ->
                    button
                        [ class "creature-name creature-name--default creature-name--linked"
                        , type_ "button"
                        , onClick (PanelShowCreature cid creature.name)
                        , Tooltips.attr Tooltips.showStatBlock
                        , attribute "aria-label"
                            ("Pin " ++ creature.name ++ "'s stat block to the side panel")
                        ]
                        [ text creature.name ]

                Nothing ->
                    span [ class "creature-name creature-name--default" ]
                        [ text creature.name ]

        WidgetArmorClass ->
            -- Same `.ac-readout` shell + `__value` inner as the
            -- non-custom card — theme tokens drive colour /
            -- weight / size so the AC chip matches at every
            -- breakpoint.
            span [ class "ac-readout" ]
                [ text "AC: "
                , span [ class "ac-readout__value" ]
                    [ text (String.fromInt creature.armorClass) ]
                ]

        WidgetHitPoints ->
            -- `.hp-display__current` resolves to green; `__max`
            -- to muted text-colour; the slash separator inherits
            -- the row's text colour.  Matches the non-custom row 2
            -- HP cluster exactly.
            span [ class "hp-display" ]
                [ span [ class "hp-display__current" ]
                    [ text (String.fromInt creature.currentHp) ]
                , span [ class "hp-display__sep" ] [ text "/" ]
                , span [ class "hp-display__max" ]
                    [ text (String.fromInt creature.maxHp) ]
                ]

        WidgetTempHp ->
            if creature.tempHp > 0 then
                span [ class "hp-display__temp" ]
                    [ text ("+" ++ String.fromInt creature.tempHp) ]

            else
                text ""

        WidgetInitiative ->
            -- Match the non-custom init pill: a circular outlined
            -- button rendered via `.init-circle`.  Click to open
            -- the initiative manager modal.
            button
                [ class "init-circle init-circle--clickable"
                , onClick (InitiativeOpen creature.name)
                , Tooltips.attr Tooltips.initiativeManager
                , attribute "aria-label"
                    ("Initiative "
                        ++ String.fromInt creature.initiative
                        ++ " — open initiative manager"
                    )
                ]
                [ text (String.fromInt creature.initiative) ]

        WidgetKindBadge ->
            -- Player / Enemy / NPC chip, sourced from the
            -- structured `creatureKind` field (lowercase token).
            -- Placeholder creatures show as NPC per the project
            -- convention (set in `Encounter.Roster.freshPlaceholder`).
            span [ class ("creature-card-custom__chip creature-card-custom__chip--kind-" ++ creature.creatureKind) ]
                [ text (kindBadgeLabel creature.creatureKind) ]

        WidgetTypeBadge ->
            if String.isEmpty creature.race then
                text ""

            else
                span [ class "creature-card-custom__chip creature-card-custom__chip--type" ]
                    [ text creature.race ]

        WidgetAlignmentBadge ->
            if String.isEmpty creature.alignment then
                text ""

            else
                span [ class "creature-card-custom__chip creature-card-custom__chip--alignment" ]
                    [ text (toTitleCase creature.alignment) ]

        WidgetConditions ->
            if List.isEmpty creature.conditions then
                text ""

            else
                span [ class "condition-chips-wrap" ]
                    (List.map conditionChip creature.conditions)

        WidgetBloodied ->
            if creature.bloodied || creature.currentHp <= creature.maxHp // 2 then
                span [ class "bloodied" ] [ text "🩸" ]

            else
                text ""

        WidgetCoverToggle ->
            -- Reuse the non-custom status-toggle skin so the
            -- "no cover" / "1/2" / "3/4" / "full" cycler reads
            -- the same way as the matching button on the card.
            button
                [ class "status-toggle status-toggle--off"
                , onClick (CycleCover creature.name)
                , attribute "aria-label" "Cycle cover state"
                ]
                [ text ("🛡 " ++ coverLabel creature.cover) ]

        WidgetConcentrating ->
            statusToggle creature
                creature.concentrating
                "🧠"
                (ToggleConcentration creature.name)

        WidgetHiding ->
            statusToggle creature
                creature.hiding
                "👤"
                (ToggleHiding creature.name)

        WidgetDodging ->
            statusToggle creature
                creature.dodging
                "🤸"
                (ToggleDodging creature.name)

        WidgetFlying ->
            statusToggle creature
                creature.flying
                "🪽"
                (ToggleFlying creature.name)

        WidgetReadiedAction ->
            statusToggle creature
                creature.readied
                "⏸"
                (ToggleReadied creature.name)

        WidgetMemoSlot ->
            -- Empty memo → small icon button with Accessible
            -- "Memo" text swap (see action-btn--memo-empty).
            -- Populated memo → memo-pill matching the non-custom
            -- card's pill shape and theme colours.
            if String.isEmpty creature.memo then
                button
                    [ class "action-btn action-btn--icon action-btn--memo-empty"
                    , onClick (MemoOpen creature.name)
                    , attribute "aria-label" "Add memo"
                    ]
                    [ span [ class "action-btn__icon" ] [ text "📝" ]
                    , span [ class "action-btn__text" ] [ text "Memo" ]
                    ]

            else
                span [ class "memo-pill" ]
                    [ button
                        [ class "memo-pill__text"
                        , onClick (MemoOpen creature.name)
                        ]
                        [ text creature.memo ]
                    , button
                        [ class "memo-pill__dismiss"
                        , onClick (MemoClear creature.name)
                        , attribute "aria-label" "Clear memo"
                        ]
                        [ text "×" ]
                    ]

        WidgetTimerSlot ->
            case creature.timer of
                Just t ->
                    span [ class "timer-pill" ]
                        [ span [ class "timer-pill__count" ]
                            [ text (String.fromInt t.remaining) ]
                        , button
                            [ class "timer-pill__dismiss"
                            , onClick (TimerDismiss creature.name)
                            , attribute "aria-label" "Cancel timer"
                            ]
                            [ text "×" ]
                        ]

                Nothing ->
                    button
                        [ class "action-btn action-btn--icon action-btn--timer-empty"
                        , onClick (TimerOpen creature.name)
                        , attribute "aria-label" "Set timer"
                        ]
                        [ span [ class "action-btn__icon" ] [ text "⏱️" ]
                        , span [ class "action-btn__text" ] [ text "Timer" ]
                        ]

        -- Damage / Heal / Temp HP widgets are legacy per-verb
        -- entry points from before the modal was merged.  They
        -- now all open the same Manage HP modal — the button
        -- label still reflects the widget the GM dropped on
        -- their custom layout, but the modal handles all four
        -- kinds so the click still lands where they expect.
        WidgetDamageButton ->
            actionBtn "Damage"
                "action-btn--damage"
                (HpChangeOpen creature.name)

        WidgetHealButton ->
            actionBtn "Heal"
                "action-btn--heal"
                (HpChangeOpen creature.name)

        WidgetTempHpButton ->
            actionBtn "Temp HP"
                "action-btn--temp"
                (HpChangeOpen creature.name)

        WidgetConditionButton ->
            actionBtn "Condition"
                "action-btn--condition"
                (ConditionOpenNew creature.name)

        WidgetDeathSaves ->
            -- Delegated to the same `View.Card.deathSaveColumn`
            -- helper the non-custom card uses so the markup +
            -- styling stay identical (side-by-side success +
            -- failure pip columns + footer dice / 🛡 / 💀).
            View.Card.deathSaveColumn creature

        WidgetLegendaryActions ->
            -- Delegated to `View.Card.legendaryColumns`, which
            -- renders the LA + LR side-by-side pair (each with
            -- 3 standard pips + a lair-bonus 4th pip below a
            -- separator).  The helper already gates on the
            -- creature's `hasLegendaryActions / Resistance`
            -- flags, so there's no extra work here.
            View.Card.legendaryColumns creature

        WidgetLegendaryResistance ->
            -- Same helper as `WidgetLegendaryActions`; it draws
            -- both LA + LR.  Rendered once via the side-column
            -- slot in `renderColumns`, so this widget-level case
            -- only matters when a user places it inside a centre
            -- row (legacy layouts).  Calling the helper twice
            -- (once per widget) would draw duplicate columns; we
            -- rely on `renderColumns` calling the helper directly
            -- and the widget catalogue filter to exclude this
            -- variant from the editor picker.
            text ""

        WidgetSkipToggle ->
            iconBtn
                (if creature.inactive then
                    "icon-btn icon-btn--toggled"

                 else
                    "icon-btn"
                )
                "∅"
                (if creature.inactive then
                    "Make active"

                 else
                    "Make inactive (skip turns)"
                )
                (ToggleInactive creature.name)

        WidgetDuplicateButton ->
            iconBtn "icon-btn"
                "⧉"
                "Duplicate"
                (DuplicateOpen creature.name)

        WidgetRemoveButton ->
            iconBtn "icon-btn icon-btn--danger"
                "×"
                "Remove from encounter"
                (RemoveCreature creature.name)

        WidgetSelectCheckbox ->
            input
                [ type_ "checkbox"
                , class "creature-card-custom__select"
                , checked creature.selected
                , onClick (ToggleSelected creature.name)
                , attribute "aria-label" ("Select " ++ creature.name)
                ]
                []

        WidgetPanelPinButton ->
            case creature.creatureId of
                Just cid ->
                    iconBtn "icon-btn"
                        "📌"
                        "Pin to right panel"
                        (PanelShowCreature cid creature.name)

                Nothing ->
                    -- No compendium source linked; the pin
                    -- button has nothing to point at.  Render
                    -- a dimmed glyph so the GM still sees the
                    -- widget slot but it doesn't fire.
                    span [ class "icon-btn icon-btn--disabled" ]
                        [ text "📌" ]

        WidgetTags ->
            -- Tags live on the compendium source, not the
            -- encounter instance.  Look up the source by
            -- `creatureId` and render each tag as a small yellow
            -- pill matching the stat-block badge styling.  When
            -- the source is missing (free-typed encounter
            -- creature, or compendium entry deleted) the widget
            -- renders nothing rather than a stub — tags are
            -- decorative, not load-bearing.
            case creature.creatureId of
                Just cid ->
                    case Compendium.find cid db of
                        Just source ->
                            if List.isEmpty source.tags then
                                text ""

                            else
                                span [ class "creature-card-custom__tags" ]
                                    (List.map tagBadge source.tags)

                        Nothing ->
                            text ""

                Nothing ->
                    text ""

        WidgetMoveUpButton ->
            iconBtn "icon-btn"
                "↑"
                "Move up in queue"
                (MoveCreatureUp creature.name)

        WidgetMoveDownButton ->
            iconBtn "icon-btn"
                "↓"
                "Move down in queue"
                (MoveCreatureDown creature.name)

        WidgetMakeActiveButton ->
            iconBtn "icon-btn icon-btn--accent"
                "→"
                "Make active"
                (SetActive creature.name)

        WidgetReplaceButton ->
            iconBtn "icon-btn"
                "⇄"
                "Replace creature"
                (QuickAddOpenForReplace creature.name)


tagBadge : String -> Html Msg
tagBadge t =
    -- Reuse the stat-block tag badge class so colour and pill
    -- shape match the side-panel rendering of the same tag.
    span [ class "statblock__tag-badge" ] [ text t ]



-- ── WIDGET HELPERS ───────────────────────────────────────────────────────────


conditionChip : Condition -> Html Msg
conditionChip cond =
    -- Same `.condition-chip` shell used by the non-custom card
    -- (and the encounter title bar) so the orange-amber fill +
    -- bumped Accessible sizing flow through.
    span [ class "condition-chip" ]
        [ span [ class "condition-chip__name" ] [ text cond.name ] ]


statusToggle : Creature -> Bool -> String -> Msg -> Html Msg
statusToggle _ active glyph msg =
    -- Match non-custom `.status-toggle` so theme overrides
    -- (Accessible "✓ " prefix, hover bg, on-state colour) apply.
    button
        [ class
            ("status-toggle "
                ++ (if active then
                        "status-toggle--on"

                    else
                        "status-toggle--off"
                   )
            )
        , onClick msg
        ]
        [ text glyph ]


actionBtn : String -> String -> Msg -> Html Msg
actionBtn label_ variantClass msg =
    button
        [ class ("action-btn " ++ variantClass)
        , onClick msg
        ]
        [ text label_ ]


iconBtn : String -> String -> String -> Msg -> Html Msg
iconBtn cls glyph ariaLabel msg =
    button
        [ class cls
        , onClick msg
        , attribute "aria-label" ariaLabel
        ]
        [ text glyph ]


pipStrip : Int -> Int -> String -> Html Msg
pipStrip total filled cls =
    span [ class "creature-card-custom__pip-strip" ]
        (List.range 1 total
            |> List.map
                (\i ->
                    let
                        isFilled =
                            i <= filled

                        pipClass =
                            "creature-card-custom__pip "
                                ++ cls
                                ++ (if isFilled then
                                        " creature-card-custom__pip--filled"

                                    else
                                        ""
                                   )
                    in
                    span [ class pipClass ] []
                )
        )


coverLabel : Cover -> String
coverLabel cover =
    case cover of
        NoCover ->
            "no cover"

        HalfCover ->
            "1/2"

        ThreeQuartersCover ->
            "3/4"

        FullCover ->
            "total"


{-| Render the lowercase `creatureKind` token ("player" /
"enemy" / "npc") as a display label. Defaults to "Enemy" for
anything unrecognised so the badge always reads.
-}
kindBadgeLabel : String -> String
kindBadgeLabel raw =
    case String.toLower raw of
        "player" ->
            "Player"

        "npc" ->
            "NPC"

        _ ->
            "Enemy"


{-| Capitalise the first letter of each space-separated word.
Lowercase alignments like "lawful evil" become "Lawful Evil" for
the badge; entries already title-cased pass through unchanged.
-}
toTitleCase : String -> String
toTitleCase s =
    s
        |> String.words
        |> List.map titleCaseWord
        |> String.join " "


titleCaseWord : String -> String
titleCaseWord w =
    case String.uncons w of
        Just ( first, rest ) ->
            String.cons (Char.toUpper first) (String.toLower rest)

        Nothing ->
            w
