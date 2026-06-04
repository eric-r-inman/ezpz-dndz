module View.Tooltips exposing
    ( addTempHp
    , appBarAccount
    , appBarCardEditor
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
    , damage
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
    , dodging
    , encounterBarDifficulty
    , fallDamage
    , flyHeightDown
    , flyHeightUp
    , flying
    , fullCover
    , halfCover
    , heal
    , hiding
    , initRollAdvantage
    , initRollDisadvantage
    , initRollStandard
    , initSelectedMany
    , initSelectedNone
    , initSelectedOne
    , initiativeManager
    , lastRollTotal
    , legendaryActionColumn
    , legendaryResistanceColumn
    , lifecycleDeadToDown
    , lifecycleDownToDead
    , loadButton
    , loadRowCompendium
    , loadRowEncounter
    , memoAdd
    , memoClear
    , memoEdit
    , modalClose
    , nextTurn
    , noteAdd
    , noteEdit
    , panelCrCalculator
    , panelOpenCompendium
    , panelStatBlockNewWindow
    , queueDuplicate
    , queueInactive
    , queueMakeActive
    , queueMoveDown
    , queueMoveUp
    , queueReactivate
    , queueRemove
    , queueSelectShiftClick
    , quickAddButton
    , quickAddCreatureRow
    , quickAddSortToAlpha
    , quickAddSortToCr
    , reactionReady
    , reactionSpent
    , readyAction
    , releaseReadied
    , reset
    , rollDice
    , rollDiceUnread
    , runEncounter
    , saveButton
    , saveButtonDirty
    , saveNoticeDismiss
    , saveRowDelete
    , saveRowOverwrite
    , saveRowRename
    , savedAgainstNotice
    , showStatBlock
    , sourceFromSaved
    , sourceUnsaved
    , statBlockAttack
    , statBlockRoll
    , statBlockSavingThrow
    , statusOffTip
    , statusOnTip
    , tempHp
    , threeQuartersCover
    , timerCancel
    , timerRinging
    , timerRunning
    , timerSet
    , toastDismiss
    , xpFilter
    , xpLairTotal
    , xpScopeEnemiesAndNpcs
    , xpScopeEnemiesOnly
    , xpScopeNpcsOnly
    , xpScopeSelectedOnly
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
tooltips by where they appear in the UI (App bar, Encounter
Controls panel, Card rows, Compendium modal, etc.); see
`docs/TOOLTIPS.org` for each tooltip's user-visible context and
back-links to the call site.

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


appBarCardEditor : String
appBarCardEditor =
    "Customize the creature card layout (prototype)"


appBarAccount : String
appBarAccount =
    "Open account settings"


appBarDonate : String
appBarDonate =
    "Support the project"



-- ── ENCOUNTER CONTROLS PANEL (right pane, top) ───────────────────────────────


quickAddButton : String
quickAddButton =
    "Quick-add a creature from the Compendium"


{-| Save split-button trigger when there are no unsaved roster
changes. See `saveButtonDirty` for the dirty variant.
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
    "Revert encounter to its last-saved state and reset round to 1"


clear : String
clear =
    "Remove every creature and reset round to 1"


runEncounter : String
runEncounter =
    "Begin combat — round 1, highest-initiative creature acts"


nextTurn : String
nextTurn =
    "Advance to next creature in initiative order"


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


xpScopeEnemiesAndNpcs : String
xpScopeEnemiesAndNpcs =
    "Total XP for enemies and NPCs"


xpScopeEnemiesOnly : String
xpScopeEnemiesOnly =
    "Total XP for enemies only"


xpScopeNpcsOnly : String
xpScopeNpcsOnly =
    "Total XP for NPCs only"


xpScopeSelectedOnly : String
xpScopeSelectedOnly =
    "Total XP for selected creatures only"


xpLairTotal : String
xpLairTotal =
    "Total XP if creature(s) fought in lair"


xpFilter : String
xpFilter =
    "Filter XP total"


encounterBarDifficulty : String
encounterBarDifficulty =
    "Open the encounter-difficulty calculator (2024 XP budgets)"


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
    "Set as active creature active"


queueRemove : String
queueRemove =
    "Remove from encounter"


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


legendaryActionColumn : String
legendaryActionColumn =
    "Legendary Action (3, +1 Lair)"


legendaryResistanceColumn : String
legendaryResistanceColumn =
    "Legendary Resistance (3, +1 Lair)"



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


damage : String
damage =
    "Apply damage"


heal : String
heal =
    "Heal hit points"


addTempHp : String
addTempHp =
    "Add temporary hit points"


applyCondition : String
applyCondition =
    "Apply condition or effect"


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



-- ── SIDE DETAIL PANEL ────────────────────────────────────────────────────────


panelOpenCompendium : String
panelOpenCompendium =
    "Open Creature Compendium"


panelCrCalculator : String
panelCrCalculator =
    "CR Calculator (not yet available)"


panelStatBlockNewWindow : String
panelStatBlockNewWindow =
    "Open stat block in new tab"



-- ── STAT BLOCK (right pane + popouts) ────────────────────────────────────────
--
-- See helpers `statBlockSavingThrow` and `statBlockRoll` for the
-- per-ability / per-die-expression dynamic forms.
-- ── COMPENDIUM BROWSER MODAL ─────────────────────────────────────────────────


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



-- ── DICE MODAL ───────────────────────────────────────────────────────────────


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



-- ── INITIATIVE MODAL ─────────────────────────────────────────────────────────


initRollStandard : String
initRollStandard =
    "Roll 1d20 + initiative bonus"


initRollAdvantage : String
initRollAdvantage =
    "Roll 2d20, keep highest, + initiative bonus"


initRollDisadvantage : String
initRollDisadvantage =
    "Roll 2d20, keep lowest, + initiative bonus"


initSelectedNone : String
initSelectedNone =
    "No creatures are selected — tick the checkbox for the creatures you want first"


initSelectedOne : String
initSelectedOne =
    "1 creature selected"



-- ── QUICK ADD MODAL ──────────────────────────────────────────────────────────


quickAddSortToAlpha : String
quickAddSortToAlpha =
    "Switch to alphabetical order"


quickAddSortToCr : String
quickAddSortToCr =
    "Switch to challenge rating order"



-- ── MODAL CHROME / TOAST ─────────────────────────────────────────────────────


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


sourceFromSaved : String -> String
sourceFromSaved name =
    "from file: " ++ name


{-| Card row 2 status toggle (concentrate / hide / dodge etc.) —
on-state hover label. `label` is the human name of the state
(e.g. "Concentrating").
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


{-| Stat-block ability cell — clickable to roll a saving throw.
-}
statBlockSavingThrow : String -> String
statBlockSavingThrow label =
    label ++ " saving throw — click to roll"


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


{-| Initiative modal "Apply & Sort: Selected" button — title
varies by selection count. See `initSelectedNone` and
`initSelectedOne` for the special-cased zero / one strings.
-}
initSelectedMany : Int -> String
initSelectedMany n =
    String.fromInt n ++ " creatures selected"


{-| Dice modal main face button (d4 / d6 / d8 / …).
-}
diceFaceRoll : Int -> String
diceFaceRoll faces =
    "Roll d" ++ String.fromInt faces
