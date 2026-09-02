module View.Tooltips exposing
    ( actionGroupToggle
    , appBarAccount
    , appBarDonate
    , appBarSettings
    , applyCondition
    , armorClass
    , attr
    , bloodied
    , chipClickToEdit
    , chipDismiss
    , chipFullTitle
    , chipRemoveModalRow
    , chipRollSave
    , clear
    , clickToEdit
    , compendiumAddSelected
    , compendiumAddToEncounter
    , compendiumAddedFilterOff
    , compendiumAddedFilterOn
    , compendiumClear
    , compendiumClearSelectedNone
    , compendiumClearSelectedReady
    , compendiumClearTagFilter
    , compendiumCreateGroup
    , compendiumCreateGroupFromSelected
    , compendiumDelete
    , compendiumDeleteSelected
    , compendiumDuplicate
    , compendiumEdit
    , compendiumEditBundled
    , compendiumEditClearUsage
    , compendiumEditDeleteCreature
    , compendiumEditRemoveEntry
    , compendiumEditRemoveSave
    , compendiumEditRemoveSection
    , compendiumEditRemoveSkill
    , compendiumEditRemoveTag
    , compendiumExport
    , compendiumExportDirty
    , compendiumGroupAdd
    , compendiumGroupDelete
    , compendiumGroupEdit
    , compendiumGroupsHide
    , compendiumGroupsShow
    , compendiumImport
    , compendiumInEncounter
    , compendiumInstanceCount
    , compendiumNewCreature
    , compendiumPasteStatBlock
    , compendiumReset
    , compendiumRowSelect
    , concentrating
    , coverCycleTip
    , deathBegin
    , deathDead
    , deathRoll
    , deathStable
    , diceAdvantage
    , diceClearHistory
    , diceCoinFlip
    , diceDisadvantage
    , diceFaceRoll
    , diceReset
    , diceRollAgain
    , difficultyButton
    , dodging
    , drawerClose
    , encounterBarSpellList
    , fallDamage
    , flyHeightDown
    , flyHeightUp
    , flying
    , fullCover
    , halfCover
    , hiding
    , hpOpenManage
    , initSelectedNone
    , initiativeManager
    , inlineEditCancel
    , lastRollTotal
    , legendaryActionColumn
    , legendaryActionsPanel
    , legendaryPipLocked
    , legendaryResistanceColumn
    , lifecycleDeadToDown
    , lifecycleDownToDead
    , loadButton
    , loadRowCompendium
    , loadRowEncounter
    , manageHp
    , memoAdd
    , memoClear
    , memoEdit
    , modalClose
    , nextTurn
    , noteAdd
    , noteEdit
    , panelOpenCompendium
    , panelRandomEncounter
    , panelStatBlockNewWindow
    , pinStatBlock
    , queueDuplicate
    , queueInactive
    , queueMakeActive
    , queueMoveDown
    , queueMoveUp
    , queueReactivate
    , queueRemove
    , queueReplace
    , queueSelectShiftClick
    , quickAddButton
    , quickAddCreatureRow
    , quickAddSortToAlpha
    , quickAddSortToCr
    , quickListOpen
    , reactionReady
    , reactionSpent
    , readyAction
    , releaseReadied
    , reset
    , rollDice
    , rollDiceUnread
    , roundSet
    , runEncounter
    , saveButton
    , saveButtonDirty
    , saveChain
    , saveNoticeDismiss
    , saveRowDelete
    , saveRowOverwrite
    , saveRowRename
    , savedAgainstNotice
    , showStatBlock
    , sourceFromSaved
    , sourceUnsaved
    , specialReactionBadge
    , specialReactionSpent
    , specialReactionsPanel
    , statBlockAbilityCheck
    , statBlockAttack
    , statBlockHabitat
    , statBlockRoll
    , statBlockSavingThrow
    , statBlockShowInCompendium
    , statusBadgeEdit
    , statusEditor
    , statusOffTip
    , statusOnTip
    , tempHp
    , threeQuartersCover
    , timerCancel
    , timerRinging
    , timerRunning
    , timerSet
    , toastDismiss
    , treasureButton
    , xpFilter
    )

{-| Centralised tooltip strings.

Every `title` attribute string in the view layer that's worth
reviewing as user-facing copy lives here, grouped by feature.
The view modules import this module and reference the constants
by name; the Elm compiler then guarantees every reference
resolves and that no orphan tooltip text drifts in the codebase.

Layout:

  - **Static** tooltips are top-level `String` values, named
    after the feature they describe. Read top-to-bottom for a
    feature-by-feature audit.
  - **Dynamic** tooltips that depend on runtime values are
    one-line helper functions returning `String`. They sit at
    the bottom of the module so the static survey isn't broken
    up by combinators.

If you're reviewing or rewording: the section comments group
tooltips by where they appear in the UI (App bar, Actions
column, Card rows, Compendium page, etc.).

-}

import Html
import Html.Attributes


{-| Wrap a tooltip string as a single `data-tooltip` attribute.
Style + show-delay live in `style.css` under `[data-tooltip]`;
the CSS pseudo-element renders the tooltip at about half the
delay of the browser's native `title=` implementation (~300ms
on macOS vs the ~600ms native default).

Used everywhere the codebase previously did `title Tooltips.foo`
— same call shape, just `Tooltips.attr Tooltips.foo`. `aria-label`
on the same element continues to cover screen-reader needs.

-}
attr : String -> Html.Attribute msg
attr s =
    Html.Attributes.attribute "data-tooltip" s



-- ── APP BAR ──────────────────────────────────────────────────────────────────


appBarSettings : String
appBarSettings =
    "Set Theme"


appBarAccount : String
appBarAccount =
    "Open account settings"


appBarDonate : String
appBarDonate =
    "Support the project"



-- ── ACTIONS COLUMN ───────────────────────────────────────────────────────────


difficultyButton : String
difficultyButton =
    "Open the encounter-difficulty calculator (2024 XP budgets)"


treasureButton : String
treasureButton =
    "Roll random treasure for this encounter (SRD individual or hoard tables)"


actionGroupToggle : String
actionGroupToggle =
    "Collapse or expand this group of buttons"


quickAddButton : String
quickAddButton =
    "Quick-add a creature from the Compendium"


xpFilter : String
xpFilter =
    "Choose which creatures the XP total counts"


panelOpenCompendium : String
panelOpenCompendium =
    "Open the Creature Compendium in its own browser tab"


panelRandomEncounter : String
panelRandomEncounter =
    "Choose parameters & generate encounter"


{-| Save trigger when there are no unsaved roster changes. See
`saveButtonDirty` for the dirty variant.
-}
saveButton : String
saveButton =
    "Save the encounter"


saveButtonDirty : String
saveButtonDirty =
    "Save the encounter (unsaved roster changes)"


loadButton : String
loadButton =
    "Load a saved encounter"


reset : String
reset =
    "Reset every creature to full HP and clear conditions / status"


clear : String
clear =
    "Remove every creature and reset round to 1"


runEncounter : String
runEncounter =
    "Begin combat — highest-initiative creature acts"


nextTurn : String
nextTurn =
    "Advance to next creature in initiative order"


roundSet : String
roundSet =
    "Set the round number"


rollDice : String
rollDice =
    "Roll dice"


rollDiceUnread : String
rollDiceUnread =
    "Roll dice (new entries since last open)"


lastRollTotal : String
lastRollTotal =
    "Last roll total"



-- ── ENCOUNTER TITLE BAR (above the creature grid) ────────────────────────────


sourceUnsaved : String
sourceUnsaved =
    "from file: (unsaved)"


encounterBarSpellList : String
encounterBarSpellList =
    "List every spell the creatures in this encounter can cast"


halfCover : String
halfCover =
    "Half cover"


threeQuartersCover : String
threeQuartersCover =
    "Three-quarters cover"


fullCover : String
fullCover =
    "Total cover"


concentrating : String
concentrating =
    "Concentrating"


hiding : String
hiding =
    "Hiding"


dodging : String
dodging =
    "Dodging"


tempHp : String
tempHp =
    "Temporary hit points"


{-| Encounter title-bar AC readout — see `armorClassValue`.
-}
armorClass : Int -> String
armorClass ac =
    "Armor Class " ++ String.fromInt ac


{-| Encounter title-bar Flying icon — see helper for the full
"🪽 Nft" tooltip.
-}
flying : Int -> String
flying ft =
    "Flying — " ++ String.fromInt ft ++ " ft"



-- ── CREATURE CARD ROW 1 (queue actions) ──────────────────────────────────────


queueSelectShiftClick : String
queueSelectShiftClick =
    "Shift-click to select / deselect all"


queueMoveUp : String
queueMoveUp =
    "Move up in queue (ignores initiative)"


queueMoveDown : String
queueMoveDown =
    "Move down in queue (ignores initiative)"


queueMakeActive : String
queueMakeActive =
    "Set as active creature"


queueRemove : String
queueRemove =
    "Remove from encounter"


queueReplace : String
queueReplace =
    "Swap for a compendium pick (keeps position and initiative)"


queueDuplicate : String
queueDuplicate =
    "Duplicate creature"


{-| Tooltip on the per-card ∅ toggle. Reads asymmetrically: the
button label is the _action_ a click will perform, not the
current state — "Make inactive" when the creature is currently
active in the queue, "Make active" when they're currently
skipped. The frontend picks the right variant per creature.
-}
queueInactive : String
queueInactive =
    "Make inactive (skips turn)"


queueReactivate : String
queueReactivate =
    "Make active (returns creature to queue)"


legendaryActionsPanel : String
legendaryActionsPanel =
    "Show what each creature's legendary actions do"


specialReactionsPanel : String
specialReactionsPanel =
    "Show what each creature's special reactions do"


legendaryActionColumn : String
legendaryActionColumn =
    "Legendary Action (3, +1 Lair)"


legendaryResistanceColumn : String
legendaryResistanceColumn =
    "Legendary Resistance (3, +1 Lair)"


legendaryPipLocked : String
legendaryPipLocked =
    "Legendary actions can't be used on the creature's own turn"


specialReactionSpent : String
specialReactionSpent =
    "Spent — click to hand it back (clears at the start of their turn)"


specialReactionBadge : String
specialReactionBadge =
    "Special reactions — this creature's reactions go beyond one per round; see the stat block"



-- ── CREATURE CARD ROW 2 (initiative + state toggles) ─────────────────────────


initiativeManager : String
initiativeManager =
    "Initiative manager"


showStatBlock : String
showStatBlock =
    "Show stat block"


noteAdd : String
noteAdd =
    "Add note"


noteEdit : String
noteEdit =
    "Edit or clear note"


flyHeightUp : String
flyHeightUp =
    "Increase by 5 ft"


flyHeightDown : String
flyHeightDown =
    "Decrease by 5 ft"


fallDamage : String
fallDamage =
    "Roll falling damage (1d6 per 10 ft, max 20d6) and ground the creature"


readyAction : String
readyAction =
    "Ready an action — click to set"


releaseReadied : String
releaseReadied =
    "Action readied — click to release"


reactionReady : String
reactionReady =
    "Reaction available — click to spend (auto-resets at turn start)"


reactionSpent : String
reactionSpent =
    "Reaction spent — click to refund"



-- ── CREATURE CARD HP CLUSTER ─────────────────────────────────────────────────


clickToEdit : String
clickToEdit =
    "Click to edit"


hpOpenManage : String
hpOpenManage =
    "Open Manage HP for this creature"


manageHp : String
manageHp =
    "Manage HP — Damage, Heal, Temp HP, or +Max HP"


applyCondition : String
applyCondition =
    "Apply condition or effect"


saveChain : String
saveChain =
    "Save Chain — reusable save + effect recipe (damage / heal / apply condition on fail or success)"


bloodied : String
bloodied =
    "Bloodied — ≤ half HP"



-- ── CREATURE CARD DEATH SAVES ────────────────────────────────────────────────


deathDead : String
deathDead =
    "Dead — 3 failed death saves"


deathStable : String
deathStable =
    "Stable — 3 successful death saves"


deathRoll : String
deathRoll =
    "Roll a 1d20 death save (5e: 10+ success, ≤9 failure, nat 20 revives, nat 1 = 2 failures)"


deathBegin : String
deathBegin =
    "Reveal the death-save pip tracker for this creature"


lifecycleDownToDead : String
lifecycleDownToDead =
    "Click to mark dead (sets 3 failed death saves)"


lifecycleDeadToDown : String
lifecycleDeadToDown =
    "Click to revert to Down (clears failed death saves)"



-- ── CREATURE CARD CONDITIONS / CHIPS ─────────────────────────────────────────


chipClickToEdit : String
chipClickToEdit =
    "Click to edit"


chipDismiss : String
chipDismiss =
    "Dismiss"


chipRemoveModalRow : String
chipRemoveModalRow =
    "Remove this condition"


saveNoticeDismiss : String
saveNoticeDismiss =
    "Dismiss"



-- ── CREATURE CARD MEMO / TIMER ───────────────────────────────────────────────


{-| Shown on any inline-editor trigger while its own editor is
open — the trigger doubles as the cancel toggle.
-}
inlineEditCancel : String
inlineEditCancel =
    "Cancel (closes without saving)"


memoAdd : String
memoAdd =
    "Add memo"


memoEdit : String
memoEdit =
    "Edit memo"


memoClear : String
memoClear =
    "Clear memo"


timerSet : String
timerSet =
    "Set timer"


timerCancel : String
timerCancel =
    "Cancel timer"



-- ── STAT-BLOCK PANEL ─────────────────────────────────────────────────────────


panelStatBlockNewWindow : String
panelStatBlockNewWindow =
    "Open stat block in new tab"


statBlockShowInCompendium : String
statBlockShowInCompendium =
    "Show this creature in the Compendium tab"


statBlockHabitat : String
statBlockHabitat =
    "Inferred from online public sources"


quickListOpen : String
quickListOpen =
    "Open a read-only quick-list of the combat queue in a new tab"



-- ── STAT BLOCK (drawer panel + popouts) ──────────────────────────────────────
--
-- See helpers `statBlockSavingThrow` and `statBlockRoll` for the
-- per-ability / per-die-expression dynamic forms.
-- ── COMPENDIUM BROWSER PAGE ──────────────────────────────────────────────────


compendiumInEncounter : String
compendiumInEncounter =
    "This creature has at least one instance in the encounter"


compendiumAddedFilterOff : String
compendiumAddedFilterOff =
    "Show only creatures that have instances in the encounter"


compendiumAddedFilterOn : String
compendiumAddedFilterOn =
    "Showing only creatures with instances in the encounter — click to clear"


compendiumRowSelect : String
compendiumRowSelect =
    "Click to select; shift+click to select all (or clear selected) creatures"


compendiumInstanceCount : String
compendiumInstanceCount =
    "Instances of this creature in the encounter"


compendiumAddToEncounter : String
compendiumAddToEncounter =
    "Roll initiative and add to the encounter"


compendiumAddSelected : String
compendiumAddSelected =
    "Roll initiative for every checked creature and add them all"


compendiumEdit : String
compendiumEdit =
    "Edit this creature"


compendiumEditBundled : String
compendiumEditBundled =
    "Bundled creatures not editable. Duplicate to edit."


compendiumDuplicate : String
compendiumDuplicate =
    "Duplicate this creature in the compendium"


compendiumDelete : String
compendiumDelete =
    "Delete this creature from the compendium"


compendiumDeleteSelected : String
compendiumDeleteSelected =
    "Delete every checked creature from the compendium"


compendiumCreateGroup : String
compendiumCreateGroup =
    "Bundle creatures into a Group that adds to the encounter as a whole"


compendiumCreateGroupFromSelected : String
compendiumCreateGroupFromSelected =
    "Bundle the checked creatures into a new Group"


compendiumGroupsShow : String
compendiumGroupsShow =
    "Show groups in the compendium list"


compendiumGroupsHide : String
compendiumGroupsHide =
    "Hide groups from the compendium list"


compendiumGroupAdd : String
compendiumGroupAdd =
    "Add every creature in this group to the encounter at once"


compendiumGroupEdit : String
compendiumGroupEdit =
    "Edit this group"


compendiumGroupDelete : String
compendiumGroupDelete =
    "Delete this group from the compendium"


compendiumNewCreature : String
compendiumNewCreature =
    "Create a new creature"


compendiumPasteStatBlock : String
compendiumPasteStatBlock =
    "Paste a 5e stat block to import into Compendium"


compendiumReset : String
compendiumReset =
    "Reset Compendium to the bundled creature set (warning: clears custom & imported creatures)"


compendiumImport : String
compendiumImport =
    "Replace the current Compenidum with a saved Compendium file"


compendiumExport : String
compendiumExport =
    "Save the current Compendium"


compendiumExportDirty : String
compendiumExportDirty =
    "Save the current Compendium (unsaved changes)"


compendiumClear : String
compendiumClear =
    "Clear all creatures, or just the checked ones"


compendiumClearSelectedNone : String
compendiumClearSelectedNone =
    "No creatures are checked"


compendiumClearSelectedReady : String
compendiumClearSelectedReady =
    "Remove checked creatures"


compendiumClearTagFilter : String
compendiumClearTagFilter =
    "Clear tag filter"



-- ── COMPENDIUM EDIT MODAL ────────────────────────────────────────────────────


compendiumEditRemoveSave : String
compendiumEditRemoveSave =
    "Remove this save"


compendiumEditRemoveSkill : String
compendiumEditRemoveSkill =
    "Remove this skill"


compendiumEditRemoveEntry : String
compendiumEditRemoveEntry =
    "Remove this entry"


compendiumEditClearUsage : String
compendiumEditClearUsage =
    "Clear Usage (keeps the action)"


compendiumEditRemoveSection : String
compendiumEditRemoveSection =
    "Remove this section"


compendiumEditDeleteCreature : String
compendiumEditDeleteCreature =
    "Delete this creature from Compendium"


compendiumEditRemoveTag : String
compendiumEditRemoveTag =
    "Remove this tag"



-- ── SAVE / LOAD MODAL ROW ICONS ──────────────────────────────────────────────


saveRowOverwrite : String
saveRowOverwrite =
    "Overwrite this save with current encounter"


saveRowRename : String
saveRowRename =
    "Rename"


saveRowDelete : String
saveRowDelete =
    "Delete"


loadRowEncounter : String
loadRowEncounter =
    "Load this encounter"


loadRowCompendium : String
loadRowCompendium =
    "Load this Compendium"



-- ── DICE PANEL ───────────────────────────────────────────────────────────────


diceReset : String
diceReset =
    "Reset count to 1 and modifier to 0"


diceAdvantage : String
diceAdvantage =
    "Roll 2d20, keep highest"


diceDisadvantage : String
diceDisadvantage =
    "Roll 2d20, keep lowest"


diceCoinFlip : String
diceCoinFlip =
    "50/50 coin flip"


diceClearHistory : String
diceClearHistory =
    "Clear roll history"


diceRollAgain : String
diceRollAgain =
    "Roll this again"



-- ── INITIATIVE EDITOR ────────────────────────────────────────────────────────


initSelectedNone : String
initSelectedNone =
    "No creatures are selected — tick the checkbox for the creatures you want first"



-- ── QUICK ADD PANEL ──────────────────────────────────────────────────────────


quickAddSortToAlpha : String
quickAddSortToAlpha =
    "Switch to alphabetical order"


quickAddSortToCr : String
quickAddSortToCr =
    "Switch to challenge rating order"



-- ── MODAL CHROME / TOAST ─────────────────────────────────────────────────────


drawerClose : String
drawerClose =
    "Close this panel"


modalClose : String
modalClose =
    "Close"


toastDismiss : String
toastDismiss =
    "Dismiss"



-- ── DYNAMIC HELPERS ──────────────────────────────────────────────────────────
--
-- One per parameterised tooltip.  Kept thin so the static
-- survey above isn't broken up by template logic.


{-| Names the creature whose stat block a click will pin.
-}
pinStatBlock : String -> String
pinStatBlock name =
    "Pin " ++ name ++ "'s stat block in the Actions panel"


sourceFromSaved : String -> String
sourceFromSaved name =
    "from file: " ++ name


{-| Card status label — opens the Status editor targeting the
label's creature.
-}
statusBadgeEdit : String
statusBadgeEdit =
    "Click to edit this creature's statuses"


{-| The Actions column's Status button — opens the posture-toggle editor.
-}
statusEditor : String
statusEditor =
    "Set cover, concentration, hiding, dodging, and flying"


{-| Status-editor posture toggle (concentrate / hide / dodge
etc.) — on-state hover label. `label` is the human name of the
state (e.g. "Concentrating").
-}
statusOnTip : String -> String
statusOnTip label =
    label ++ " — click to clear"


{-| Off-state counterpart of `statusOnTip`.
-}
statusOffTip : String -> String
statusOffTip label =
    "not " ++ label ++ " — click to set"


{-| Card row 2 Cover toggle — three-state cycle through
no-cover / half / three-quarters / full.
-}
coverCycleTip : String -> String
coverCycleTip label =
    label ++ " — click to cycle"


{-| Condition chip's wrapping tooltip. `name` is the
condition's display name; `durationText` is the pre-formatted
human duration ("until end of next turn", etc.); `maybeSave` is
the save-to-end spec when one is configured.
-}
chipFullTitle :
    String
    -> String
    -> Maybe { ability : String, dc : Int }
    -> String
chipFullTitle name durationText maybeSave =
    let
        savePart =
            case maybeSave of
                Just s ->
                    " · " ++ s.ability ++ " save DC " ++ String.fromInt s.dc

                Nothing ->
                    ""
    in
    name ++ " — " ++ durationText ++ savePart


{-| Inline d20 button next to a condition chip. Composes the
"Roll {ABILITY} save (DC {DC}, bonus {BONUS})" form used on the
chip's 🎲 affordance.
-}
chipRollSave :
    { ability : String, dc : Int, bonus : String }
    -> String
chipRollSave spec =
    "Roll "
        ++ spec.ability
        ++ " save (DC "
        ++ String.fromInt spec.dc
        ++ ", bonus "
        ++ spec.bonus
        ++ ")"


{-| "Saved: {Condition}" notice chip wrapper.
-}
savedAgainstNotice : String -> String
savedAgainstNotice conditionName =
    "Saved against "
        ++ conditionName
        ++ " — auto-clears on next end-of-turn"


{-| Card timer pill — running vs. ringing forms. `phaseWord` is
"begin" or "end".
-}
timerRunning : { remaining : Int, phaseWord : String } -> String
timerRunning t =
    "Timer: "
        ++ String.fromInt t.remaining
        ++ " left, ticks at "
        ++ t.phaseWord
        ++ "-of-turn"


timerRinging : String -> String
timerRinging phaseWord =
    "Timer rang at "
        ++ phaseWord
        ++ "-of-turn — click × to dismiss"


{-| Stat-block Saving Throws chip — clickable to roll the
proficient saving throw. Renders as "Click to roll DEX saving
throw (+2)" so the GM sees the exact bonus before they click.
-}
statBlockSavingThrow : String -> Int -> String
statBlockSavingThrow label bonus =
    let
        sign =
            if bonus >= 0 then
                "+"

            else
                ""
    in
    "Click to roll "
        ++ label
        ++ " saving throw ("
        ++ sign
        ++ String.fromInt bonus
        ++ ")"


{-| Stat-block ability cell — clickable to roll an ability
check. Renders as "Click to roll CON (+7)" so the GM sees
exactly which roll fires at a glance. Used on the six
STR/DEX/CON/INT/WIS/CHA cells up top; the dedicated save chips
in the Saving Throws line carry `statBlockSavingThrow` instead.
-}
statBlockAbilityCheck : String -> Int -> String
statBlockAbilityCheck label modifier =
    let
        sign =
            if modifier >= 0 then
                "+"

            else
                ""
    in
    "Click to roll "
        ++ label
        ++ " ("
        ++ sign
        ++ String.fromInt modifier
        ++ ")"


{-| Inline dice-link button inside a stat block segment.
-}
statBlockRoll : String -> String
statBlockRoll shown =
    "Roll " ++ shown


{-| Inline attack-roll button (the `+N to hit` phrase). Reads
"Roll +7 to hit (1d20+7)" so the GM sees both the original
phrase and the actual expression the click will fire.
-}
statBlockAttack : String -> Int -> String
statBlockAttack shown mod =
    let
        signed =
            if mod >= 0 then
                "+" ++ String.fromInt mod

            else
                String.fromInt mod
    in
    "Roll " ++ shown ++ " (1d20" ++ signed ++ ")"


{-| Quick-add row tooltip identifying the creature being added.
-}
quickAddCreatureRow : String -> String
quickAddCreatureRow creatureName =
    "Add " ++ creatureName ++ " to encounter"


{-| Dice modal main face button (d4 / d6 / d8 / …).
-}
diceFaceRoll : Int -> String
diceFaceRoll faces =
    "Roll d" ++ String.fromInt faces
