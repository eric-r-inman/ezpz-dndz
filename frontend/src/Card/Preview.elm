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
        (List.map (renderRow creature) layout.centerRows)



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
    , acceptingDeathSaves = False
    , reactionUsed = False
    , rechargeAbilities = []
    , readied = False
    , inactive = False
    , note = ""
    , memo = "Carrying a key"
    , timer = Nothing
    , creatureId = Nothing
    , legendaryActionsCount = 0
    , legendaryActionsLairBonus = 0
    , legendaryActionsUsed = Set.empty
    , legendaryResistanceCount = 0
    , legendaryResistanceLairBonus = 0
    , legendaryResistanceUsed = Set.empty
    , isPlaceholder = False
    , creatureKind = "enemy"
    , race = "Beast"
    , alignment = "Neutral"
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

        WidgetTypeBadge ->
            span [ class "card-preview__chip" ] [ text "Goblinoid" ]

        WidgetAlignmentBadge ->
            span [ class "card-preview__chip" ] [ text "Chaotic Evil" ]

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

        WidgetReadiedAction ->
            toggleChip "⏸" (boolLabel "readied action" creature.readied)

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

        WidgetDeathSaves ->
            -- Mock pip strip — three success + three failure dots
            -- shown regardless of the creature's actual deathSaves
            -- state, since this is a sample card.  The real
            -- `Card.Render` renders the actual DeathSaves struct.
            span [ class "card-preview__deathsaves" ]
                [ span [ class "card-preview__deathsaves-label" ] [ text "✓" ]
                , pipStrip 3 0 "card-preview__pip--success"
                , span [ class "card-preview__deathsaves-label" ] [ text "✗" ]
                , pipStrip 3 0 "card-preview__pip--failure"
                ]

        WidgetLegendaryActions ->
            span [ class "card-preview__legendary" ]
                [ span [ class "card-preview__legendary-label" ] [ text "LA" ]
                , pipStrip 3 0 "card-preview__pip--legendary"
                ]

        WidgetLegendaryResistance ->
            span [ class "card-preview__legendary" ]
                [ span [ class "card-preview__legendary-label" ] [ text "LR" ]
                , pipStrip 3 0 "card-preview__pip--resistance"
                ]

        WidgetSkipToggle ->
            iconChip "∅" (boolLabel "inactive" creature.inactive)

        WidgetDuplicateButton ->
            iconChip "⧉" "duplicate"

        WidgetRemoveButton ->
            iconChip "×" "remove"

        WidgetSelectCheckbox ->
            span [ class "card-preview__checkbox" ]
                [ text
                    (if creature.selected then
                        "☑"

                     else
                        "☐"
                    )
                ]

        WidgetPanelPinButton ->
            iconChip "📌" "pin to right panel"

        WidgetTags ->
            -- Editor preview uses a synthetic creature with no
            -- compendium source, so render two sample badges that
            -- visualise what the widget will look like on a real
            -- card.  The live encounter card uses the actual
            -- compendium tag list (see `View.Card.Custom`).
            span [ class "card-preview__tags" ]
                [ span [ class "card-preview__tag-badge" ] [ text "boss" ]
                , span [ class "card-preview__tag-badge" ] [ text "fire_resist" ]
                ]

        WidgetMoveUpButton ->
            iconChip "↑" "move up"

        WidgetMoveDownButton ->
            iconChip "↓" "move down"

        WidgetMakeActiveButton ->
            iconChip "→" "make active"

        WidgetReplaceButton ->
            iconChip "⇄" "replace"



-- ── WIDGET HELPERS ───────────────────────────────────────────────────────────


conditionChip : String -> Html msg
conditionChip name =
    span [ class "card-preview__chip card-preview__chip--condition" ]
        [ text name ]


iconChip : String -> String -> Html msg
iconChip glyph descriptor =
    span [ class "card-preview__icon-chip" ]
        [ span [ class "card-preview__icon-chip-glyph" ] [ text glyph ]
        , span [ class "card-preview__icon-chip-label" ] [ text descriptor ]
        ]


{-| Horizontal strip of `total` pip circles, with the first
`filled` shown as solid. Used by death-saves and the LA / LR
trackers; the `cls` argument applies a colour modifier so the
pips read distinctly (green success, red failure, gold
legendary).
-}
pipStrip : Int -> Int -> String -> Html msg
pipStrip total filled cls =
    span [ class "card-preview__pip-strip" ]
        (List.range 1 total
            |> List.map
                (\i ->
                    let
                        isFilled =
                            i <= filled

                        pipClass =
                            "card-preview__pip "
                                ++ cls
                                ++ (if isFilled then
                                        " card-preview__pip--filled"

                                    else
                                        ""
                                   )
                    in
                    span [ class pipClass ] []
                )
        )


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
            "total"


boolLabel : String -> Bool -> String
boolLabel verb b =
    if b then
        verb

    else
        "not " ++ verb
