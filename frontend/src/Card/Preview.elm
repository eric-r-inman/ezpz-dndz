module Card.Preview exposing (sampleCreature, view)

{-| **Prototype** layout-driven creature card.

Takes a [`Card.Layout.CardLayout`](Card-Layout#CardLayout) plus a
sample creature and renders the card from the layout's rows /
widgets / alignments — no hardcoded structure.

Widgets are dispatched through [`renderWidget`](#renderWidget),
which currently handles a representative subset (name, AC, HP,
temp HP, conditions, the four core toggles, the action-button
row, memo + timer slots). Widgets we haven't wired up yet
render as a labeled "Coming soon" pill so the catalogue stays
complete in the editor while we expand renderer coverage over
time.

This module is read-only — nothing fires `Msg`s. The preview
exists to show the user what their layout looks like; clicks on
preview controls intentionally don't do anything (we don't want
the editor's sample to mutate the live encounter).

-}

import Card.Layout as Layout
    exposing
        ( CardLayout
        , CardRow
        , CardWidget(..)
        , RowAlignment(..)
        )
import Encounter exposing (Condition, Cover(..), Creature)
import Encounter.DeathSaves as DeathSaves
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (class)
import Set



-- ── ENTRY ────────────────────────────────────────────────────────────────────


{-| Render a creature card according to the given layout.
-}
view : CardLayout -> Creature -> Html msg
view layout creature =
    div [ class "card-preview" ]
        (List.map (renderRow creature) layout.rows)



-- ── SAMPLE CREATURE ──────────────────────────────────────────────────────────


{-| Stock creature used in the editor's preview pane. Chosen
to exercise as many widget renderers as possible — non-zero
temp HP, a couple of conditions, a memo, etc.
-}
sampleCreature : Creature
sampleCreature =
    { name = "Sample Goblin"
    , kind = "enemy"
    , initiative = 14
    , initiativeBonus = 2
    , currentHp = 7
    , maxHp = 12
    , tempHp = 3
    , armorClass = 15
    , speed = 30
    , conditions = [ sampleCondition 1 "Prone", sampleCondition 2 "Frightened" ]
    , saveNotices = []
    , selected = False
    , cover = NoCover
    , concentrating = False
    , hiding = False
    , dodging = False
    , flying = False
    , flyHeight = 0
    , bloodied = False
    , deathSaves = DeathSaves.empty
    , holding = False
    , inactive = False
    , note = ""
    , memo = "Carrying a key"
    , timer = Nothing
    , creatureId = Nothing
    , hasLegendaryActions = False
    , legendaryActionsUsed = Set.empty
    , hasLegendaryResistance = False
    , legendaryResistanceUsed = Set.empty
    }


sampleCondition : Int -> String -> Condition
sampleCondition id name =
    { id = id
    , name = name
    , note = ""
    , duration = Encounter.DurationManual
    , saveToEnd = Nothing
    }



-- ── ROWS / ALIGNMENT ─────────────────────────────────────────────────────────


renderRow : Creature -> CardRow -> Html msg
renderRow creature row =
    div
        [ class
            ("card-preview__row "
                ++ alignmentClass row.alignment
            )
        ]
        (List.map (renderWidget creature) row.widgets)


alignmentClass : RowAlignment -> String
alignmentClass a =
    case a of
        AlignLeft ->
            "card-preview__row--align-left"

        AlignCenter ->
            "card-preview__row--align-center"

        AlignRight ->
            "card-preview__row--align-right"

        AlignSpaceBetween ->
            "card-preview__row--align-space-between"



-- ── WIDGET DISPATCH ──────────────────────────────────────────────────────────


renderWidget : Creature -> CardWidget -> Html msg
renderWidget creature widget =
    case widget of
        WidgetName ->
            span [ class "card-preview__name" ] [ text creature.name ]

        WidgetArmorClass ->
            span [ class "card-preview__ac" ]
                [ text ("AC " ++ String.fromInt creature.armorClass) ]

        WidgetHitPoints ->
            span [ class "card-preview__hp" ]
                [ span [ class "card-preview__hp-current" ]
                    [ text (String.fromInt creature.currentHp) ]
                , span [ class "card-preview__hp-sep" ] [ text " / " ]
                , span [ class "card-preview__hp-max" ]
                    [ text (String.fromInt creature.maxHp) ]
                ]

        WidgetTempHp ->
            if creature.tempHp > 0 then
                span [ class "card-preview__temp" ]
                    [ text ("+" ++ String.fromInt creature.tempHp) ]

            else
                placeholder widget "(no temp HP)"

        WidgetInitiative ->
            span [ class "card-preview__initiative" ]
                [ text ("init " ++ String.fromInt creature.initiative) ]

        WidgetKindBadge ->
            span [ class "card-preview__chip" ] [ text "Enemy" ]

        WidgetRaceLine ->
            span [ class "card-preview__race" ]
                [ text "Goblin · Chaotic Evil" ]

        WidgetConditions ->
            if List.isEmpty creature.conditions then
                placeholder widget "(no conditions)"

            else
                span [ class "card-preview__conditions" ]
                    (List.map (\c -> conditionChip c.name) creature.conditions)

        WidgetBloodied ->
            if creature.bloodied || creature.currentHp <= creature.maxHp // 2 then
                span [ class "card-preview__bloodied" ] [ text "🩸" ]

            else
                placeholder widget "(not bloodied)"

        WidgetCoverToggle ->
            toggleChip "🛡" (coverLabel creature.cover)

        WidgetConcentrating ->
            toggleChip "🧠" (boolLabel "concentrating" creature.concentrating)

        WidgetHiding ->
            toggleChip "👤" (boolLabel "hiding" creature.hiding)

        WidgetDodging ->
            toggleChip "🤸" (boolLabel "dodging" creature.dodging)

        WidgetFlying ->
            toggleChip "🪽" (boolLabel "flying" creature.flying)

        WidgetHoldingAction ->
            toggleChip "⏸" (boolLabel "holding action" creature.holding)

        WidgetMemoSlot ->
            if String.isEmpty creature.memo then
                placeholder widget "(no memo)"

            else
                span [ class "card-preview__memo" ] [ text ("📝 " ++ creature.memo) ]

        WidgetTimerSlot ->
            case creature.timer of
                Just t ->
                    span [ class "card-preview__timer" ]
                        [ text ("⏱ " ++ String.fromInt t.remaining) ]

                Nothing ->
                    placeholder widget "(no timer)"

        WidgetDamageButton ->
            actionPill "Damage" "card-preview__btn--damage"

        WidgetHealButton ->
            actionPill "Heal" "card-preview__btn--heal"

        WidgetTempHpButton ->
            actionPill "Temp HP" "card-preview__btn--temp"

        WidgetConditionButton ->
            actionPill "Condition" "card-preview__btn--condition"

        _ ->
            placeholder widget "Coming soon"



-- ── WIDGET HELPERS ───────────────────────────────────────────────────────────


conditionChip : String -> Html msg
conditionChip name =
    span [ class "card-preview__chip card-preview__chip--condition" ]
        [ text name ]


toggleChip : String -> String -> Html msg
toggleChip glyph state =
    span [ class "card-preview__toggle" ]
        [ span [ class "card-preview__toggle-glyph" ] [ text glyph ]
        , span [ class "card-preview__toggle-state" ] [ text state ]
        ]


actionPill : String -> String -> Html msg
actionPill label_ extraClass =
    button
        [ class ("card-preview__btn " ++ extraClass)

        -- Preview buttons never fire — they're decorative in the
        -- editor.  Adding `disabled` would dim them visually,
        -- but we want them to LOOK like they would in the real
        -- card so the user sees what their layout will produce.
        ]
        [ text label_ ]


{-| Labeled placeholder shown for either:

  - widget variants we haven't wired up yet (the `_ ->` catchall
    in [`renderWidget`](#renderWidget)), or
  - widgets that are layout-included but have no value to show
    for this sample creature (e.g. memo when the memo is empty).

-}
placeholder : CardWidget -> String -> Html msg
placeholder widget hint =
    span [ class "card-preview__placeholder" ]
        [ span [ class "card-preview__placeholder-label" ]
            [ text (Layout.widgetLabel widget) ]
        , span [ class "card-preview__placeholder-hint" ]
            [ text hint ]
        ]


coverLabel : Cover -> String
coverLabel cover =
    case cover of
        NoCover ->
            "no cover"

        HalfCover ->
            "half"

        ThreeQuartersCover ->
            "3/4"

        FullCover ->
            "full"


boolLabel : String -> Bool -> String
boolLabel verb b =
    if b then
        verb

    else
        "not " ++ verb
