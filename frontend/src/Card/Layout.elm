module Card.Layout exposing
    ( CardWidget(..), CardRow, RowAlignment(..), CardLayout
    , QueueView(..)
    , defaultLayout, emptyLayout
    , widgetKey, widgetFromKey, widgetLabel, widgetDescription, widgetCategory
    , widgetAllValues, widgetCategoryAllValues
    , rowAlignmentKey, rowAlignmentFromKey, rowAlignmentLabel
    , rowAlignmentAllValues
    , queueViewKey, queueViewFromKey, queueViewLabel, queueViewAllValues
    , WidgetCategory(..), widgetCategoryLabel
    , addRow, removeRow, moveRowUp, moveRowDown
    , addWidget, removeWidget
    , setRowAlignment
    )

{-| **Prototype** domain types for the customizable creature
card.

A `CardLayout` is a list of `CardRow`s; each row is a list of
`CardWidget`s with an alignment. Widgets are an enumeration of
every value, toggle, and icon that today's `View.Card` renders;
the prototype renderer covers a subset (name, HP, AC, conditions,
status toggles, HP-change action buttons) and the rest fall back
to labeled placeholders so the editor's catalogue stays complete
while we wire the renderers up over time.

No `Html` imports — this is the rules-engine layer, mirroring the
discipline of `Encounter` / `Compendium`. All view code lives in
[`View.Card.Preview`](View-Card-Preview) and (eventually)
[`View.Card.Custom`](View-Card-Custom).

@docs CardWidget, CardRow, RowAlignment, CardLayout
@docs QueueView
@docs defaultLayout, emptyLayout
@docs widgetKey, widgetFromKey, widgetLabel, widgetDescription, widgetCategory
@docs widgetAllValues, widgetCategoryAllValues
@docs rowAlignmentKey, rowAlignmentFromKey, rowAlignmentLabel
@docs rowAlignmentAllValues
@docs queueViewKey, queueViewFromKey, queueViewLabel, queueViewAllValues
@docs WidgetCategory, widgetCategoryLabel
@docs addRow, removeRow, moveRowUp, moveRowDown
@docs addWidget, removeWidget
@docs setRowAlignment

-}

-- ── TYPES ────────────────────────────────────────────────────────────────────


type alias CardLayout =
    { rows : List CardRow }


type alias CardRow =
    { widgets : List CardWidget
    , alignment : RowAlignment
    }


{-| Horizontal alignment of the widgets within a row.

  - `AlignLeft` / `AlignCenter` / `AlignRight` — pack widgets
    with the gap on the unused side.
  - `AlignSpaceBetween` — fill the row, distributing widgets
    evenly (first widget flush left, last widget flush right).

-}
type RowAlignment
    = AlignLeft
    | AlignCenter
    | AlignRight
    | AlignSpaceBetween


{-| Queue-level layout choice. Affects how the encounter
panel arranges creature cards; widgets inside each card are
unchanged by this setting.
-}
type QueueView
    = ListView
    | GridView


{-| Every element today's `View.Card` is capable of rendering.

The variants are flat (not nested by row / column) so the type
acts as a stable catalogue: a layout names which widgets to
render where, and the renderer maps each variant to the
specific Html for that widget.

When new widgets land on `View.Card`, add the variant here
(and to [`widgetAllValues`](#widgetAllValues)) so the editor's
"Add widget" picker sees them.

-}
type CardWidget
    = WidgetName
    | WidgetArmorClass
    | WidgetHitPoints
    | WidgetTempHp
    | WidgetInitiative
    | WidgetKindBadge
    | WidgetRaceLine
    | WidgetConditions
    | WidgetBloodied
    | WidgetCoverToggle
    | WidgetConcentrating
    | WidgetHiding
    | WidgetDodging
    | WidgetFlying
    | WidgetReadiedAction
    | WidgetMemoSlot
    | WidgetTimerSlot
    | WidgetDamageButton
    | WidgetHealButton
    | WidgetTempHpButton
    | WidgetConditionButton
    | WidgetDeathSaves
    | WidgetLegendaryActions
    | WidgetLegendaryResistance
    | WidgetSkipToggle
    | WidgetDuplicateButton
    | WidgetRemoveButton
    | WidgetSelectCheckbox
    | WidgetPanelPinButton
    | WidgetTags


{-| Coarse grouping shown in the widget picker so the
catalogue isn't one long flat list. Categories are
display-only; the layout itself just stores widgets.
-}
type WidgetCategory
    = CategoryIdentity
    | CategoryVitals
    | CategoryConditionsAndStatus
    | CategoryActions
    | CategoryCombatTracking
    | CategoryRowControls



-- ── DEFAULT LAYOUT ───────────────────────────────────────────────────────────


{-| Default layout — a best-effort mirror of today's hardcoded
`View.Card` rendering, scoped to the widgets the prototype
renderer can actually draw. Users with no saved layout fall
back to this, and the editor opens to it the first time.
-}
defaultLayout : CardLayout
defaultLayout =
    { rows =
        [ { widgets = [ WidgetName, WidgetArmorClass, WidgetKindBadge ]
          , alignment = AlignSpaceBetween
          }
        , { widgets =
                [ WidgetHitPoints
                , WidgetTempHp
                , WidgetBloodied
                , WidgetConditions
                ]
          , alignment = AlignLeft
          }
        , { widgets =
                [ WidgetCoverToggle
                , WidgetConcentrating
                , WidgetHiding
                , WidgetDodging
                , WidgetFlying
                ]
          , alignment = AlignLeft
          }
        , { widgets =
                [ WidgetDamageButton
                , WidgetHealButton
                , WidgetTempHpButton
                , WidgetConditionButton
                , WidgetReadiedAction
                , WidgetMemoSlot
                , WidgetTimerSlot
                ]
          , alignment = AlignLeft
          }
        ]
    }


emptyLayout : CardLayout
emptyLayout =
    { rows = [] }



-- ── HELPERS ──────────────────────────────────────────────────────────────────


widgetAllValues : List CardWidget
widgetAllValues =
    [ WidgetName
    , WidgetArmorClass
    , WidgetHitPoints
    , WidgetTempHp
    , WidgetInitiative
    , WidgetKindBadge
    , WidgetRaceLine
    , WidgetConditions
    , WidgetBloodied
    , WidgetCoverToggle
    , WidgetConcentrating
    , WidgetHiding
    , WidgetDodging
    , WidgetFlying
    , WidgetReadiedAction
    , WidgetMemoSlot
    , WidgetTimerSlot
    , WidgetDamageButton
    , WidgetHealButton
    , WidgetTempHpButton
    , WidgetConditionButton
    , WidgetDeathSaves
    , WidgetLegendaryActions
    , WidgetLegendaryResistance
    , WidgetSkipToggle
    , WidgetDuplicateButton
    , WidgetRemoveButton
    , WidgetSelectCheckbox
    , WidgetPanelPinButton
    , WidgetTags
    ]


widgetCategoryAllValues : List WidgetCategory
widgetCategoryAllValues =
    [ CategoryIdentity
    , CategoryVitals
    , CategoryConditionsAndStatus
    , CategoryActions
    , CategoryCombatTracking
    , CategoryRowControls
    ]


widgetKey : CardWidget -> String
widgetKey w =
    case w of
        WidgetName ->
            "name"

        WidgetArmorClass ->
            "armor_class"

        WidgetHitPoints ->
            "hit_points"

        WidgetTempHp ->
            "temp_hp"

        WidgetInitiative ->
            "initiative"

        WidgetKindBadge ->
            "kind_badge"

        WidgetRaceLine ->
            "race_line"

        WidgetConditions ->
            "conditions"

        WidgetBloodied ->
            "bloodied"

        WidgetCoverToggle ->
            "cover_toggle"

        WidgetConcentrating ->
            "concentrating"

        WidgetHiding ->
            "hiding"

        WidgetDodging ->
            "dodging"

        WidgetFlying ->
            "flying"

        WidgetReadiedAction ->
            "readied_action"

        WidgetMemoSlot ->
            "memo_slot"

        WidgetTimerSlot ->
            "timer_slot"

        WidgetDamageButton ->
            "damage_button"

        WidgetHealButton ->
            "heal_button"

        WidgetTempHpButton ->
            "temp_hp_button"

        WidgetConditionButton ->
            "condition_button"

        WidgetDeathSaves ->
            "death_saves"

        WidgetLegendaryActions ->
            "legendary_actions"

        WidgetLegendaryResistance ->
            "legendary_resistance"

        WidgetSkipToggle ->
            "skip_toggle"

        WidgetDuplicateButton ->
            "duplicate_button"

        WidgetRemoveButton ->
            "remove_button"

        WidgetSelectCheckbox ->
            "select_checkbox"

        WidgetPanelPinButton ->
            "panel_pin_button"

        WidgetTags ->
            "tags"


widgetFromKey : String -> Maybe CardWidget
widgetFromKey raw =
    -- Linear lookup over the catalogue is fine — there are ~30
    -- variants and this only runs on user form input, not in
    -- a render loop.
    case widgetAllValues |> List.filter (\w -> widgetKey w == raw) |> List.head of
        Just w ->
            Just w

        Nothing ->
            widgetFromLegacyKey raw


{-| Pre-rename wire tokens that older saved layouts may still
carry. Returning the current variant for each one means a card
layout authored before a rename keeps working without a manual
migration. Add an entry here whenever a widget's key changes;
the canonical key on `widgetKey` always wins.
-}
widgetFromLegacyKey : String -> Maybe CardWidget
widgetFromLegacyKey raw =
    case raw of
        "holding_action" ->
            -- 2014-era "hold action" terminology; the 2024 MM
            -- uses "readied action".
            Just WidgetReadiedAction

        _ ->
            Nothing


widgetLabel : CardWidget -> String
widgetLabel w =
    case w of
        WidgetName ->
            "Name"

        WidgetArmorClass ->
            "Armor Class"

        WidgetHitPoints ->
            "Hit Points"

        WidgetTempHp ->
            "Temp HP"

        WidgetInitiative ->
            "Initiative"

        WidgetKindBadge ->
            "Kind Badge"

        WidgetRaceLine ->
            "Race / Alignment Line"

        WidgetConditions ->
            "Conditions"

        WidgetBloodied ->
            "Bloodied Marker"

        WidgetCoverToggle ->
            "Cover Toggle"

        WidgetConcentrating ->
            "Concentrating Toggle"

        WidgetHiding ->
            "Hiding Toggle"

        WidgetDodging ->
            "Dodging Toggle"

        WidgetFlying ->
            "Flying + Height"

        WidgetReadiedAction ->
            "Readied-Action Toggle"

        WidgetMemoSlot ->
            "Memo"

        WidgetTimerSlot ->
            "Timer"

        WidgetDamageButton ->
            "Damage Button"

        WidgetHealButton ->
            "Heal Button"

        WidgetTempHpButton ->
            "Temp HP Button"

        WidgetConditionButton ->
            "Condition Button"

        WidgetDeathSaves ->
            "Death Saves"

        WidgetLegendaryActions ->
            "Legendary Actions"

        WidgetLegendaryResistance ->
            "Legendary Resistance"

        WidgetSkipToggle ->
            "Skip-Turn Toggle"

        WidgetDuplicateButton ->
            "Duplicate Button"

        WidgetRemoveButton ->
            "Remove Button"

        WidgetSelectCheckbox ->
            "Select Checkbox"

        WidgetPanelPinButton ->
            "Right-Panel Pin"

        WidgetTags ->
            "Tags"


widgetDescription : CardWidget -> String
widgetDescription w =
    case w of
        WidgetName ->
            "Creature name; clicks pin the right panel to its stat block."

        WidgetArmorClass ->
            "Click-to-edit AC value."

        WidgetHitPoints ->
            "Current / max HP with click-to-edit on each side."

        WidgetTempHp ->
            "+N temp-HP marker (only when > 0)."

        WidgetInitiative ->
            "Initiative roll for this creature."

        WidgetKindBadge ->
            "Player / Enemy / NPC chip."

        WidgetRaceLine ->
            "Race + alignment summary."

        WidgetConditions ->
            "Inline list of active conditions and effects."

        WidgetBloodied ->
            "Drop-of-blood marker when current HP ≤ half max."

        WidgetCoverToggle ->
            "Cycle no / half / 3/4 / full cover."

        WidgetConcentrating ->
            "Concentration tracker (🧠)."

        WidgetHiding ->
            "Hidden-status toggle (👤)."

        WidgetDodging ->
            "Dodging-action toggle (🤸)."

        WidgetFlying ->
            "Flying toggle + altitude readout."

        WidgetReadiedAction ->
            "Readied-action marker."

        WidgetMemoSlot ->
            "GM-only note pill for this creature."

        WidgetTimerSlot ->
            "Multi-round timer for spell effects / ongoing damage."

        WidgetDamageButton ->
            "Open the Damage modal."

        WidgetHealButton ->
            "Open the Heal modal."

        WidgetTempHpButton ->
            "Open the Temp HP modal."

        WidgetConditionButton ->
            "Open the Condition / Effect modal."

        WidgetDeathSaves ->
            "Three success + three failure pips, shown at 0 HP."

        WidgetLegendaryActions ->
            "Legendary-action pip column."

        WidgetLegendaryResistance ->
            "Legendary-resistance pip column."

        WidgetSkipToggle ->
            "Mark inactive so the queue walker skips this creature."

        WidgetDuplicateButton ->
            "Open the Duplicate-picker modal."

        WidgetRemoveButton ->
            "Remove this creature from the encounter."

        WidgetSelectCheckbox ->
            "Bulk-selection checkbox."

        WidgetPanelPinButton ->
            "Pin the right panel to this creature's stat block."

        WidgetTags ->
            "Yellow pill badges for the creature's user-authored tags."


widgetCategory : CardWidget -> WidgetCategory
widgetCategory w =
    case w of
        WidgetName ->
            CategoryIdentity

        WidgetKindBadge ->
            CategoryIdentity

        WidgetRaceLine ->
            CategoryIdentity

        WidgetTags ->
            CategoryIdentity

        WidgetArmorClass ->
            CategoryVitals

        WidgetHitPoints ->
            CategoryVitals

        WidgetTempHp ->
            CategoryVitals

        WidgetInitiative ->
            CategoryVitals

        WidgetBloodied ->
            CategoryVitals

        WidgetConditions ->
            CategoryConditionsAndStatus

        WidgetCoverToggle ->
            CategoryConditionsAndStatus

        WidgetConcentrating ->
            CategoryConditionsAndStatus

        WidgetHiding ->
            CategoryConditionsAndStatus

        WidgetDodging ->
            CategoryConditionsAndStatus

        WidgetFlying ->
            CategoryConditionsAndStatus

        WidgetReadiedAction ->
            CategoryConditionsAndStatus

        WidgetMemoSlot ->
            CategoryConditionsAndStatus

        WidgetTimerSlot ->
            CategoryConditionsAndStatus

        WidgetDamageButton ->
            CategoryActions

        WidgetHealButton ->
            CategoryActions

        WidgetTempHpButton ->
            CategoryActions

        WidgetConditionButton ->
            CategoryActions

        WidgetDeathSaves ->
            CategoryCombatTracking

        WidgetLegendaryActions ->
            CategoryCombatTracking

        WidgetLegendaryResistance ->
            CategoryCombatTracking

        WidgetSkipToggle ->
            CategoryRowControls

        WidgetDuplicateButton ->
            CategoryRowControls

        WidgetRemoveButton ->
            CategoryRowControls

        WidgetSelectCheckbox ->
            CategoryRowControls

        WidgetPanelPinButton ->
            CategoryRowControls


widgetCategoryLabel : WidgetCategory -> String
widgetCategoryLabel c =
    case c of
        CategoryIdentity ->
            "Identity"

        CategoryVitals ->
            "Vitals"

        CategoryConditionsAndStatus ->
            "Conditions & Status"

        CategoryActions ->
            "Action Buttons"

        CategoryCombatTracking ->
            "Combat Tracking"

        CategoryRowControls ->
            "Row Controls"


rowAlignmentKey : RowAlignment -> String
rowAlignmentKey a =
    case a of
        AlignLeft ->
            "left"

        AlignCenter ->
            "center"

        AlignRight ->
            "right"

        AlignSpaceBetween ->
            "space_between"


rowAlignmentFromKey : String -> Maybe RowAlignment
rowAlignmentFromKey raw =
    case raw of
        "left" ->
            Just AlignLeft

        "center" ->
            Just AlignCenter

        "right" ->
            Just AlignRight

        "space_between" ->
            Just AlignSpaceBetween

        _ ->
            Nothing


rowAlignmentLabel : RowAlignment -> String
rowAlignmentLabel a =
    case a of
        AlignLeft ->
            "Left"

        AlignCenter ->
            "Center"

        AlignRight ->
            "Right"

        AlignSpaceBetween ->
            "Space between"


rowAlignmentAllValues : List RowAlignment
rowAlignmentAllValues =
    [ AlignLeft, AlignCenter, AlignRight, AlignSpaceBetween ]


queueViewKey : QueueView -> String
queueViewKey q =
    case q of
        ListView ->
            "list"

        GridView ->
            "grid"


queueViewFromKey : String -> Maybe QueueView
queueViewFromKey raw =
    case raw of
        "list" ->
            Just ListView

        "grid" ->
            Just GridView

        _ ->
            Nothing


queueViewLabel : QueueView -> String
queueViewLabel q =
    case q of
        ListView ->
            "List"

        GridView ->
            "Grid"


queueViewAllValues : List QueueView
queueViewAllValues =
    [ ListView, GridView ]



-- ── MUTATORS ─────────────────────────────────────────────────────────────────


addRow : CardLayout -> CardLayout
addRow layout =
    { layout
        | rows =
            layout.rows
                ++ [ { widgets = [], alignment = AlignLeft } ]
    }


removeRow : Int -> CardLayout -> CardLayout
removeRow index layout =
    { layout | rows = removeAt index layout.rows }


moveRowUp : Int -> CardLayout -> CardLayout
moveRowUp index layout =
    if index <= 0 then
        layout

    else
        { layout | rows = swap (index - 1) index layout.rows }


moveRowDown : Int -> CardLayout -> CardLayout
moveRowDown index layout =
    if index < 0 || index >= List.length layout.rows - 1 then
        layout

    else
        { layout | rows = swap index (index + 1) layout.rows }


addWidget : Int -> CardWidget -> CardLayout -> CardLayout
addWidget rowIndex widget layout =
    { layout
        | rows =
            updateAt rowIndex
                (\r -> { r | widgets = r.widgets ++ [ widget ] })
                layout.rows
    }


removeWidget : Int -> Int -> CardLayout -> CardLayout
removeWidget rowIndex widgetIndex layout =
    { layout
        | rows =
            updateAt rowIndex
                (\r -> { r | widgets = removeAt widgetIndex r.widgets })
                layout.rows
    }


setRowAlignment : Int -> RowAlignment -> CardLayout -> CardLayout
setRowAlignment rowIndex alignment layout =
    { layout
        | rows =
            updateAt rowIndex
                (\r -> { r | alignment = alignment })
                layout.rows
    }



-- ── INTERNAL ─────────────────────────────────────────────────────────────────


removeAt : Int -> List a -> List a
removeAt index xs =
    List.indexedMap Tuple.pair xs
        |> List.filterMap
            (\( i, x ) ->
                if i == index then
                    Nothing

                else
                    Just x
            )


updateAt : Int -> (a -> a) -> List a -> List a
updateAt index fn xs =
    List.indexedMap
        (\i x ->
            if i == index then
                fn x

            else
                x
        )
        xs


swap : Int -> Int -> List a -> List a
swap i j xs =
    let
        atI =
            List.drop i xs |> List.head

        atJ =
            List.drop j xs |> List.head
    in
    case ( atI, atJ ) of
        ( Just vi, Just vj ) ->
            xs
                |> updateAt i (\_ -> vj)
                |> updateAt j (\_ -> vi)

        _ ->
            xs
