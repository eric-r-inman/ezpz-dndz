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
    flying, holding action, skip) fire their `Toggle*` Msgs.
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
import Msg exposing (HpKind(..), Msg(..))
import Set
import Ui.HpChange exposing (HpEdit)



-- ── ENTRY ────────────────────────────────────────────────────────────────────


view : CardLayout -> String -> Maybe HpEdit -> Creature -> Html Msg
view layout activeName _ creature =
    let
        isActive =
            creature.name == activeName

        isDead =
            Encounter.isDeathSaveDead creature.deathSaves

        cardClass =
            String.join " "
                (List.filterMap identity
                    [ Just "creature-card"
                    , Just "creature-card--custom"
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
    article
        [ id (Effects.cardId creature.name), class cardClass ]
        [ div [ class "creature-card-custom__body" ]
            (List.map (renderRow creature) layout.rows)
        ]



-- ── ROWS ─────────────────────────────────────────────────────────────────────


renderRow : Creature -> CardRow -> Html Msg
renderRow creature row =
    div
        [ class
            ("creature-card-custom__row "
                ++ alignmentClass row.alignment
            )
        ]
        (List.map (renderWidget creature) row.widgets)


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


renderWidget : Creature -> CardWidget -> Html Msg
renderWidget creature widget =
    case widget of
        WidgetName ->
            span [ class "creature-card-custom__name" ] [ text creature.name ]

        WidgetArmorClass ->
            span [ class "creature-card-custom__ac" ]
                [ text ("AC " ++ String.fromInt creature.armorClass) ]

        WidgetHitPoints ->
            span [ class "creature-card-custom__hp" ]
                [ span [ class "creature-card-custom__hp-current" ]
                    [ text (String.fromInt creature.currentHp) ]
                , span [ class "creature-card-custom__hp-sep" ] [ text " / " ]
                , span [ class "creature-card-custom__hp-max" ]
                    [ text (String.fromInt creature.maxHp) ]
                ]

        WidgetTempHp ->
            if creature.tempHp > 0 then
                span [ class "creature-card-custom__temp" ]
                    [ text ("+" ++ String.fromInt creature.tempHp) ]

            else
                text ""

        WidgetInitiative ->
            span [ class "creature-card-custom__initiative" ]
                [ text ("init " ++ String.fromInt creature.initiative) ]

        WidgetKindBadge ->
            span [ class "creature-card-custom__chip" ] [ text creature.kind ]

        WidgetRaceLine ->
            text ""

        WidgetConditions ->
            if List.isEmpty creature.conditions then
                text ""

            else
                span [ class "creature-card-custom__conditions" ]
                    (List.map conditionChip creature.conditions)

        WidgetBloodied ->
            if creature.bloodied || creature.currentHp <= creature.maxHp // 2 then
                span [ class "creature-card-custom__bloodied" ] [ text "🩸" ]

            else
                text ""

        WidgetCoverToggle ->
            button
                [ class "creature-card-custom__toggle"
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

        WidgetHoldingAction ->
            statusToggle creature
                creature.holding
                "⏸"
                (ToggleHolding creature.name)

        WidgetMemoSlot ->
            if String.isEmpty creature.memo then
                button
                    [ class "creature-card-custom__icon-btn"
                    , onClick (MemoOpen creature.name)
                    , attribute "aria-label" "Add memo"
                    ]
                    [ text "📝" ]

            else
                span [ class "creature-card-custom__memo-pill" ]
                    [ button
                        [ class "creature-card-custom__memo-text"
                        , onClick (MemoOpen creature.name)
                        ]
                        [ text creature.memo ]
                    , button
                        [ class "creature-card-custom__memo-clear"
                        , onClick (MemoClear creature.name)
                        , attribute "aria-label" "Clear memo"
                        ]
                        [ text "×" ]
                    ]

        WidgetTimerSlot ->
            case creature.timer of
                Just t ->
                    span [ class "creature-card-custom__timer-pill" ]
                        [ span [] [ text ("⏱ " ++ String.fromInt t.remaining) ]
                        , button
                            [ class "creature-card-custom__memo-clear"
                            , onClick (TimerDismiss creature.name)
                            , attribute "aria-label" "Cancel timer"
                            ]
                            [ text "×" ]
                        ]

                Nothing ->
                    button
                        [ class "creature-card-custom__icon-btn"
                        , onClick (TimerOpen creature.name)
                        , attribute "aria-label" "Set timer"
                        ]
                        [ text "⏱️" ]

        WidgetDamageButton ->
            actionBtn "Damage"
                "action-btn--damage"
                (HpChangeOpen creature.name DamageKind)

        WidgetHealButton ->
            actionBtn "Heal"
                "action-btn--heal"
                (HpChangeOpen creature.name HealKind)

        WidgetTempHpButton ->
            actionBtn "Temp HP"
                "action-btn--temp"
                (HpChangeOpen creature.name TempHpKind)

        WidgetConditionButton ->
            actionBtn "Condition"
                "action-btn--condition"
                (ConditionOpenNew creature.name)

        WidgetDeathSaves ->
            span [ class "creature-card-custom__deathsaves" ]
                [ span [ class "creature-card-custom__pip-label" ] [ text "✓" ]
                , pipStrip 3
                    creature.deathSaves.successes
                    "creature-card-custom__pip--success"
                , span [ class "creature-card-custom__pip-label" ] [ text "✗" ]
                , pipStrip 3
                    creature.deathSaves.failures
                    "creature-card-custom__pip--failure"
                ]

        WidgetLegendaryActions ->
            if creature.hasLegendaryActions then
                span [ class "creature-card-custom__legendary" ]
                    [ span [ class "creature-card-custom__pip-label" ] [ text "LA" ]
                    , pipStrip 3
                        (Set.size creature.legendaryActionsUsed)
                        "creature-card-custom__pip--legendary"
                    ]

            else
                text ""

        WidgetLegendaryResistance ->
            if creature.hasLegendaryResistance then
                span [ class "creature-card-custom__legendary" ]
                    [ span [ class "creature-card-custom__pip-label" ] [ text "LR" ]
                    , pipStrip 3
                        (Set.size creature.legendaryResistanceUsed)
                        "creature-card-custom__pip--resistance"
                    ]

            else
                text ""

        WidgetSkipToggle ->
            iconBtn
                (if creature.inactive then
                    "creature-card-custom__icon-btn creature-card-custom__icon-btn--toggled"

                 else
                    "creature-card-custom__icon-btn"
                )
                "∅"
                (if creature.inactive then
                    "Make active"

                 else
                    "Make inactive (skip turns)"
                )
                (ToggleInactive creature.name)

        WidgetDuplicateButton ->
            iconBtn "creature-card-custom__icon-btn"
                "⧉"
                "Duplicate"
                (DuplicateOpen creature.name)

        WidgetRemoveButton ->
            iconBtn "creature-card-custom__icon-btn creature-card-custom__icon-btn--danger"
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
                    iconBtn "creature-card-custom__icon-btn"
                        "📌"
                        "Pin to right panel"
                        (PanelShowCreature cid creature.name)

                Nothing ->
                    -- No compendium source linked; the pin
                    -- button has nothing to point at.  Render
                    -- a dimmed glyph so the GM still sees the
                    -- widget slot but it doesn't fire.
                    span [ class "creature-card-custom__icon-btn creature-card-custom__icon-btn--disabled" ]
                        [ text "📌" ]



-- ── WIDGET HELPERS ───────────────────────────────────────────────────────────


conditionChip : Condition -> Html Msg
conditionChip cond =
    span [ class "creature-card-custom__chip creature-card-custom__chip--condition" ]
        [ text cond.name ]


statusToggle : Creature -> Bool -> String -> Msg -> Html Msg
statusToggle _ active glyph msg =
    button
        [ class
            ("creature-card-custom__toggle"
                ++ (if active then
                        " creature-card-custom__toggle--active"

                    else
                        ""
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
            "full"
