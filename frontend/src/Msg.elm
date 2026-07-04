module Msg exposing
    ( Msg(..), MeInfo, MeStatus(..)
    , HpKind(..), HpField(..)
    , RollScope(..), RollMode(..)
    , DurationKind(..)
    , CompendiumSort(..), CompendiumField(..), FeatureGroup(..)
    , CoinField(..), CoinKind(..), CompendiumBulkMenu(..), ControlMenu(..), DamagePicker(..), FlatCategory(..), LoadSource(..), ModalChromeEdge(..), RowKind(..), SaveChainHpKind(..), SaveChainRollMode(..), SaveChainSide(..), SaveDestination(..), SubKind(..), Theme(..), TreasurePreset(..), UsageKind(..)
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
@docs HpKind, HpField
@docs RollScope, RollMode
@docs DurationKind
@docs CompendiumSort, CompendiumField, FeatureGroup

-}

import Auth
import Browser
import Browser.Dom
import Card.Wire
import Compendium
import Compendium.Group
import Compendium.Wire
import Dice
import Encounter exposing (Encounter)
import Encounter.RandomEncounter.Lore
import Encounter.Treasure
import Encounter.Wire
import Encounter.Xp exposing (XpScope)
import File exposing (File)
import Http
import Json.Decode as Decode
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


{-| Damage / Heal / Temp HP / +Max HP — the verb the modal
applies. `MaxHpKind` raises the creature's maxHp by the input
amount and adds the same amount to currentHp, mirroring the
5e Aid convention.
-}
type HpKind
    = DamageKind
    | HealKind
    | TempHpKind
    | MaxHpKind


{-| Which inline numeric value on the card is being edited.
Originally this only covered HP fields (hence the name); when AC
became click-to-edit the same machinery extended here too.
-}
type HpField
    = CurrentHpField
    | MaxHpField
    | ArmorClassField
    | TempHpField


{-| Which side of a Save Chain outcome a form-field change
targets — fail or success. Used as a discriminator on the
shared `SaveChainOutcome*` Msg branches so we don't have to
double every field's Msg surface.
-}
type SaveChainSide
    = SaveChainFail
    | SaveChainSuccess


{-| HP effect selector radio the Save Chain modal renders on
each side. Kept separate from `HpKind` (the Manage HP modal's
verbs) because the Save Chain semantics differ — notably
`SaveChainHalfFail` is a success-side sentinel that resolves
at apply-time against whatever the fail side dealt.
-}
type SaveChainHpKind
    = SaveChainNoHp
    | SaveChainDamage
    | SaveChainHeal
    | SaveChainHalfFail


{-| Roll-mode for the "🎲 Roll saves" batch. Straight = one
`1d20 + mod` per target (5e default). Advantage / Disadvantage
roll two d20s and keep the higher / lower respectively; each
target rolls independently under the chosen mode, then the
per-target totals feed the same fail / pass routing as a
straight batch.
-}
type SaveChainRollMode
    = SaveChainRollNormal
    | SaveChainRollAdvantage
    | SaveChainRollDisadvantage



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



-- ── PREFERENCES AUX ──────────────────────────────────────────────────────────


{-| Color-scheme preference. `Auto` defers to the OS pref via
the `prefers-color-scheme` media query baked into `style.css`.
Defined in `Msg` (rather than `Preferences`) so the
`PreferencesThemeSet Theme` Msg constructor can carry it
without an import cycle, mirroring the `CompendiumSort` pattern
below. `Preferences.elm` re-exports it.
-}
type Theme
    = Modern
    | Dark
    | Accessible



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


{-| Discriminator for the `Compendium.Usage` ADT variants in the
per-feature Usage editor. `UsageNone` corresponds to
`usage = Nothing`; the rest map 1:1 to the `Usage` constructors.
The edit modal pairs this with conditional param fields per
variant (Recharge low/high, Per-Day-style uses count).
-}
type UsageKind
    = UsageNone
    | UsageRecharge
    | UsagePerDay
    | UsagePerShortRest
    | UsagePerLongRest
    | UsageAtWill


{-| Discriminator for the three damage-list multi-select pickers
on the New / Edit Creature modal: vulnerabilities, resistances,
immunities. Condition immunities have their own picker (different
canonical list), so they don't share this enum.
-}
type DamagePicker
    = DamageVulnerabilitiesPicker
    | DamageResistancesPicker
    | DamageImmunitiesPicker



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


{-| Where the Load Compendium modal pulls from. Mirrors
`SaveDestination` so the radio group reads as a symmetric
Server / Device pair across both modals.
-}
type LoadSource
    = LoadSourceServer
    | LoadSourceDevice


{-| Which Encounter-Controls split-button dropdown is open.
The SaveMenu / LoadMenu options pick destination (Server vs.
Device) before the Save / Load Msg fires. Mediated by a
`Maybe ControlMenu` on `Model` so only one can be open at a
time.
-}
type ControlMenu
    = SaveControlMenu
    | LoadControlMenu


{-| Which compendium-modal split-button dropdown is currently
showing its menu. Mediated by a `Maybe CompendiumBulkMenu` field
on the compendium UI substate so only one is open at a time.
Lives in `Msg` rather than `Ui.Compendium` because the
constructor parameterizes the `CompendiumBulkMenuToggle` Msg and
`Ui.Compendium` already imports `Msg` (cycle avoidance).
-}
type CompendiumBulkMenu
    = ClearMenu
    | ImportMenu
    | ExportMenu


{-| Which row family a Treasure-Table row-edit message targets.
Individual and hoard rows share their coin-formula columns; this
discriminator lets one set of edit messages dispatch to either
table without duplicating five variants per field.
-}
type RowKind
    = IndividualRow
    | HoardRow


{-| One of the five coin denominations on a row.
-}
type CoinKind
    = CKCopper
    | CKSilver
    | CKElectrum
    | CKGold
    | CKPlatinum


{-| Which sub-tuple of the `(count, faces, mult)` coin formula
this edit targets. Edits arrive as `String` so the input box can
hold a transient empty value while the user is typing; the
handler parses + clamps.
-}
type CoinField
    = CFCount
    | CFFaces
    | CFMult


{-| One of the three hoard-only subroll categories — gems, art
objects, or magic items. Each carries its own tier/table enum
which the editor exposes as a dropdown.
-}
type SubKind
    = SKGems
    | SKArt
    | SKMagic


{-| Discriminator for the three flat (name, gp) categories —
Mundane, Weapons, Armor — in the table editor. All three share
the same shape and the same edit Msg family.
-}
type FlatCategory
    = FlatMundane
    | FlatWeapons
    | FlatArmor


{-| Named one-click presets in Tune-your-rolls. Each applies a
canned configuration to the current Kind's toggles + count knobs
so common DM intents ("coins only", "wizard's lair") don't
require the GM to toggle six fields by hand every time.
-}
type TreasurePreset
    = PresetCoinsOnly
    | PresetCoinsGems
    | PresetSrdDefault
    | PresetWizardLair
    | PresetBanditCamp



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
      -- Flip the per-creature `acceptingDeathSaves` opt-in on for
      -- a downed (0 HP) creature so the death-save pip tracker
      -- appears on its card.  Resets back to False when the
      -- creature heals above 0.
    | DeathSavesBegin String
      -- Mark a downed creature dead immediately: set their death-
      -- save failures to 3 so the predicate cascade
      -- (`isDeathSaveDead`, card class, queue skip) flips in one
      -- shot.  Fired by clicking the DOWN lifecycle badge on the
      -- card border.
    | MarkCreatureDead String
      -- Reverse of `MarkCreatureDead`: clear failures back to 0
      -- (successes preserved).  Fired by clicking the DEAD
      -- lifecycle badge so the same physical pill is a reversible
      -- toggle.
    | RevertCreatureToDown String
    | ToggleReadied String
    | ToggleReaction String
      -- Click the recharge chip on a creature's card to flip a
      -- single recharge ability between ready/expended.  Pure UI
      -- toggle; doesn't fire a dice roll.  Used by the ability-
      -- name half of the split chip (spent + active) to mark
      -- ready manually, and by the whole chip in non-active
      -- states (toggle either direction).
    | ToggleRechargeAbility String String
      -- Fire the recharge d6 for one ability on demand.  Wired
      -- to the blinking dice glyph on the spent + active chip
      -- form — recharges are no longer auto-rolled at the start
      -- of the creature's turn; the GM clicks when ready.
    | RollRechargeNow String String
      -- Result of the recharge d6 for one ability: (creature
      -- name, ability name, the d6 roll).  If roll.total >=
      -- ability.low, flip ready=True.
    | RechargeRollLanded String String Dice.Roll
    | ToggleInactive String
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
      -- Open or close the re-roll dropdown attached to a single
      -- history entry (toggle: clicking the open one closes; any
      -- other entry replaces).  `DiceRerunNoModifier` is the new
      -- menu item that re-rolls with the constant stripped from
      -- the expression.
    | DiceRerunMenuToggle Int
    | DiceRerunMenuClose
    | DiceRerunNoModifier Dice.Roll
    | DiceClearHistory
    | DiceRollLanded Dice.Roll
      -- A peer tab broadcast a freshly-landed roll over the
      -- BroadcastChannel.  Payload is the encoded `Dice.Roll`;
      -- decode failures are silently ignored.
    | DiceRollFromOtherTab Decode.Value
      -- A peer tab broadcast the latest encounter over the
      -- BroadcastChannel.  Payload is the encoded `Encounter`;
      -- the receiving handler decodes and replaces
      -- `model.encounter` in place.  No re-broadcast.
    | EncounterFromOtherTab Decode.Value
    | DiceHistoryLoaded (Result Http.Error (List Dice.Roll))
    | DicePersistResponse (Result Http.Error (List Dice.Roll))
    | DiceClearResponse (Result Http.Error ())
      -- Per-user Lore-group sync (Tier-3 feature parity with
      -- card layouts).  Fetched once on authed boot; PUT after
      -- every Save/Delete in the Lore section of the Group-
      -- Edit modal.  Anonymous users still ride localStorage.
    | LoreGroupsLoaded (Result Http.Error (List Encounter.RandomEncounter.Lore.Group))
    | LoreGroupsPersisted (Result Http.Error ())
      -- Per-user condition-preset sync.  Same flow as Lore
      -- groups: fetch on authed boot, PUT on every Save / Delete
      -- in the Add-Condition modal's preset row.  Anonymous
      -- users persist to localStorage as before.  Payload is an
      -- opaque `Decode.Value` because the preset record type
      -- lives in `Ui.Condition`, which already imports `Msg` for
      -- `DurationKind` — typing the Msg here would cycle.  The
      -- handler in Main runs `Ui.Condition.Wire.decodePresets`
      -- before adopting.
    | ConditionPresetsLoaded (Result Http.Error Decode.Value)
    | ConditionPresetsPersisted (Result Http.Error ())
      -- Save Chain presets: mirror of condition presets — GET on
      -- authenticated boot, PUT after any mutation while
      -- authenticated.  Anonymous sessions keep writing to
      -- localStorage.  Same "opaque `Decode.Value`" reasoning as
      -- above: the typed `SaveChain` record lives in
      -- `Encounter.SaveChain`, which would cycle if we referenced
      -- it here.  Decode via `Encounter.SaveChain.Wire.decodePresets`
      -- happens in `Update.UserSync`.
    | SaveChainPresetsLoaded (Result Http.Error Decode.Value)
    | SaveChainPresetsPersisted (Result Http.Error ())
    | RollFromStatBlock String Dice.Expression Int Int
      -- (creatureName, expression, clientX, clientY at click time)
    | StatBlockRollLanded Int Int Dice.Roll
      -- (clientX, clientY captured at click, the resolved roll)
    | RollPopupExpired Int
    | DiceLastTotalFlashCleared
      -- HP change modal (Manage HP button on the card).  Opens
      -- with the target creature but no committed kind — the
      -- kind is chosen when the GM clicks one of the four
      -- footer action buttons (Damage / Heal / Temp HP /
      -- +Max HP), which fires `HpChangeApplyAs kind`.
    | HpChangeOpen String
    | HpChangeClose
    | HpChangeAmountChanged String
    | HpChangeIgnoreTempToggle
    | HpChangeApplyToSelectedToggle
      -- Commits the modal's current amount as the given kind,
      -- then closes.  The amount text is parsed at commit time:
      -- an integer applies immediately; a dice formula routes
      -- through `HpChangeRollLanded` after rolling; a parse
      -- failure surfaces the error inline and leaves the modal
      -- open.
    | HpChangeApplyAs HpKind
    | HpChangeRollLanded Dice.Roll
    | HpChangeUndoLatest
      -- ── Save Chain modal ─────────────────────────────────
      -- Opens the reusable "creature makes a save; something
      -- happens" modal from the card's Save Chain button.  Form
      -- state is edited here, saved as a named preset in
      -- `localStorage.saveChainPresets`, and executed via
      -- `SaveChainApplyFail` / `SaveChainApplyPass`.
    | SaveChainOpen String
    | SaveChainClose
    | SaveChainNameChanged String
    | SaveChainAbilitySet Compendium.Ability
    | SaveChainDcChanged String
    | SaveChainDcOverrideChanged String
    | SaveChainApplyToSelectedToggle
      -- OutcomeSide + field for the shared handlers.  The tag
      -- lets one Msg cover both fail-side and success-side
      -- fields without doubling the surface.
    | SaveChainOutcomeHpKindSet SaveChainSide SaveChainHpKind
    | SaveChainOutcomeHpAmountChanged SaveChainSide String
      -- Effect list ops.  Each outcome side carries zero or
      -- more `{name, note}` rows, so field-change Msgs are
      -- indexed by row.  Add pushes a fresh blank row; remove
      -- drops the row at `idx`.
    | SaveChainOutcomeEffectAdd SaveChainSide
    | SaveChainOutcomeEffectRemove SaveChainSide Int
    | SaveChainOutcomeEffectNameChanged SaveChainSide Int String
    | SaveChainOutcomeEffectNoteChanged SaveChainSide Int String
      -- Per-effect "save-to-end" toggle.  Flips between
      -- `Nothing` (no re-save) and `Just AutoRollAtEnd` (the
      -- canonical default).  The applied condition inherits
      -- the chain's save ability + DC as its save-to-end
      -- configuration when opted in.
    | SaveChainOutcomeEffectSaveToEndToggle SaveChainSide Int
      -- Per-effect auto-roll mode picker (Manual / AtBegin /
      -- AtEnd), only meaningful when `saveToEnd` is `Just _`.
      -- Mirrors the auto-roll radio group in the standard
      -- Condition modal.
    | SaveChainOutcomeEffectAutoRollSet SaveChainSide Int Encounter.AutoRollMode
      -- Preset ops
    | SaveChainPresetPickerChanged String
    | SaveChainPresetLoad
    | SaveChainPresetSave
    | SaveChainPresetDelete
    | SaveChainReset
      -- Overwrite every bundled-named preset in
      -- `model.saveChainPresets` with the current bundled
      -- definition, then persist.  Non-bundled presets stay.
      -- Escape hatch for users whose stored bundled presets
      -- are stale from before a wire-shape refactor (e.g.
      -- Hold Person without save-to-end from pre-that-feature).
    | SaveChainRestoreBundled
    | SaveChainExportBundled
      -- Apply
    | SaveChainApplyFail
    | SaveChainApplyPass
      -- Landing point for a dice roll fired by an apply where
      -- the amount was a formula (`8d6`, `2d10+3`, …).  The
      -- side tag routes it back through the resolver so
      -- `HalfFailDamage` on Success halves the total before
      -- applying.
    | SaveChainApplyRollLanded SaveChainSide Dice.Roll
      -- "🎲 Roll saves" button — rolls d20 + save-mod for
      -- every current target and auto-applies fail / success
      -- outcomes based on each roll vs the DC.  Save mod is
      -- pulled from the target's compendium record (saving
      -- throw override, else ability modifier).  Rolls come
      -- back as a batch through `SaveChainSavesRolled`.  The
      -- `SaveChainRollMode` param picks straight d20 vs.
      -- 2d20-keep-highest (advantage) vs. 2d20-keep-lowest
      -- (disadvantage) so the same batch machinery serves all
      -- three buttons in the modal.
    | SaveChainRollSaves SaveChainRollMode
    | SaveChainSavesRolled (List ( String, Dice.Roll ))
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
      -- Duplicate picker modal: open from the card's ⧉ button,
      -- pick one of four flavors (exact / fresh / two minion variants).
    | DuplicateOpen String
    | DuplicateClose
    | DuplicateExact
    | DuplicateFresh
    | DuplicateMinionHalf
    | DuplicateMinionOne
    | DuplicatePudding
      -- Initiative manager modal
    | InitiativeOpen String
    | InitiativeClose
    | InitiativeCustomChanged String
    | InitiativeQuickSort
    | InitiativeAutoRoll RollScope RollMode
    | InitiativeApplyTarget
    | InitiativeApplySelected
      -- "Disadv. & Surprised" yellow buttons: roll initiative
      -- at disadvantage AND flag the affected creatures as
      -- surprised.  The surprised flag clears at the end of
      -- that creature's first turn (see Encounter.Lifecycle).
    | InitiativeAutoRollSurprised RollScope
      -- Manual-initiative "Apply & Sort w/ Surprised" buttons:
      -- write the typed value, sort the queue, AND flag the
      -- affected creatures as surprised.
    | InitiativeApplyTargetSurprised
    | InitiativeApplySelectedSurprised
    | InitiativeRollsLanded (List ( String, Dice.Roll ))
    | ActiveCardScrollChecked (Result Browser.Dom.Error ())
      -- Encounter-bar active-name click: scroll the panel body
      -- so the named creature's card is in view.  Uses the same
      -- machinery as `NextTurn`'s auto-scroll to a moved active,
      -- but fired by an explicit user click on the name in the
      -- info row rather than a queue advance.
    | ScrollCardIntoView String
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
      -- 1-Minute preset radio that sits alongside Countdown.
      -- Selecting it sets durationKind=Countdown, turns=10,
      -- phase=AtEnd, and flags `useOneMinutePreset` so the radio
      -- stays visually selected even though the underlying
      -- duration is Countdown.
    | ConditionDurationOneMinute
    | ConditionUntilCreatureChanged String
    | ConditionUntilPhaseSet Encounter.TurnPhase
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
      -- Save/Load presets for the Add-Condition modal.  The GM
      -- captures a fully-configured form under a user-given name
      -- so common scenarios (e.g. "Stun" with the bearer's-next-
      -- turn duration + DC 15 CON save-to-end) can be reapplied
      -- with one click.  Body is persisted to localStorage via
      -- `Ports.persistLocalConditionPresets`.
    | ConditionPresetSaveStart
    | ConditionPresetSaveNameChanged String
    | ConditionPresetSaveCategoryChanged String
    | ConditionPresetSaveCancel
    | ConditionPresetSaveSubmit
    | ConditionPresetLoadMenuToggle
    | ConditionPresetLoadMenuClose
    | ConditionPresetLoad String
    | ConditionPresetDelete String
    | ConditionPresetCategoryToggle String
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
    | TimerSetupNoteChanged String
    | TimerSetupApply
    | TimerSetupCancel
    | TimerDismiss String
      -- Save/Load presets for the Timer-setup modal.  Mirror of
      -- the ConditionPreset* family — see those docs for the
      -- save-then-name → load-then-apply flow.
    | TimerPresetSaveStart
    | TimerPresetSaveNameChanged String
    | TimerPresetSaveCancel
    | TimerPresetSaveSubmit
    | TimerPresetLoadMenuToggle
    | TimerPresetLoadMenuClose
    | TimerPresetLoad String
    | TimerPresetDelete String
      -- Compendium browser
    | CompendiumLoaded (Result Http.Error (List Compendium.Creature))
    | CompendiumOpen
    | CompendiumClose
      -- ↗ button in the Compendium modal header: opens the
      -- standalone /compendium tab (or focuses it if already
      -- open) and closes the modal.
    | CompendiumOpenInTab
      -- Continuation from the JS port: the named compendium
      -- tab couldn't be focused (never opened, or was closed
      -- by the user), so the main page should fall back to
      -- opening the modal locally.
    | CompendiumTabMissing
    | CompendiumSearchChanged String
    | CompendiumKindToggled Compendium.CreatureKind
    | CompendiumSortChanged CompendiumSort
      -- "Tag" dropdown to the right of A-Z.  Payload is the wire
      -- token ("habitat:limbo" / "tag:fire_resist" / "" for clear),
      -- decoded into a `TagFilter` by the browser handler.
    | CompendiumTagFilterChanged String
    | CompendiumSelect String
    | CompendiumAddedToggle
    | CompendiumAddToQueue String
    | CompendiumAddSelectedToQueue
      -- Group feature (Phase A: UI scaffolding only — buttons fire
      -- placeholder toasts until the modal + store land).
    | CompendiumGroupsToggle
    | CompendiumGroupCreate
    | CompendiumGroupCreateFromSelected
      -- Group browser-list interactions.
    | CompendiumGroupExpandToggle String
    | CompendiumGroupSelect String
    | CompendiumGroupDelete String
    | CompendiumGroupEditOpenExisting String
      -- Lore-group browser-list interactions.  The Compendium
      -- now surfaces lore groups as a peer of regular groups
      -- in their own section above the user-groups; selection
      -- drives the right-pane action bar / detail.
    | CompendiumLoreSectionToggle
    | CompendiumLoreExpandToggle String
    | CompendiumLoreSelect String
    | CompendiumLoreDelete String
    | CompendiumLoreAdd String
    | CompendiumLoreAddMaterialise String (List ( Compendium.Creature, Int ))
      -- Group → encounter handoff.  Like CompendiumAddToQueue
      -- but the materialiser is a separate path because it has
      -- to honour the group's initiative mode + per-entry
      -- minion overrides.
    | CompendiumGroupAdd String
      -- Response continuation: the fully-resolved spawn specs
      -- (one per spawned creature) and the dice pool to push to
      -- history (empty for manual initiative, one entry for
      -- shared-rolled, N for each-rolls).
    | CompendiumGroupAddMaterialise (List Compendium.Group.GroupSpawn) (List Dice.Roll)
      -- Boot fetch + persistence callbacks.
    | CompendiumGroupsLoaded (Result Http.Error (List Compendium.Group.Group))
    | CompendiumGroupCreated (Result Http.Error Compendium.Group.Group)
    | CompendiumGroupUpdated (Result Http.Error Compendium.Group.Group)
    | CompendiumGroupDeleted String (Result Http.Error ())
      -- Card-editor (creature-card customization) modal lifecycle.
    | CardEditorOpen
      -- Switch the encounter panel between the classic hardcoded
      -- `View.Card` renderer and the layout-driven
      -- `View.Card.Custom` renderer.
    | CustomCardLayoutToggle
    | CardEditorClose
    | CardEditorSave
    | CardEditorReset
    | CardEditorFocusRow Int
    | CardEditorRowAdd
    | CardEditorRowRemove Int
    | CardEditorRowMoveUp Int
    | CardEditorRowMoveDown Int
    | CardEditorRowAlignmentSet Int String
    | CardEditorWidgetAdd Int String
    | CardEditorWidgetRemove Int Int
    | CardEditorQueueViewSet String
    | CardEditorToggleDeathSaves
    | CardEditorToggleLegendary
      -- Saved-layout persistence (`/api/card-layouts`).
    | CardEditorLayoutNameChanged String
    | CardEditorSaveAs
    | CardEditorOverwriteConfirm
    | CardEditorOverwriteCancel
    | CardEditorLoad String
    | CardEditorDelete String
    | CardEditorLayoutsLoaded (Result Http.Error (List Card.Wire.SavedLayoutMeta))
    | CardEditorLayoutFetched (Result Http.Error Card.Wire.SavedLayout)
    | CardEditorLayoutSaved (Result Http.Error Card.Wire.SavedLayout)
    | CardEditorLayoutDeleted String (Result Http.Error ())
      -- Group-edit modal lifecycle.
    | GroupEditClose
    | GroupEditNameChanged String
    | GroupEditInitiativeModeSet String
    | GroupEditManualInitiativeChanged String
    | GroupEditEntryAdd
    | GroupEditEntryRemove Int
    | GroupEditEntryCreatureChanged Int String
    | GroupEditEntryCountChanged Int String
    | GroupEditEntryMinionTypeSet Int String
    | GroupEditSubmit
      -- Lore section embedded in the Create / Edit Group
      -- modal: expand toggles, per-group expand, new / edit /
      -- delete affordances, draft field edits.
    | GroupEditLoreUserExpandToggle
    | GroupEditLoreBundledExpandToggle
    | GroupEditLoreGroupExpandToggle String
    | GroupEditLoreNew
    | GroupEditLoreEdit String
    | GroupEditLoreDeleteRequest String
    | GroupEditLoreDeleteConfirm
    | GroupEditLoreDeleteCancel
    | GroupEditLoreDraftCancel
    | GroupEditLoreDraftSubmit
    | GroupEditLoreDraftTest
      -- Standalone Edit Lore Group modal — the lore-group CRUD
      -- now lives outside the Create/Edit Group modal so the
      -- Compendium can surface lore groups as a peer of regular
      -- groups.  These msgs mirror the GroupEditLore* set but
      -- target `ModalLoreEdit`.
    | LoreEditOpenNew
    | LoreEditOpenExisting String
    | LoreEditClose
    | LoreEditSave
    | LoreEditNameChanged String
    | LoreEditDescriptionChanged String
    | LoreEditWeightChanged String
    | LoreEditAddSearchChanged String
    | LoreEditMemberAdd String
    | LoreEditMemberRemove Int
    | LoreEditMemberRoleSet Int String
    | LoreEditMemberCountMinChanged Int String
    | LoreEditMemberCountMaxChanged Int String
    | LoreEditTest
    | GroupEditLoreDraftNameChanged String
    | GroupEditLoreDraftWeightChanged String
    | GroupEditLoreDraftMemberAdd String
    | GroupEditLoreDraftMemberRemove Int
    | GroupEditLoreDraftMemberRoleSet Int String
    | GroupEditLoreDraftMemberCountMinChanged Int String
    | GroupEditLoreDraftMemberCountMaxChanged Int String
    | GroupEditLoreAddSearchChanged String
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
      -- Per-feature Usage editor.  `UsageKind` selects which Usage
      -- ADT variant the feature should hold; the param Msgs tweak
      -- the per-variant payload (e.g. Recharge low/high, PerDay
      -- uses count).
    | CompendiumEditFeatureUsageKindSet FeatureGroup Int UsageKind
    | CompendiumEditFeatureUsageRechargeLowChanged FeatureGroup Int String
    | CompendiumEditFeatureUsageRechargeHighChanged FeatureGroup Int String
    | CompendiumEditFeatureUsageUsesChanged FeatureGroup Int String
    | CompendiumEditCustomSectionAdd
    | CompendiumEditCustomSectionRemove Int
    | CompendiumEditCustomSectionNameChanged Int String
    | CompendiumEditCustomSectionBodyChanged Int String
      -- Multi-select pickers for damage / condition lists.  Each
      -- toggle flips the named entry in or out of the picker's
      -- list.  See `DamagePicker` for the three damage variants;
      -- conditions get their own toggle since they pull from a
      -- different canonical list.
    | CompendiumEditDamageToggle DamagePicker String
    | CompendiumEditConditionToggle String
    | CompendiumEditHabitatToggle Compendium.Habitat
    | CompendiumEditTreasureToggle Compendium.Treasure
      -- Free-form user tags.  Add creates a new empty row, Remove
      -- drops the row at the index, Changed updates the row text.
      -- Validation (one-word, dedup) runs at submit time.
    | CompendiumEditTagAdd
    | CompendiumEditTagRemove Int
    | CompendiumEditTagChanged Int String
      -- Loot text-row editor on the New / Edit Creature modal.
      -- Each entry is a free-text item the GM types in (e.g.
      -- "Bone necklace", "Crumpled map fragment"); the list
      -- surfaces at the bottom of the stat block and aggregates
      -- into Treasure roller output.
    | CompendiumEditLootAdd
    | CompendiumEditLootRemove Int
    | CompendiumEditLootChanged Int String
      -- Single GM checkbox: when on, the card's reaction pip
      -- swaps the lightning glyph for a bold yellow `!` to
      -- signal "this creature has reaction mechanics worth
      -- looking up in the stat block."
    | CompendiumEditSpecialReactionsToggle
      -- Advanced section editors: legendary actions, lair actions,
      -- regional effects, spellcasting.  Each section can be
      -- entirely absent (`Nothing`); the Add / Remove Msgs flip
      -- between absent and present.  When present, per-field Msgs
      -- mutate the substructure.
    | CompendiumEditLegendaryAdd
    | CompendiumEditLegendaryRemove
    | CompendiumEditLegendaryDescriptionChanged String
    | CompendiumEditLegendaryUsesChanged String
    | CompendiumEditLegendaryUsesInLairChanged String
    | CompendiumEditLegendaryOptionAdd
    | CompendiumEditLegendaryOptionRemove Int
    | CompendiumEditLegendaryOptionNameChanged Int String
    | CompendiumEditLegendaryOptionDescriptionChanged Int String
    | CompendiumEditLairAdd
    | CompendiumEditLairRemove
    | CompendiumEditLairInitiativeChanged String
    | CompendiumEditLairDescriptionChanged String
    | CompendiumEditLairOptionAdd
    | CompendiumEditLairOptionRemove Int
    | CompendiumEditLairOptionNameChanged Int String
    | CompendiumEditLairOptionDescriptionChanged Int String
    | CompendiumEditRegionalAdd
    | CompendiumEditRegionalRemove
    | CompendiumEditRegionalDescriptionChanged String
    | CompendiumEditRegionalFadeAfterChanged String
    | CompendiumEditRegionalEffectAdd
    | CompendiumEditRegionalEffectRemove Int
    | CompendiumEditRegionalEffectNameChanged Int String
    | CompendiumEditRegionalEffectDescriptionChanged Int String
    | CompendiumEditSpellcastingAdd
    | CompendiumEditSpellcastingRemove
    | CompendiumEditSpellcastingDescriptionChanged String
    | CompendiumEditSpellcastingAbilitySet Compendium.Ability
    | CompendiumEditSpellcastingSaveDcChanged String
    | CompendiumEditSpellcastingAttackBonusChanged String
    | CompendiumEditSpellcastingAtWillChanged String
    | CompendiumEditSpellcastingSlotAdd
    | CompendiumEditSpellcastingSlotRemove Int
    | CompendiumEditSpellcastingSlotLevelChanged Int String
    | CompendiumEditSpellcastingSlotCountChanged Int String
    | CompendiumEditSpellcastingSlotSpellsChanged Int String
    | CompendiumEditSpellcastingInnateAdd
    | CompendiumEditSpellcastingInnateRemove Int
    | CompendiumEditSpellcastingInnateUsesChanged Int String
    | CompendiumEditSpellcastingInnateSpellsChanged Int String
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
      -- QuickList (`/quick-list`) row click: fires from the
      -- standalone quick-view tab.  Broadcasts a panel-show
      -- request across the BroadcastChannel so the main tab
      -- pins the stat block + scrolls the card into view, and
      -- brings itself to front via `window.opener.focus()`.
    | QuickListRowClick String String
      -- Payload from the main tab's `incomingPanelShow`
      -- subscription — a QuickList tab asked us to pin +
      -- scroll to (id, name).
    | IncomingPanelShow String String
      -- Legendary action / legendary resistance pip toggles
    | ToggleLegendaryActionPip String Int
    | ToggleLegendaryResistancePip String Int
      -- Live-encounter persistence
    | EncounterLoaded (Result Http.Error (Maybe Encounter))
    | EncounterPersisted (Result Http.Error ())
      -- Encounter Controls: Save / Load / Reset / Clear
    | SaveOpen SaveDestination
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
    | LoadSourceSet LoadSource
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
      -- Compendium snapshot Save / Load (server-side named
      -- snapshots, distinct from the live working compendium).
      -- Mirrors the encounter Save / Load modal's wire pattern;
      -- device-save / device-load reuse the existing
      -- CompendiumExportClick / CompendiumImportClick paths.
    | SaveCompendiumOpen SaveDestination
    | SaveCompendiumClose
    | SaveCompendiumDestinationSet SaveDestination
    | SaveCompendiumFilenameChanged String
    | SaveCompendiumSubmit
    | SaveCompendiumListLoaded (Result Http.Error (List Compendium.Wire.SavedCompendiumMeta))
    | SaveCompendiumPersistResponse String (Result Http.Error ())
    | SaveCompendiumOverwriteRequested String
    | SaveCompendiumConfirmCancel
    | SaveCompendiumConfirmConfirm
    | LoadCompendiumOpen
    | LoadCompendiumClose
    | LoadCompendiumSourceSet LoadSource
    | LoadCompendiumListLoaded (Result Http.Error (List Compendium.Wire.SavedCompendiumMeta))
    | LoadCompendiumFromServerRequested String
    | LoadCompendiumConfirmCancel
    | LoadCompendiumConfirmConfirm
    | LoadCompendiumServerResponse String (Result Http.Error ( List Compendium.Creature, List Compendium.Group.Group ))
      -- Encounter Controls panel: which (if any) of the
      -- Save / Load split-button dropdowns is currently open.
    | ControlMenuToggle ControlMenu
    | ControlMenuClose
    | EncounterReset
    | EncounterClear
    | EncounterAddPlaceholder
      -- Inline rename for Placeholder N cards.  The name span
      -- on a placeholder card becomes an <input> when its name
      -- matches the open rename state's target.
    | PlaceholderRenameOpen String
    | PlaceholderRenameChange String
    | PlaceholderRenameCommit
    | PlaceholderRenameCancel
      -- Quick Add modal — one-click "drop a creature into the
      -- encounter" picker (alphabetical / CR sort, click-a-row).
    | QuickAddOpen
      -- Open the picker in "swap this creature" mode.  The pick
      -- handler then replaces the named creature in place with
      -- the chosen one, preserving the old initiative.
    | QuickAddOpenForReplace String
    | QuickAddClose
    | QuickAddSortToggle
    | QuickAddSearchChanged String
    | QuickAddPick String
    | QuickAddPickPlaceholder
      -- Ability-check / saving-throw modal triggered from
      -- compendium stat blocks.  The two `Int`s are the
      -- `clientX` / `clientY` of the original click — they ride
      -- through the modal so the floating roll-result popup
      -- can anchor at the cell when the dice eventually land.
      -- `AbilityCheckOpen` fires from the six STR/DEX/... cells
      -- (1d20 + flat modifier).  `AbilitySaveOpen` fires from
      -- the inline chips in the Saving Throws property line
      -- (1d20 + proficient save bonus).  Same modal lifecycle,
      -- different labels.
    | AbilityCheckOpen String String Int Int Int
      -- (creatureName, abilityLabel, abilityModifier, clickX, clickY)
    | AbilitySaveOpen String String Int Int Int
      -- (creatureName, abilityLabel, saveBonus, clickX, clickY)
    | AbilitySaveClose
    | AbilitySaveRoll RollMode
    | AbilitySaveLanded Int Int Dice.Roll
      -- (clickX, clickY captured at original ability-cell click,
      --  the resolved roll)
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
      -- Bulk-selection + Clear dropdown.  CompendiumRowToggle's
      -- second argument is the shift-key state at click time:
      -- shift+click on an unselected creature selects every
      -- visible row; shift+click on a selected one clears.
    | CompendiumRowToggle String Bool
      -- Compendium-modal split-button dropdowns: Clear / Import /
      -- Export.  `Toggle` flips the named menu open / closed (and
      -- closes whichever other one was open); `Close` collapses
      -- everything (used by Esc + click-outside).
    | CompendiumBulkMenuToggle CompendiumBulkMenu
    | CompendiumBulkMenuClose
    | CompendiumClearAll
    | CompendiumClearSelected
    | CompendiumDeleteSelected
    | CompendiumExportClick
      -- (creatureId, displayName)
    | CompendiumPendingCancel
    | CompendiumPendingConfirm
    | CompendiumImportResponse (Result Http.Error Int)
    | CompendiumResetResponse (Result Http.Error (List Compendium.Creature))
      -- Same wire path as Import, but the response should leave
      -- the library in a "dirty" state since the user chose to
      -- discard creatures rather than restore from a file.
    | CompendiumClearResponse (Result Http.Error Int)
      -- Toast notifications
    | ToastDismiss Int
      -- User preferences (theme, density, etc.)
    | PreferencesThemeSet Theme
      -- AppBar settings popover
    | SettingsToggle
    | SettingsClose
      -- Anonymous-mode banner dismissal.  Hides the "you're
      -- browsing as a guest" strip for the rest of the session.
    | AnonymousBannerDismiss
      -- Keyboard shortcuts
    | CompendiumFocusSearch
      -- Authentication.  AuthMeReceived fires once on boot from
      -- the GET /api/auth/me probe; Login* / Register* drive the
      -- form on the AuthAnonymous screen; Logout dismantles the
      -- session.  AuthLoginResponse covers both register and
      -- login (the wire shapes are identical) so the form re-uses
      -- a single "did the request fail?" branch.
    | AuthMeReceived (Result Http.Error Auth.User)
    | AuthLoginEmailChanged String
    | AuthLoginPasswordChanged String
    | AuthLoginDisplayNameChanged String
    | AuthLoginModeChanged Auth.LoginMode
    | AuthLoginSubmit
    | AuthLoginResponse (Result Http.Error Auth.User)
    | AuthLogout
    | AuthLogoutDone (Result Http.Error ())
      -- Anonymous-mode nudge: gated controls (Save to Server, etc.)
      -- dispatch this instead of their real Msg, sending the user
      -- to the login route so they can promote into an
      -- authenticated session.
    | NavigateToLogin
      -- Cancel the sign-in form and return to the encounter page.
      -- Fired by the Cancel link on /login as well as the Esc
      -- subscription scoped to the Login route.
    | LoginCancel
      -- Login-time migration: the response to the PUT that copies
      -- an anonymous-session encounter into a named server save
      -- slot.  Carries the save-name so the success-toast can
      -- mention it; clears localStorage.encounter on success.
    | LocalEncounterMigrated String (Result Http.Error ())
      -- Same shape for the card-layout migration response.
    | LocalCardLayoutMigrated String (Result Http.Error Card.Wire.SavedLayout)
      -- Compendium migration response.  Int carries the count of
      -- creatures that landed server-side so the toast can be
      -- specific.
    | LocalCompendiumMigrated Int (Result Http.Error ())
      -- CR Calculator modal.
    | CrCalculatorOpen
    | CrCalculatorClose
    | CrCalculatorScopeSet XpScope
    | CrCalculatorPartyAdd
    | CrCalculatorPartyRemove Int
    | CrCalculatorPartyLevelSet Int String
      -- Random Encounter modal.  Party config reuses the
      -- CR Calculator's `*Party*` Msgs because the underlying
      -- `model.party` is shared between the two features.
    | RandomEncounterOpen
    | RandomEncounterClose
      -- Wire tokens for all the dropdown / pill fields —
      -- keeps the Msg payloads as `String` so the view's
      -- <select> handlers stay simple.  "" on habitat /
      -- creature type means Any.
    | RandomEncounterDifficultySet String
    | RandomEncounterScaleSet String
    | RandomEncounterHabitatSet String
      -- Multi-type picker: the view renders N+1 <select>s where
      -- N is the current number of selected types and the final
      -- slot is a blank "add another" picker.  The `Int` is the
      -- slot index; `""` removes that slot, a non-blank value
      -- sets or appends.
    | RandomEncounterCreatureTypeAt Int String
    | RandomEncounterMinionsToggle
      -- "Lore-leaning" toggle: when on, the generator prefers
      -- bundled lore groups (goblinoid warband, kobold + dragon,
      -- hag coven, etc.) over the per-slot fill.
    | RandomEncounterLoreToggle
      -- Specific-creature pin picker.  PickerToggle opens /
      -- closes the inline picker (search input + compendium
      -- list).  Search text drives an inline result list;
      -- PinAdd takes a creature id (used by both a picker
      -- click and the row's +); PinDecrement nudges count
      -- down clamped at 1; PinRemove drops the entire entry
      -- regardless of count.
    | RandomEncounterPinPickerToggle
    | RandomEncounterPinSearchChanged String
    | RandomEncounterPinAdd String
    | RandomEncounterPinDecrement String
    | RandomEncounterPinRemove String
      -- Exclude-creature picker.  Same shape as the pin
      -- picker but the chosen creatures are *filtered out* of
      -- the random roll instead of guaranteed.  No counts —
      -- exclusion is a boolean.
    | RandomEncounterExcludePickerToggle
    | RandomEncounterExcludeSearchChanged String
    | RandomEncounterExcludeAdd String
    | RandomEncounterExcludeRemove String
      -- Fire the generator with the current params.  Internally
      -- issues a `Random.generate RandomEncounterRolled` Cmd.
    | RandomEncounterGenerate
      -- Continuation: the picked groups land here.  First
      -- list is every (creature, count) row in display order;
      -- second is the creature ids that came from the minion
      -- pick, so the view can mark those rows.  An empty
      -- groups list means the filtered pool was empty.
    | RandomEncounterRolled (List ( Compendium.Creature, Int )) (List String)
      -- Commit the current roll to the encounter queue.
    | RandomEncounterAddToEncounter
      -- Treasure modal — random loot generator from the encounter
      -- title bar.  Open seeds the modal's UI state with the
      -- bracket suggested from the toughest creature's CR; the
      -- actual loot lives on `model.encounter.treasure` so it
      -- persists with the encounter.
    | TreasureOpen
    | TreasureClose
      -- 📜 button in the encounter title bar — opens a read-only
      -- modal listing every queue member's at-will / slot /
      -- innate spells, grouped by creature.
    | SpellListOpen
    | SpellListClose
    | TreasureKindSet String
    | TreasureRoll
      -- The random Generator landed; payload is the materialised
      -- TreasureRoll.  Saved straight into the encounter, which
      -- triggers the standard persist hook.
    | TreasureRolled Encounter.Treasure.TreasureRoll
      -- Per-category re-roll: dump just one slice of the loot
      -- (coins, gems, art, magic) and roll a fresh draw for it.
      -- Useful when the magic item came up off-theme but the
      -- rest of the loot is keepers.
    | TreasureRerollCategory Encounter.Treasure.Category
    | TreasureCategoryRolled Encounter.Treasure.Category Encounter.Treasure.TreasureRoll
      -- Collapse / expand the "By creature" breakdown that
      -- accompanies a Sum (all Enemies) roll.
    | TreasureContributionsToggle
      -- Per-encounter roll knobs (More/Normal/Fewer for counts,
      -- Higher/Normal/Lower for tier values).  Wire strings are
      -- ("coins" / "gems" / "art" / "magic", "fewer" / "normal" /
      -- "more") and ("gems" / "art" / "magic", "lower" / "normal" /
      -- "higher"). Reset returns every knob to Normal.
    | TreasureSettingsCountSet String String
    | TreasureSettingsValueSet String String
    | TreasureSettingsNoneSet Encounter.Treasure.Kind String Bool
    | TreasureSettingsScrollChanceSet String
    | TreasureSettingsPresetApply TreasurePreset
    | TreasureSettingsReset
      -- Named per-user profiles for "Tune your rolls" — server-
      -- backed when signed in.  See the Update.UserSync
      -- handlers + Update.Treasure.profileSave/Load/Delete.
    | TreasureProfilesLoaded (Result Http.Error Decode.Value)
    | TreasureProfilesPersisted (Result Http.Error ())
    | TreasureProfileNameChanged String
    | TreasureProfileSave
    | TreasureProfileLoad String
    | TreasureProfileDelete String
      -- Collapse / expand the "Tune your rolls" settings panel
      -- in the Treasure modal.
    | TreasureSettingsToggle
      -- Per-row delete.  The × button on each rolled treasure
      -- item removes just that item from the encounter's roll
      -- (gem/art/magic by index; coin denomination by wire
      -- string).  The matching custom-row remove lives below
      -- alongside the rest of the user-table flow.
    | TreasureCoinRemove String
    | TreasureGemRemove Int
    | TreasureArtRemove Int
    | TreasureMagicRemove Int
    | TreasureMundaneRemove Int
    | TreasureWeaponsRemove Int
    | TreasureArmorRemove Int
      -- Singular per-user Treasure Table sync.  Boot fetch lands
      -- in `TreasureTableLoaded`; every editor mutation fires
      -- `Effects.putTreasureTable` and the response lands in
      -- `TreasureTablePersisted`.  Anonymous sessions persist via
      -- `Ports.persistLocalUserTreasureTable` and skip the wire.
    | TreasureTableLoaded (Result Http.Error (Maybe Encounter.Treasure.TreasureTable))
    | TreasureTablePersisted (Result Http.Error ())
      -- Editor modal lifecycle.
    | TreasureTableOpen
    | TreasureTableClose
      -- Toggle one collapsible section's expanded state.  Section
      -- discriminator + slug get passed verbatim from the view
      -- so the editor doesn't have to know about the section
      -- catalogue.
    | TreasureTableToggleSection String String
      -- Edit the list of names for one gem / art / magic tier.
      -- `String` parameter pairs are (tier-key, new-name) for
      -- add and (tier-key, index, new-value) for edit.  Remove
      -- just takes (tier-key, index).
    | TreasureTableGemAdd String
    | TreasureTableGemEdit String Int String
    | TreasureTableGemRemoveItem String Int
    | TreasureTableArtAdd String
    | TreasureTableArtEdit String Int String
    | TreasureTableArtRemoveItem String Int
    | TreasureTableMagicAdd String
    | TreasureTableMagicEdit String Int String
    | TreasureTableMagicRemoveItem String Int
      -- Per-row edits for the Individual + Hoard bracket rows.
      -- All carry (bracketWire, rowIndex, …).  Coin/sub kinds are
      -- discriminated by the small ADTs below so a single message
      -- per field-class scales across all five coin denominations
      -- and the three hoard subroll categories.
    | TreasureTableRowAdd RowKind String
    | TreasureTableRowRemove RowKind String Int
    | TreasureTableWeightSet RowKind String Int String
    | TreasureTableCoinAdd RowKind String Int CoinKind
    | TreasureTableCoinRemove RowKind String Int CoinKind
    | TreasureTableCoinSet RowKind String Int CoinKind CoinField String
    | TreasureTableSubAdd String Int SubKind
    | TreasureTableSubRemove String Int SubKind
    | TreasureTableSubCountSet String Int SubKind String
    | TreasureTableSubFacesSet String Int SubKind String
    | TreasureTableSubTierSet String Int SubKind String
      -- Per-category flat list edits (Mundane / Weapons / Armor).
      -- Each entry is `{ name, valueGp }`; the value field is
      -- typed as String so the user can blank it while editing,
      -- the parser-on-input clamps to a non-negative Int.
    | TreasureTableFlatAdd FlatCategory
    | TreasureTableFlatNameSet FlatCategory Int String
    | TreasureTableFlatValueSet FlatCategory Int String
    | TreasureTableFlatRemove FlatCategory Int
      -- Spell-name edits per scroll level.  String key is the
      -- level wire ("cantrip", "1st", …, "9th"); structurally
      -- mirrors the gem / art / magic name editors above.
    | TreasureTableScrollAdd String
    | TreasureTableScrollEdit String Int String
    | TreasureTableScrollRemove String Int
      -- Reset the in-flight DRAFT (not the saved table) to the
      -- bundled SRD default.  The user still has to click Save
      -- for the reset to commit.
    | TreasureTableResetToBundled
      -- Commit the draft to model.userTreasureTable + close.
      -- The standard persistence hook in Main.update then fires.
    | TreasureTableSave
      -- Two-step inline confirmation for "Revert to bundled":
      -- Request flips the UI flag, Cancel backs out, Confirm
      -- drops `model.userTreasureTable` to Nothing so the app
      -- falls back to `Treasure.bundledTable`.  Only surfaced
      -- when the user actually has a saved custom table.
    | TreasureTableRevertRequest
    | TreasureTableRevertCancel
    | TreasureTableRevertConfirm
      -- Account page (`/me`) form interactions.
    | AccountDisplayNameChanged String
    | AccountProfileSubmit
    | AccountProfileSaved (Result Http.Error Auth.User)
    | AccountCurrentPasswordChanged String
    | AccountNewPasswordChanged String
    | AccountConfirmPasswordChanged String
    | AccountPasswordSubmit
    | AccountPasswordChanged (Result Http.Error ())
      -- Modal chrome (drag-to-move, edge-resize).  The chrome
      -- state lives on `model.modalChrome`; subscriptions
      -- listen for mousemove / mouseup while a gesture is in
      -- flight.  See Update.ModalChrome + Ui.ModalChrome.
    | ModalChromeDragStart Int Int
    | ModalChromeDragMove Int Int
    | ModalChromeDragEnd
    | ModalChromeResizeStart ModalChromeEdge Int Int Int Int
    | ModalChromeResizeMove Int Int
    | ModalChromeResizeEnd
    | NoOp


{-| Wire-friendly mirror of `Ui.ModalChrome.Edge`. Lives here so
the `Msg` definitions don't pull in the chrome module just for
this enum (which would invert the dependency direction).
-}
type ModalChromeEdge
    = ModalEdgeN
    | ModalEdgeS
    | ModalEdgeE
    | ModalEdgeW
    | ModalEdgeNW
    | ModalEdgeNE
    | ModalEdgeSW
    | ModalEdgeSE
