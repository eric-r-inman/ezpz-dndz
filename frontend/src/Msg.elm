module Msg exposing
    ( Msg(..), MeInfo, MeStatus(..)
    , HpKind(..), HpInputMode(..), HpField(..)
    , RollScope(..), RollMode(..)
    , DurationKind(..)
    , CompendiumSort(..), CompendiumField(..), FeatureGroup(..)
    , SaveDestination(..), XpScope(..)
    )

{-| The flat top-level message type for the application + the
auxiliary value types referenced by `Msg` constructors.

Pulled out of `Main.elm` so per-feature `Update/*` modules can
import from a stable surface without dragging in the entire
application shell.

The non-`Msg` types here are the message-shaped enums (HP-edit
verb, condition-duration kind, initiative roll scope, etc.) plus
`MeInfo` / `MeStatus`, which `Msg.GotMe` transports. Larger
modal-state record types (`HpChangeUi`, `ConditionUi`, etc.)
stay in `Main.elm` for now and are scheduled for per-feature
`Ui.elm` extraction in a follow-up.

@docs Msg, MeInfo, MeStatus
@docs HpKind, HpInputMode, HpField
@docs RollScope, RollMode
@docs DurationKind
@docs CompendiumSort, CompendiumField, FeatureGroup

-}

import Browser
import Browser.Dom
import Compendium
import Dice
import Encounter exposing (Encounter)
import Encounter.Wire
import File exposing (File)
import Http
import Url exposing (Url)



-- ── USER / AUTH ──────────────────────────────────────────────────────────────


{-| Server-side user record returned by `/me`. `name` is the
display label; `authEnabled` flips false when the server runs
without OIDC configured (local-dev mode), in which case the name
is the stub `"admin"`.
-}
type alias MeInfo =
    { name : String
    , authEnabled : Bool
    }


{-| Loading state for the `/me` request. Drives the app-bar
identity badge.
-}
type MeStatus
    = Loading
    | Loaded MeInfo
    | Failed



-- ── HP-CHANGE AUX ────────────────────────────────────────────────────────────


{-| Damage / Heal / Temp HP — the verb the modal applies.
-}
type HpKind
    = DamageKind
    | HealKind
    | TempHpKind


{-| Manual integer entry vs. dice expression. The modal toggles
between the two via radio buttons; submitting in dice mode rolls
once and applies the total.
-}
type HpInputMode
    = ManualMode
    | DiceMode


{-| Which inline numeric value on the card is being edited.
Originally this only covered HP fields (hence the name); when AC
became click-to-edit the same machinery extended here too.
-}
type HpField
    = CurrentHpField
    | MaxHpField
    | ArmorClassField



-- ── INITIATIVE AUX ───────────────────────────────────────────────────────────


{-| Whether an initiative auto-roll applies to the click target,
the entire queue, or only selected creatures.
-}
type RollScope
    = ScopeTarget
    | ScopeAll
    | ScopeSelected


{-| Roll-mode for initiative auto-roll: standard 1d20, 5e
advantage (2d20-keep-highest), or 5e disadvantage
(2d20-keep-lowest).
-}
type RollMode
    = ModeStandard
    | ModeAdvantage
    | ModeDisadvantage



-- ── CONDITION AUX ────────────────────────────────────────────────────────────


{-| Three duration shapes the condition modal exposes:

  - `DurKindManual` — sticks until the GM removes it.
  - `DurKindUntilTurn` — expires at begin/end of a referenced
    creature's current or next turn.
  - `DurKindCountdown` — N of the bearer's own turns.

This is the modal-radio enum that the user picks from; it gets
projected into the domain `Encounter.Duration` ADT on submit.

-}
type DurationKind
    = DurKindManual
    | DurKindUntilTurn
    | DurKindCountdown



-- ── COMPENDIUM AUX ───────────────────────────────────────────────────────────


{-| Sort order for the compendium list.
-}
type CompendiumSort
    = SortName
    | SortCr
    | SortRecency


{-| Discriminator for the compendium edit modal's many string
fields. Each constructor names one field; a single
`CompendiumEditFieldChanged CompendiumField String` Msg covers
all of them, then the update branch uses the discriminator to
route the new value to the right place on the form record.
-}
type CompendiumField
    = CFName
    | CFRace
    | CFSubrace
    | CFAlignment
    | CFSource
    | CFDescription
    | CFArmorClass
    | CFArmorClassNote
    | CFMaxHp
    | CFHpFormula
    | CFInitiativeBonus
    | CFSpeedWalk
    | CFSpeedFly
    | CFSpeedSwim
    | CFSpeedClimb
    | CFSpeedBurrow
    | CFAbilityStr
    | CFAbilityDex
    | CFAbilityCon
    | CFAbilityInt
    | CFAbilityWis
    | CFAbilityCha
    | CFSensesBlindsight
    | CFSensesDarkvision
    | CFSensesTremorsense
    | CFSensesTruesight
    | CFSensesPassivePerception
    | CFDamageVulnerabilities
    | CFDamageResistances
    | CFDamageImmunities
    | CFConditionImmunities
    | CFLanguages
    | CFChallengeRating
    | CFXp
    | CFXpInLair
    | CFProficiencyBonus


{-| Discriminator for the four `List Feature` slots on a
creature: traits, actions, bonus actions, reactions. The edit
modal renders a separate row group for each, but the
add/remove/edit Msg constructors are parameterized over this
enum to avoid four nearly-identical Msg families.
-}
type FeatureGroup
    = TraitsGroup
    | ActionsGroup
    | BonusActionsGroup
    | ReactionsGroup



-- ── SAVE / LOAD AUX ──────────────────────────────────────────────────────────


{-| Where the Save button writes when submitted.

  - `SaveDestinationServer` — POST/PUT to the server's named-save
    store under the user's account.
  - `SaveDestinationDevice` — trigger a `File.Download` of the
    encoded encounter so the GM can keep it on their own machine.

This is a pure UI enum; the server side doesn't care which mode
was used because it only sees the half of the flow that uses it.

-}
type SaveDestination
    = SaveDestinationServer
    | SaveDestinationDevice



-- ── ENCOUNTER XP AUX ─────────────────────────────────────────────────────────


{-| Which slice of the encounter contributes to the title-bar XP
total. Controls the dropdown to the right of the XP readout.

  - `ScopeXpEnemiesAndNpcs` — every non-Player creature. Default.
  - `ScopeXpEnemiesOnly` — Enemy-tagged creatures only.
  - `ScopeXpNpcsOnly` — NPC-tagged creatures only.
  - `ScopeXpSelectedOnly` — whichever creatures the GM has ticked
    via the row 1 multi-select checkboxes (Player kind still
    excluded).

Player-kind creatures never grant XP regardless of scope; they're
the party, not the budget.

-}
type XpScope
    = ScopeXpEnemiesAndNpcs
    | ScopeXpEnemiesOnly
    | ScopeXpNpcsOnly
    | ScopeXpSelectedOnly



-- ── MSG ──────────────────────────────────────────────────────────────────────


{-| The flat top-level message type. Future per-feature
extraction may wrap subsets in nested types (`Msg = DiceMsg
Update.Dice.Msg | ...`); for now everything is one ADT.
-}
type Msg
    = UrlRequested Browser.UrlRequest
    | UrlChanged Url
    | GotMe (Result Http.Error MeInfo)
    | NextTurn
    | SetActive String
    | CycleCover String
    | ToggleConcentration String
    | ToggleHiding String
    | ToggleDodging String
    | ToggleFlying String
    | AdjustFlyHeight String Int
    | RollFallDamage String
    | FallDamageLanded String Dice.Roll
    | DeathSaveToggleSuccess String Int
    | DeathSaveToggleFailure String Int
    | DeathSaveRoll String
    | DeathSaveRollLanded String Dice.Roll
    | ToggleHolding String
      -- Dice modal
    | OpenDice
    | CloseDice
    | DiceInputChanged String
    | DiceCountChanged String
    | DiceModifierChanged String
    | DiceResetSliders
    | DiceRollFromInput
    | DiceRollFaces Int
    | DiceRollAdvantage
    | DiceRollDisadvantage
    | DiceFlipCoin
    | DiceRerun Dice.Roll
    | DiceClearHistory
    | DiceRollLanded Dice.Roll
    | DiceHistoryLoaded (Result Http.Error (List Dice.Roll))
    | DicePersistResponse (Result Http.Error (List Dice.Roll))
    | DiceClearResponse (Result Http.Error ())
    | RollFromStatBlock String Dice.Expression
      -- HP change modal
    | HpChangeOpen String HpKind
    | HpChangeClose
    | HpChangeModeSet HpInputMode
    | HpChangeAmountChanged String
    | HpChangeExpressionChanged String
    | HpChangeIgnoreTempToggle
    | HpChangeApplyToSelectedToggle
    | HpChangeApply
    | HpChangeRollLanded Dice.Roll
    | HpChangeUndoLatest
      -- Inline HP edit on the creature card
    | HpEditStart String HpField Int
    | HpEditChange String
    | HpEditCommit
    | HpEditCancel
      -- Selection
    | ToggleSelected String
    | ShiftToggleSelected
      -- Manual queue reordering
    | MoveCreatureUp String
    | MoveCreatureDown String
      -- Roster mutation (right rail × / ⧉ buttons)
    | RemoveCreature String
    | DuplicateCreature String
      -- Initiative manager modal
    | InitiativeOpen String
    | InitiativeClose
    | InitiativeCustomChanged String
    | InitiativeQuickSort
    | InitiativeAutoRoll RollScope RollMode
    | InitiativeApplyTarget
    | InitiativeApplySelected
    | InitiativeRollsLanded (List ( String, Dice.Roll ))
    | ActiveCardScrollChecked (Result Browser.Dom.Error ())
      -- Note-edit modal (the row 1 pencil button)
    | NoteEditOpen String String
    | NoteEditChange String
    | NoteEditCommit
    | NoteEditCancel
      -- Condition / effect modal
    | ConditionOpenNew String
    | ConditionOpenEdit String Int
    | ConditionClose
    | ConditionPickStandard String
    | ConditionCustomNameChanged String
    | ConditionNoteChanged String
    | ConditionDurationKindSet DurationKind
    | ConditionUntilCreatureChanged String
    | ConditionUntilPhaseSet Encounter.TurnPhase
    | ConditionUntilTargetSet Encounter.TurnTarget
    | ConditionCountdownTurnsChanged String
    | ConditionCountdownPhaseSet Encounter.TurnPhase
    | ConditionSaveToggle
    | ConditionSaveAbilityChanged String
    | ConditionSaveDcChanged String
    | ConditionSaveBonusChanged String
    | ConditionSaveAutoRollSet Encounter.AutoRollMode
    | ConditionApplyToSelectedToggle
    | ConditionSubmit
    | ConditionDelete
    | ConditionRemoveChip String Int
    | ConditionRollSave String Int
    | ConditionSaveLanded String Int Int Bool Dice.Roll
      -- (creature, condition id, dc, wasAutoRoll, roll)
    | SaveNoticeDismiss String Int
      -- Card row 3 memo
    | MemoOpen String
    | MemoChange String
    | MemoCommit
    | MemoCancel
    | MemoClear String
      -- Card row 3 timer
    | TimerOpen String
    | TimerSetupTurnsChanged String
    | TimerSetupPhaseSet Encounter.TurnPhase
    | TimerSetupApply
    | TimerSetupCancel
    | TimerDismiss String
      -- Compendium browser
    | CompendiumLoaded (Result Http.Error (List Compendium.Creature))
    | CompendiumOpen
    | CompendiumClose
    | CompendiumSearchChanged String
    | CompendiumKindToggled Compendium.CreatureKind
    | CompendiumSortChanged CompendiumSort
    | CompendiumSelect String
    | CompendiumAddCountChanged String
    | CompendiumAddToQueue String
    | CompendiumInitiativeRolled String (List ( String, Dice.Roll ))
      -- (creatureId, [(displayName, roll)])
      -- Compendium edit / create modal
    | CompendiumEditNew
    | CompendiumEditExisting
    | CompendiumEditDuplicate
    | CompendiumEditCancel
    | CompendiumEditFieldChanged CompendiumField String
    | CompendiumEditKindSet Compendium.CreatureKind
    | CompendiumEditSizeSet Compendium.Size
    | CompendiumEditSpeedHoverToggle
    | CompendiumEditSavingThrowAdd
    | CompendiumEditSavingThrowRemove Int
    | CompendiumEditSavingThrowAbilitySet Int Compendium.Ability
    | CompendiumEditSavingThrowBonusChanged Int String
    | CompendiumEditSkillAdd
    | CompendiumEditSkillRemove Int
    | CompendiumEditSkillNameChanged Int String
    | CompendiumEditSkillBonusChanged Int String
    | CompendiumEditFeatureAdd FeatureGroup
    | CompendiumEditFeatureRemove FeatureGroup Int
    | CompendiumEditFeatureNameChanged FeatureGroup Int String
    | CompendiumEditFeatureDescriptionChanged FeatureGroup Int String
    | CompendiumEditCustomSectionAdd
    | CompendiumEditCustomSectionRemove Int
    | CompendiumEditCustomSectionNameChanged Int String
    | CompendiumEditCustomSectionBodyChanged Int String
    | CompendiumEditSubmit
    | CompendiumEditSubmitResponse (Result Http.Error Compendium.Creature)
    | CompendiumEditDelete
    | CompendiumEditDeleteResponse String (Result Http.Error ())
      -- (id, result)
      -- Compendium paste / parse modal
    | CompendiumPasteOpen
    | CompendiumPasteCancel
    | CompendiumPasteTextChanged String
    | CompendiumPasteApply
      -- Pin a compendium creature's stat block in the side panel
    | PanelShowCreature String String
      -- (compendium id, encounter creature display name)
      -- Legendary action / legendary resistance pip toggles
    | ToggleLegendaryActionPip String Int
    | ToggleLegendaryResistancePip String Int
      -- Live-encounter persistence
    | EncounterLoaded (Result Http.Error (Maybe Encounter))
    | EncounterPersisted (Result Http.Error ())
      -- Encounter Controls: Save / Load / Reset / Clear
    | SaveOpen
    | SaveClose
    | SaveDestinationSet SaveDestination
    | SaveFilenameChanged String
    | SaveSubmit
    | SaveListLoaded (Result Http.Error (List Encounter.Wire.SavedEncounterMeta))
    | SavePersistResponse String (Result Http.Error ())
    | SaveOverwriteRequested String
    | SaveDeleteRequested String
    | SaveConfirmCancel
    | SaveConfirmConfirm
    | SaveDeleteResponse String (Result Http.Error ())
    | SaveRenameStart String
    | SaveRenameChange String
    | SaveRenameSubmit
    | SaveRenameCancel
    | SaveRenameResponse { from : String, to : String } (Result Http.Error ())
    | LoadOpen
    | LoadClose
    | LoadFromServerRequested String
    | LoadConfirmCancel
    | LoadConfirmConfirm
    | LoadServerResponse String (Result Http.Error Encounter)
    | LoadDeleteRequested String
    | LoadDeleteResponse String (Result Http.Error ())
    | LoadRenameStart String
    | LoadRenameChange String
    | LoadRenameSubmit
    | LoadRenameCancel
    | LoadRenameResponse { from : String, to : String } (Result Http.Error ())
    | LoadListLoaded (Result Http.Error (List Encounter.Wire.SavedEncounterMeta))
    | LoadFromDeviceClick
    | LoadFromDeviceFileChosen File
    | LoadFromDeviceFileRead String
    | EncounterReset
    | EncounterClear
      -- Quick Add modal — one-click "drop a creature into the
      -- encounter" picker (alphabetical / CR sort, click-a-row).
    | QuickAddOpen
    | QuickAddClose
    | QuickAddSortToggle
    | QuickAddPick String
      -- Saving-throw modal triggered from compendium ability cells
    | AbilitySaveOpen String String Int
      -- (creatureName, abilityLabel, saveBonus)
    | AbilitySaveClose
    | AbilitySaveRoll RollMode
    | AbilitySaveLanded Dice.Roll
    | EncounterControlConfirm
    | EncounterControlCancel
    | EncounterRun
    | XpScopeSet XpScope
    | XpFilterToggle
    | XpFilterClose
      -- Bulk: import / export / reset / delete-from-browser
    | CompendiumImportClick
    | CompendiumImportFileChosen File
    | CompendiumImportFileRead String
    | CompendiumResetClick
    | CompendiumDeleteFromBrowser String String
      -- (creatureId, displayName)
    | CompendiumPendingCancel
    | CompendiumPendingConfirm
    | CompendiumImportResponse (Result Http.Error Int)
    | CompendiumResetResponse (Result Http.Error (List Compendium.Creature))
      -- Toast notifications
    | ToastDismiss Int
      -- Keyboard shortcuts
    | CompendiumFocusSearch
    | NoOp
