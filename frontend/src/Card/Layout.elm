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
    , centerEditableWidgets, legacyDefaultLayout, migrateLegacyDefault, toggleDeathSaves, toggleLegendary
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
    { centerRows : List CardRow
    , deathSavesEnabled : Bool
    , legendaryEnabled : Bool
    }


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
    | WidgetTypeBadge
    | WidgetAlignmentBadge
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
    | WidgetMoveUpButton
    | WidgetMoveDownButton
    | WidgetMakeActiveButton
    | WidgetReplaceButton


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
    -- The custom card is a fixed shell: left + right rails are
    -- always present (and unmodifiable), the death-saves and
    -- legendary side columns are toggle-only, and the centre
    -- column has exactly three editable rows.  The default below
    -- populates the centre rows with the same content the
    -- non-custom card shows.
    { centerRows =
        [ { widgets =
                [ WidgetInitiative
                , WidgetName
                , WidgetKindBadge
                , WidgetTypeBadge
                , WidgetAlignmentBadge
                , WidgetTags
                , WidgetArmorClass
                , WidgetConditions
                ]
          , alignment = AlignSpaceBetween
          }
        , { widgets =
                [ WidgetHitPoints
                , WidgetTempHp
                , WidgetBloodied
                , WidgetCoverToggle
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
    , deathSavesEnabled = True
    , legendaryEnabled = True
    }


emptyLayout : CardLayout
emptyLayout =
    { centerRows = []
    , deathSavesEnabled = False
    , legendaryEnabled = False
    }


{-| The shape `defaultLayout` had BEFORE the Kind / Type /
Alignment split and the row-controls expansion. Held as a
constant so anonymous-mode bootstrap can detect users who never
customised their layout and upgrade them to the new default
instead of leaving them on an obsolete shape. Customised
layouts won't match this exactly and so won't be touched.
-}
legacyDefaultLayout : CardLayout
legacyDefaultLayout =
    { centerRows =
        [ { widgets = [ WidgetName, WidgetArmorClass ]
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
    , deathSavesEnabled = False
    , legendaryEnabled = False
    }


{-| Upgrade a loaded layout to include every widget the current
`defaultLayout` lists. Two-step:

1.  If the layout matches `legacyDefaultLayout` exactly, swap
    wholesale for `defaultLayout` so the user gets the new row
    structure (better visual parity with the non-custom card).
2.  Otherwise — when the user has customised — keep their rows
    intact and APPEND a new row containing any widgets present
    in `defaultLayout` but missing from their layout. Additive,
    never destructive.

This handles both the "fresh user with stale localStorage" case
and the "user who customised and then a new widget shipped" case
without losing their work.

-}
migrateLegacyDefault : CardLayout -> CardLayout
migrateLegacyDefault layout =
    if layout == legacyDefaultLayout then
        defaultLayout

    else
        supplementMissingWidgets layout


{-| If `defaultLayout`'s centre rows reference widgets the input
layout doesn't have, append them as a third (or trailing) centre
row so the user picks up new widgets that have shipped since
they last touched the editor. Caps centre rows at three —
anything beyond is dropped (the editor enforces the same cap).
-}
supplementMissingWidgets : CardLayout -> CardLayout
supplementMissingWidgets layout =
    let
        present =
            layout.centerRows |> List.concatMap .widgets

        missing =
            defaultLayout.centerRows
                |> List.concatMap .widgets
                |> List.filter (\w -> not (List.member w present))

        supplemented =
            if List.isEmpty missing then
                layout.centerRows

            else
                layout.centerRows
                    ++ [ { widgets = missing, alignment = AlignLeft } ]
    in
    { layout | centerRows = List.take 3 supplemented }



-- ── HELPERS ──────────────────────────────────────────────────────────────────


widgetAllValues : List CardWidget
widgetAllValues =
    [ WidgetName
    , WidgetArmorClass
    , WidgetHitPoints
    , WidgetTempHp
    , WidgetInitiative
    , WidgetKindBadge
    , WidgetTypeBadge
    , WidgetAlignmentBadge
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
    , WidgetMoveUpButton
    , WidgetMoveDownButton
    , WidgetMakeActiveButton
    , WidgetReplaceButton
    ]


{-| Subset of the catalogue that's pickable inside the centre
column. Excludes the rail widgets (move / select / make-active /
×, inactive, replace, duplicate, panel pin) which always live in
the left or right rail, and the side-column widgets (death
saves, LA, LR) which the layout toggles on / off as fixed
content. The editor's "Add widget" picker presents this list
rather than `widgetAllValues`.
-}
centerEditableWidgets : List CardWidget
centerEditableWidgets =
    widgetAllValues
        |> List.filter
            (\w ->
                case w of
                    WidgetSelectCheckbox ->
                        False

                    WidgetMoveUpButton ->
                        False

                    WidgetMoveDownButton ->
                        False

                    WidgetMakeActiveButton ->
                        False

                    WidgetRemoveButton ->
                        False

                    WidgetSkipToggle ->
                        False

                    WidgetReplaceButton ->
                        False

                    WidgetDuplicateButton ->
                        False

                    WidgetPanelPinButton ->
                        False

                    WidgetDeathSaves ->
                        False

                    WidgetLegendaryActions ->
                        False

                    WidgetLegendaryResistance ->
                        False

                    _ ->
                        True
            )


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

        WidgetTypeBadge ->
            "type_badge"

        WidgetAlignmentBadge ->
            "alignment_badge"

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

        WidgetMoveUpButton ->
            "move_up_button"

        WidgetMoveDownButton ->
            "move_down_button"

        WidgetMakeActiveButton ->
            "make_active_button"

        WidgetReplaceButton ->
            "replace_button"


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

        "race_line" ->
            -- Pre-split combined "Race / Alignment" widget;
            -- legacy saved layouts deserialise to the new
            -- type-only badge so the alignment half is dropped
            -- (the layout editor lets the user add it back).
            Just WidgetTypeBadge

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

        WidgetTypeBadge ->
            "Type Badge"

        WidgetAlignmentBadge ->
            "Alignment Badge"

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

        WidgetMoveUpButton ->
            "Move Up Button"

        WidgetMoveDownButton ->
            "Move Down Button"

        WidgetMakeActiveButton ->
            "Make Active Button"

        WidgetReplaceButton ->
            "Replace Button"


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

        WidgetTypeBadge ->
            "Creature type (e.g. Dragon, Humanoid, Beast)."

        WidgetAlignmentBadge ->
            "Alignment summary (e.g. Lawful Evil, Neutral)."

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

        WidgetMoveUpButton ->
            "Move this creature one slot up in the queue."

        WidgetMoveDownButton ->
            "Move this creature one slot down in the queue."

        WidgetMakeActiveButton ->
            "Promote this creature to active (whose turn it is)."

        WidgetReplaceButton ->
            "Swap this creature for another via the Quick Add modal."


widgetCategory : CardWidget -> WidgetCategory
widgetCategory w =
    case w of
        WidgetName ->
            CategoryIdentity

        WidgetKindBadge ->
            CategoryIdentity

        WidgetTypeBadge ->
            CategoryIdentity

        WidgetAlignmentBadge ->
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

        WidgetMoveUpButton ->
            CategoryRowControls

        WidgetMoveDownButton ->
            CategoryRowControls

        WidgetMakeActiveButton ->
            CategoryRowControls

        WidgetReplaceButton ->
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


{-| Centre column is capped at three editable rows. `addRow`
appends an empty row when below the cap; no-op at the cap.
-}
addRow : CardLayout -> CardLayout
addRow layout =
    if List.length layout.centerRows >= 3 then
        layout

    else
        { layout
            | centerRows =
                layout.centerRows
                    ++ [ { widgets = [], alignment = AlignLeft } ]
        }


removeRow : Int -> CardLayout -> CardLayout
removeRow index layout =
    { layout | centerRows = removeAt index layout.centerRows }


moveRowUp : Int -> CardLayout -> CardLayout
moveRowUp index layout =
    if index <= 0 then
        layout

    else
        { layout | centerRows = swap (index - 1) index layout.centerRows }


moveRowDown : Int -> CardLayout -> CardLayout
moveRowDown index layout =
    if index < 0 || index >= List.length layout.centerRows - 1 then
        layout

    else
        { layout | centerRows = swap index (index + 1) layout.centerRows }


addWidget : Int -> CardWidget -> CardLayout -> CardLayout
addWidget rowIndex widget layout =
    { layout
        | centerRows =
            updateAt rowIndex
                (\r -> { r | widgets = r.widgets ++ [ widget ] })
                layout.centerRows
    }


removeWidget : Int -> Int -> CardLayout -> CardLayout
removeWidget rowIndex widgetIndex layout =
    { layout
        | centerRows =
            updateAt rowIndex
                (\r -> { r | widgets = removeAt widgetIndex r.widgets })
                layout.centerRows
    }


setRowAlignment : Int -> RowAlignment -> CardLayout -> CardLayout
setRowAlignment rowIndex alignment layout =
    { layout
        | centerRows =
            updateAt rowIndex
                (\r -> { r | alignment = alignment })
                layout.centerRows
    }


{-| Toggle whether the death-saves side column appears on the
card. The column shows the standard 3 success + 3 failure pip
strip when on; it's fixed content, not customisable.
-}
toggleDeathSaves : CardLayout -> CardLayout
toggleDeathSaves layout =
    { layout | deathSavesEnabled = not layout.deathSavesEnabled }


{-| Toggle the legendary side column (LA + LR pip strips).
Same fixed-content contract as `toggleDeathSaves`.
-}
toggleLegendary : CardLayout -> CardLayout
toggleLegendary layout =
    { layout | legendaryEnabled = not layout.legendaryEnabled }



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
