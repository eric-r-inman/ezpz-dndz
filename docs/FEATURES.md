#+title:     eZpZ-dndZ — Features
#+subtitle:  A guide to every feature in the combat manager
#+language:  en

* Welcome

~eZpZ-dndZ~ is a fre DnD combat encounter manager. It handles initiative order, hit points, conditions, and much more — offloading combat miuntae from the DM's brain, so they can stay focused on the story. 

* License

eZpZ-dndZ is source-available under the *PolyForm Strict License
1.0.0*: noncommercial / personal use only; no distribution, forks,
modifications, or derivative works.  See the project ~LICENSE~ file
for the full text.

* This Document

This document is a feature-by-feature tour: what each feature is for,
where to find it in the UI, and how to use it.
** A note on beta status

** Note on Beta testing

eZpZ-dndZ is in active beta. The core encounter loop (initiative, HP,
conditions, dice roller, etc.) is stable, probably, as perhaps is the server. But, breaking changes can happen without warning. Use this app at your own risk.

Your feedback is welcome and will guide the development of this app. Use the *Leave Feedback* link on the Account page, the *Contact* link in the footer, or email ~feedback@ezpzdndz~ directly.

** Conventions in this document

- Buttons are referred to by their visible label and emoji where
  applicable (e.g. "🎲 Roll").
- "The encounter" means the live queue of creatures currently in
  combat.
- "The compendium" means your personal monster library — the
  catalogue you build encounters from.

* Getting started

** Creating an account

Visit the site and you'll be greeted by the *Authentication Portal*.

- *Create Account* — An account allows you to save and import encounters and monsters. You'll be logged in automatically after registration.
- *Sign In* — for returning users.  The email and password are the
  same ones you registered with.

Sessions are cookie-based and survive browser restarts.  Closing the
tab does not log you out.

** Signing out

Signing out clears your session and clears the active encounter. You sign out via the Account page.

* eZpZdndZ Tools

The main browser window is split into three regions:

1. *Left/center* — the *Encounter Panel*: Round tracker/creature status bar, plus the creature cards in the active encounter.
2. *Upper Right* — the *Encounter controls* for adancing the turn, loading and saving encounters, etc.
3. *Lower Right* — the *Compendium Panel*: access to the monster library and CR Calculator, and a pinned stat block with quick-roll links.

** The Encounter Status Bar

The bar above the creature queue shows the abbreviated status of the active creature.

*Left cluster*

- *Source indicator (ⓘ)* — hover to see whether the current encounter
  is unsaved or the filename it was loaded from.
- *Round counter* — e.g. "Round 5".  Increments when a full turn
  cycle completes.
- *Active creature summary* — the current creature's name, HP (click
  to edit inline), AC (click to edit inline), and any note.
- *State icons* — quick-glance badges for the active creature's
  cover, concentration, hiding, dodging, and flying status (with fly
  height when airborne).
- *Condition chips* — every condition currently on the active
  creature.  Click a chip to edit or remove it; click the 🎲 icon on
  a chip to roll its save-to-end.

*Right cluster*

- *Encounter XP* — total XP of creatures in the current scope.
- *XP scope filter* — drop-down: Enemies & NPCs, Enemies Only, NPCs
  Only, or Selected Only.  Changes what counts toward both this
  readout and the CR Calculator.
- *Difficulty button* — opens the *CR Calculator* (see below) with
  the current XP scope pre-selected.
- *Lair XP note* — appears when one or more creatures has a different
  XP value in their lair.

** Creature Cards

Each creature in the queue is a card with up to five columns: a left
rail, a three-row center column, an optional death-saves column, an
optional legendary-pips column, and a right rail.

*** Left rail — queue position

- *Select checkbox* — click to mark this creature as selected.
  Shift-click extends the selection across a range of cards.
- *Move Up (↑) / Move Down (↓)* — reorder this creature in the queue.
- *Make Active (→)* — make this creature take the current turn.

*** Center column — Row 1 — identity

- *Initiative badge* — the dark circle showing this creature's
  initiative value.
- *Creature name* — click to pin this creature's stat block to the
  Compendium Panel on the right.  Names automatically get a numeric
  suffix ("Goblin 2") for duplicates.
- *Note pencil (✏️)* — opens the *Note* modal to set a short label
  (~40 chars, displayed in italics).  Useful for "boss",
  "summoned by Lyra", or "ally".
- *AC* — click to edit inline.
- *Condition chips* — one per active condition.  Each chip carries a
  name, an optional note, a 🎲 button to roll a save-to-end (when
  the condition has one configured), and an × to remove it.

*** Center column — Row 2 — HP and toggles

- *HP display* — "current / max" with optional "+N temp" suffix.
  Click any of current, max, or temp to edit inline.
- *Bloodied marker* — surfaces when HP drops below 50% of max.
- *Cover cycle (⬜/◻/◭/⬛)* — click to step through None → Half →
  Three-Quarters → Full cover.
- *Concentration (✨)* — toggle on/off.
- *Hiding (👁‍🗨)* — toggle on/off.
- *Dodging (🛡️)* — toggle on/off.
- *Flying (⬆️)* — toggle on/off.  When on, an input appears for fly
  height in feet.

*** Center column — Row 3 — actions and per-card extras

- *Damage (🔴)* — opens the *HP Change* modal in damage mode.
- *Heal (💚)* — opens *HP Change* in heal mode.
- *Temp HP (🌡️)* — opens *HP Change* in temp-HP mode.
- *Condition (⚡)* — opens the *Condition* modal to add a new
  condition (or several across selected creatures).
- *Ready (✋)* — toggle "readied action" (2024 MM terminology;
  was "hold action" in 2014).  A creature with a readied action
  skips its turn until the GM releases the readied state.
- *Memo slot* — a tiny inline label (up to 15 chars), e.g. "leg
  res used".  Click to edit.
- *Timer slot (⏱️)* — opens the *Timer* modal to attach a countdown
  to the card.

*** Right rail — destruction and visibility

- *Remove (×)* — pop this creature out of the encounter.
- *Inactive toggle (⧉)* — keep the card visible but exclude it from
  the turn order.  Useful for downed enemies you want to remember.
- *Duplicate (⧉ second group)* — opens the *Duplicate* picker with
  five options (see below).

*** Optional — Death Saves column

When a creature drops to 0 HP, a column of three success circles and
three failure × marks appears.  Click any circle or × to toggle it.

- *Roll Death Save (🎲)* — auto-rolls 1d20.  A roll of 10 or higher
  is a success; 9 or lower is a failure; natural 20 returns the
  creature to 1 HP; natural 1 counts as two failures.
- The card flips to *Stable* (one success after rest) or *Dead*
  (three failures) automatically.

*** Optional — Legendary pips column

When the pinned stat block has legendary actions or *Legendary
Resistance*, the card grows a small column of pip indicators.  Click
each pip to mark it used/available — handy for tracking "1/day"
resources without leaving the table.

** Encounter Controls (middle cluster)

The middle pane is where global encounter actions live.

*** Dice quick-roll cluster

- *Last total* — a flashing readout of the most recent dice result.
- *Expand arrow (→)* — toggles the inline dice-history strip.
- *Roll (🎲)* — opens the full *Dice Roller* (see *Dice* below).

*** Action grid (six buttons, three rows of two)

1. *Quick Add (➕)* — lightweight creature picker.  See *Quick Add*.
2. *Save (💾)* — split button:
   - Click the main face to save to the server.
   - Click the dropdown to choose *Save to Server* or *Download to
     Device*.
   - The face turns orange/yellow when the encounter has unsaved
     changes.
3. *Load (📂)* — split button:
   - Main face / dropdown distinguish between *Load from Server* and
     *Load from Device*.
4. *Next Turn / Run (>❯ / ▶)* — advances the turn.  Before round 1
   the label is *Run* and pressing it kicks off combat (rolls
   initiative-tied effects, ticks per-turn countdowns).  After that,
   the label switches to *Next Turn*.
5. *Reset (⟲)* — reverts the encounter to the last saved snapshot
   and forces the round counter to 1.  Asks for confirmation first.
6. *Clear (🗑)* — empties the encounter back to a blank slate.  Also
   asks for confirmation.

The Reset and Clear buttons swap into an inline *Confirm / Cancel*
banner when pressed — there is no system dialog to dismiss; just hit
*Confirm* to proceed or *Cancel* to back out.

* Combat actions

** HP changes (damage, heal, temp HP)

The HP Change modal is shared across damage, heal, and temp HP.

- *Mode toggle* — Manual (type a flat integer) or Roll Dice (type a
  dice expression like ~2d6+3~).  Roll Dice rolls once and applies
  the total.
- *Ignore temp HP* — when applying damage, deplete temp HP first.
- *Apply to selected creatures* — if any creatures are multi-
  selected, the same amount is applied to all of them.  Each gets
  its own log entry.
- *Preview* — the modal shows what the creature's HP will be after
  the change before you commit.
- *HP Change Log* — recent damage/heal entries for the creature.
  Useful for "wait, how much did I just take?" moments.

You can also click a creature's current HP, max HP, AC, or temp HP
directly on the card to edit it inline without opening the modal.

** Initiative

Open the *Initiative* modal from a creature's initiative badge.  The
modal offers four kinds of actions, all of which sort the queue
automatically after they finish:

- *Quick Sort* — re-sorts the queue by current initiative values.
- *Roll & Sort: This / All / Selected* — rolls 1d20 + initiative
  bonus for the chosen scope.  Each scope has Advantage (2d20 keep
  high) and Disadvantage (2d20 keep low) variants.
- *Custom value* — type an integer and apply it to either the target
  creature or every selected creature.

** Conditions

The *Condition* modal serves both creation and editing.

- *Standard condition* — radio buttons for all 15 standard 5e
  conditions; selecting one pre-fills the name.
- *Custom name* — override or write a free-form name (e.g.
  "Suppressed", "Bardic inspiration").
- *Note* — a 10-char hint, shown on the chip ("from Lyra", "DC 13").
- *Duration* — three modes:
  - *Manual* — sticks until the GM removes it.
  - *Until Turn* — expires at the begin or end of another creature's
    current or next turn.  Pick the creature, the phase, and whether
    "current" or "next" turn.
  - *Countdown* — ticks down N of the bearer's own turns, at begin
    or end of turn.
- *Save-to-end* — optional.  When enabled, the condition includes
  an ability, DC, and bonus; you can choose Manual (you click the 🎲
  on the chip to roll it), or Auto-roll at the begin or end of the
  bearer's turn.
- *Apply to selected creatures* — when creating a new condition with
  multiple creatures selected, this checkbox splats independent
  copies onto each (different IDs, independent durations).

When you click 🎲 on a chip, a minimal save-roll modal shows the
expression and offers normal, Advantage, and Disadvantage roll
buttons.  Auto-rolling conditions fire silently at the configured
turn phase, popping a floating "+N" result above the card.

** Death saves

Already covered above in the card column section.  In short: at 0 HP
a column appears; click to toggle results manually or hit *Roll Death
Save* to roll 1d20.  Natural 20 = back to 1 HP; natural 1 = two
failures; three successes = stable; three failures = dead.

** Readying an action

The *Ready (✋)* toggle on row 3 marks a creature as readying an
action this turn.  Their turn is skipped in the rotation until
you turn the toggle back off.  (2024 Monster Manual terminology;
previous "hold action" wording referred to the same mechanic.)

** Memos and timers

Two small per-card slots on row 3.

- *Memo* — a 15-char persistent label on the card itself, ideal for
  resource tracking.  Click to edit; click again with empty text to
  clear.
- *Timer* — a turn-based countdown.  Configure how many of the
  bearer's turns it should last, whether it ticks at the begin or
  end of their turn, and an optional 10-char label.  When the
  countdown reaches 0 the card flashes a 0 and the page plays a
  short ping; click × on the timer to dismiss it.

* The Dice Roller

Open from the *🎲 Roll* button in the middle pane.

- *Expression input* — type any dice expression (e.g. ~3d8+5~,
  ~4d6kh3~ for "drop lowest", ~2d20kh1~ for advantage).  Press
  *Enter* or click *Roll*.  Parse errors surface inline.
- *Count and modifier* — sliders that prefix the next die-face roll.
  Setting count to 3 and modifier to +5 then clicking *d6* rolls
  ~3d6+5~.  The ❌ button resets them to 1 and 0.
- *Die-face buttons* — d4, d6, d8, d10, d12, d20, d100.  One-click
  rolls using the current count + modifier.
- *Advantage / Disadvantage / Coin* — quick rolls for the table's
  most common shapes.
- *Roll history* — up to 30 entries, newest first.  Click any past
  roll to re-run it (appends a new entry).  *Clear History* wipes the
  list (with confirmation).

Roll history is persisted to your account — it survives logout and
appears on other devices when you sign back in.

* Quick Add

Open from the *➕ Quick Add* button.  This is the fastest way to drop
a creature into the encounter without leaving the table view.

- *Sort toggle* — switch the list between alphabetical and CR order.
- *Creature list* — every creature in your compendium, with its CR
  on the right.  Click a row to add one instance to the encounter at
  full HP with no conditions.

Use Quick Add when you know what you want; use the full Compendium
when you want to read stat blocks first.

* The Compendium

The Compendium is your personal monster library.  It powers Quick
Add, the right-panel stat block, and the encounter's per-creature
data (initiative bonuses, AC, max HP, traits, etc.).

** Opening the Compendium

Click *📖 Open* on the right Compendium Panel.  The library opens as
a two-column modal: a filterable list on the left, a stat block and
action bar on the right.

** Browsing and filtering

- *Search* — live filter as you type.  Matches against creature
  name.
- *Kind toggles* — Player / Enemy / NPC filters.
- *Sort* — by Name, CR, or Recency.
- *Tag filter* — drop-down to the right of the sort picker.  Two
  groups: *Habitats* (every 2024 MM habitat tag, both Material-
  Plane and Planar) and *Tags* (every user-authored tag that
  currently appears on at least one creature).  The Tags group
  disappears when no creature carries a tag — there is no
  separate tag database, so a tag exists only while at least one
  creature uses it.  Pick a habitat or tag to narrow the list to
  creatures carrying that label.
- *Already in encounter* — the count next to a creature reflects
  how many instances of it are currently in the queue.

** Viewing a stat block

Click a creature in the list to load its full stat block on the
right.  Clickable elements inside the stat block:

- *Ability scores* — clicking an ability cell (STR, DEX, …) opens
  an *Ability Save* roll prompt.
- *Inline dice* — any dice expression in a trait or action
  (e.g. "2d6+3 fire damage") is clickable and pops a floating
  result above the cursor.
- *Tag badges* — if the creature has any user tags, they appear as
  small pills on the right side of the name row in the
  Compendium-modal stat block.  In the pinned right-rail Compendium
  Panel on the main page, the same tags collapse to a single 🏷
  icon next to the name; hover the icon to see the full list.
- *Habitat / Treasure row* — at the very bottom of the stat block,
  below custom sections and lore, the 2024 Monster Manual habitat
  and treasure tags appear as labeled rows.  Planar habitats render
  inside a "Planar (…)" wrapper to mirror the printed format.

** Adding to the encounter

- *Add to Encounter* — drops one instance into the queue.  An
  optional "Roll initiative" mode rolls 1d20 + init bonus
  automatically.
- *Duplicate* — clones the creature inside the library (for
  variants).
- *Edit* — opens the *Compendium Edit* form pre-filled.
- *Delete* — removes the creature from the library (with
  confirmation).

** Compendium Edit

A multi-section form covering everything a 5e stat block needs:

- *Identity* — name, kind, size, race/subrace, alignment, source,
  description.
- *Combat core* — AC, HP, init bonus, speeds (walk/fly/swim/climb/
  burrow, plus a "hover" toggle).
- *Abilities* — the six ability scores with computed modifiers.
- *Saving throws and skills* — add or remove rows freely.
- *Properties* — damage vulnerabilities/resistances/immunities,
  condition immunities, languages, CR, XP (with optional in-lair
  override), proficiency bonus.
- *Senses* — blindsight, darkvision, tremorsense, truesight, passive
  perception, each in feet.
- *Features* — separate editable lists for Traits, Actions, Bonus
  Actions, and Reactions.  Each feature has a name, body, and a
  usage configuration (None, Recharge, Per Day, Per Short Rest, Per
  Long Rest, At Will) with mode-specific fields.
- *Custom sections* — free-form name + body for anything the
  built-in groups don't cover.
- *Tags* — free-form, single-word labels you can use to organise
  the library.  Click *+ Add Tag*, type the tag (no spaces;
  underscores are fine — e.g. ~boss~, ~fire_resist~, ~ranged~),
  hit × to remove a row.  Tags are user-authored only; the Paste
  Stat Block parser does not populate them.  Once at least one
  creature carries a tag, it appears in the Compendium browser's
  *Tag* filter dropdown; when the last creature using it is
  deleted or has the tag removed, the tag silently disappears
  from the dropdown.
- *Habitats* — the 2024 Monster Manual habitat list.  A
  Material-Plane chip row (Arctic, Coastal, Desert, Forest,
  Grassland, Hill, Mountain, Swamp, Underdark, Underwater, Urban)
  plus a Planar chip row (Abyss, Acheron, Astral Plane,
  Beastlands, Elemental Chaos, the four Elemental Planes, Feywild,
  Limbo, Lower Planes, Nine Hells, Upper Planes).  Multi-select.
- *Treasure* — the 2024 MM treasure buckets: Arcana, Armaments,
  Implements, Relics.  Multi-select.  The Paste Stat Block parser
  reads these automatically when the pasted text includes a
  ~Habitat:~ or ~Treasure:~ line (handling both colon-prefixed and
  bare-prefix forms, the ~Planar (X, Y)~ wrapper, same-line
  ~Habitat: X Treasure: Y~ cramming, and the ~Treasure: Any~
  shorthand which expands to all four buckets).
- *Advanced* — placeholders for Legendary Actions, Lair Actions,
  Regional Effects, and Spellcasting.  These read existing data but
  some fields are not yet fully editable; a banner warns you when
  the form can't round-trip a creature's data perfectly.  Avoid
  re-saving creatures with these sections through the form until the
  banner goes away (or use Paste Stat Block to refresh them).

** Paste Stat Block

When you have a stat block as text (from a PDF, a homebrew doc, etc.)
you don't have to retype it.  Open the Paste modal from the
Compendium toolbar:

- Paste the block into the left textarea.
- The right pane shows a live parsed preview.  If parsing fails, the
  preview explains what went wrong.
- When the preview looks right, click *Apply* — the parsed data
  transfers to the Compendium Edit form, where you can tidy up
  anything the parser missed before saving.

** Creature Groups

Groups are pre-configured "packs" of creatures you can add to an
encounter in one click — for example, "Hobgoblin patrol" containing
1 Hobgoblin Captain and 4 Hobgoblin Warriors.

- *Create Group* — opens the Group editor.  Name, initiative mode
  (each rolls / shared rolled / shared manual), and one entry per
  creature.  Each entry has a creature, a count, and an optional
  "minion" treatment (none / half max HP / 1 HP).
- *Create from Selected* — start a new group pre-populated with the
  creatures you've selected in the Compendium browser.
- *Edit Group* — change name, initiative mode, or entries.
- *Add Group to Encounter* — spawns the group's creatures, applying
  the chosen initiative behaviour and minion overrides.

Groups travel with your compendium: exporting the compendium exports
the groups; resetting the compendium clears the groups.

** Saving and loading the compendium itself

Separate from individual encounter saves, you can save and load
snapshots of your entire compendium library.

- *Save Compendium* — choose between server snapshot or device
  download (JSON).  Existing server snapshots show timestamps and
  can be renamed, overwritten, or deleted inline.
- *Load Compendium* — choose a file from your device or a server
  snapshot.  Loading prompts for confirmation; it replaces the
  entire library.

** Import, Export, and Reset

- *Export to File* — downloads the entire current compendium as a
  JSON file.  Includes creatures and groups.
- *Export Selected* — exports only the creatures you've selected.
- *Import from File* — uploads a JSON file and replaces the entire
  library (with confirmation).
- *Reset to bundled* — restores the small set of bundled example
  creatures and clears all groups.

* CR Calculator

The *CR Calculator* lets you sanity-check encounter difficulty
against the D&D 2024 *XP Budget per Character* system.  No 2014-era
monster-count multiplier — a fight is exactly as hard as the sum of
its monsters' XP.

** Opening it

Two entry points:

- The *⚔️ CR Calculator* button on the right Compendium Panel.
- The *Difficulty* button on the encounter title bar, which opens
  the calculator with the title bar's XP scope pre-selected.

** Using it

- *Party* — one row per character with a level dropdown (1–20) and
  a × to remove.  *+ Add character* appends a fresh level-1 row.
  The party list persists across modal opens during the session.
- *Scope* — which creatures count toward encounter XP.  Mirrors the
  XP scope dropdown on the title bar (Enemies & NPCs, Enemies Only,
  NPCs Only, Selected Only).
- *Result* — the live readout:
  - Encounter XP for the chosen scope.
  - The party's per-tier XP budgets (Low / Moderate / High).
  - A difficulty bucket — Trivial / Low / Moderate / High / Beyond
    High — colour-coded.
  - A short GM-facing description of what that bucket means at the
    table.

Note: the party roster is currently in-memory only.  Server
persistence for the party is on the roadmap.

* Card Customization (prototype)

A *🎨 Customize card* button on the app bar opens the *Card Editor*,
a prototype layout tool that lets you change which widgets appear on
your creature cards and how they're arranged.

What's working:

- Pick a queue view mode (List or Grid).
- Add, remove, and reorder rows.
- Set per-row alignment.
- Add widgets to rows from a dropdown picker.
- Save layouts to your account, load them, rename them, overwrite
  them, or delete them.
- A live preview to the right of the editor reflects your changes
  in real time.

What's not yet finished:

- Several widgets render as labelled placeholders in the preview
  (and the live encounter) rather than the final visual.  The names
  on the placeholders match the widgets they'll become.
- The full widget library is still being filled in.

Toggle the customised renderer with the *Custom: on / off* switch in
the app bar.  When off, the encounter renders with the classic
built-in card layout regardless of what's saved.

* Saving and loading encounters

** Saving

Open the *Save* modal from the middle-pane *💾 Save* button.

- *Destination* — Server (persisted to your account) or Device
  (browser file download).
- *Filename* — required for server saves.  Device saves get a
  date-stamped default.
- *Existing saves* — listed underneath when saving to the server.
  Each row can be renamed (pencil), overwritten (click the row),
  or deleted (×).  Inline confirmation banners replace the buttons
  while a destructive action is pending.

Encounters auto-save their live state to the server on every change,
so reopening the app picks up exactly where you left off — but those
auto-saves overwrite each other.  Use *Save* to bookmark named
snapshots you can return to (e.g. "Goblin ambush — round 0").

** Loading

Open the *Load* modal from the middle-pane *📂 Load* button.

- *Choose file…* — picks a JSON file from your device.  After
  selection, a confirmation banner explains that loading replaces
  the current encounter.
- *Server saves list* — every saved encounter on your account.
  Click a row to load it (with confirmation), use the pencil to
  rename it, or the × to delete it.

Loading any encounter forces the round counter back to 1 — the round
state is part of the snapshot, so a save made on round 5 reloads at
round 5; only *Reset* and *Clear* alter the round outside of a load.

* The Account page

Visit ~/me~ from the *User* badge in the app bar.

** Profile section

- *Email* and *Member since* are read-only.
- *Display name* is editable.  Save commits the change to the
  server; a banner reports success or failure.

** Security section

- *Change password* — supply your current password, type the new
  one twice, and submit.  Independent success/error feedback so it
  can't be confused with profile-update messages.

** Actions section

- *Leave Feedback* — opens your mail client to send to
  ~feedback@ezpzdndz~.  Use this for any bug report, feature
  suggestion, or "this is confusing" note.
- *Sign Out* — clears your session and returns you to the login
  screen.

* Site chrome

** App Bar (top)

- *eZpZ-dndZ* — brand text, links back to the encounter view.
- *Encounter* — link to the main view at ~/~.
- *Customize card* — opens the Card Editor.
- *Custom: on / off* — toggles the customised card renderer.
- *User badge* — your display name, links to ~/me~.

** Footer (fixed at the bottom)

- *Copyright and license summary* on the left.
- *Beta disclaimer* in the middle ("features may change or break
  without notice").
- *Contact* link on the right (mailto: ~feedback@ezpzdndz~).

** Toast notifications

Status messages slide in from a corner of the screen:

- Info (blue) — informational updates ("Encounter saved as
  'Dragons' Keep'").
- Success (green) — successful destructive actions ("Deleted
  Goblin").
- Warning (orange) — non-fatal issues.
- Error (red) — failed operations with a brief reason.

Toasts auto-dismiss after a few seconds; click the × to dismiss
sooner.

** Floating roll popups

Whenever you roll dice from a stat block, a chip, an ability cell,
or a button, the result floats up briefly from the cursor as a
*+N* or *−N* chip.  Roll-history entries still go to the dice log.

* Multi-select and bulk actions

Selecting creatures (via the checkbox on the left rail or
shift-click) unlocks bulk behaviour throughout the app:

- *HP Change → Apply to selected* — applies the same damage, heal,
  or temp HP to every selected creature.  Each receives its own
  log entry.
- *Condition → Apply to selected (N)* — splats independent copies
  of a new condition onto every selected creature.
- *Initiative → Roll & Sort: Selected* — rolls initiative only for
  selected creatures (with Advantage/Disadvantage variants).
- *XP scope → Selected Only* — both the title bar XP readout and
  the CR Calculator can use selection as scope, letting you check
  "what if this wave hits us right now?" mid-fight.

In the Compendium browser, selection enables:

- *Clear Selected* — bulk delete from the library.
- *Export Selected* — download only the selected creatures.
- *Create Group from Selected* — start a new group with the
  selection.

* Themes and visual modes

The settings popover (currently being rebuilt; reappears in an
upcoming release) lets you switch between *Light*, *Dark*, and
*Auto* (follow OS preference).  Selected creature cards highlight
with a border and accent fill.  Dead creatures grey out and surface
their death-save column.  Inactive creatures dim and step out of the
turn order.  The *Save* button outlines yellow when the encounter
has unsaved changes.

* Keyboard and mouse shortcuts

- *Escape* — closes any open modal, dropdown, or popover.
- *Click outside the modal* — same as Escape.
- *Enter inside a single-line text field* — submits the form
  (Apply / Save / Roll).
- *Shift + Click on a creature checkbox or card* — extends the
  multi-select range from the last checked item to this one.
- *Click the inline ability cell or dice expression in a stat
  block* — rolls it.

* Honest limitations and rough edges (today)

We'd rather you know about these in advance than be surprised by
them at the table.

- *Card Editor* is a prototype.  Some widgets render as labelled
  placeholders.  The classic renderer (toggle: *Custom: off*) is
  the production view.
- *Compendium Edit's advanced sections* — Legendary Actions, Lair
  Actions, Regional Effects, and Spellcasting — are partially
  editable.  Existing data is preserved on save, but the editor
  surfaces a banner when it can't round-trip a section.  Paste
  Stat Block is the safest way to refresh those sections.
- *CR Calculator party* persists for the session but not yet to
  the server.  Restarting the app re-empties it.
- *Theme picker* is temporarily hidden while the settings popover
  is being rebuilt; the underlying theming still works via OS
  preference.
- *Mobile/tablet polish* is incomplete.  The app is targeted at
  laptop and desktop screens for now.

If you spot something not on this list, it's almost certainly a
bug — please report it.

* How to report bugs and suggest features

We read every piece of feedback.  In rough order of preference:

1. *Email* — ~feedback@ezpzdndz~.  Subject line is fine, body
   can be as terse as you like.  Screenshots are very welcome.
2. *Leave Feedback button* on the Account page (~/me~) — opens a
   pre-addressed email.
3. *Contact link* in the footer — same email, different doorway.

When something goes wrong, the most useful things to include are:

- What you were trying to do.
- What actually happened.
- Whether it has happened before, or just once.
- The browser you're using, if you remember.

You don't need to write a full report — "I clicked save and got a
red banner" is a great start.  Thank you for testing.

* License

eZpZ-dndZ is source-available under the *PolyForm Strict License
1.0.0*: noncommercial / personal use only; no distribution, forks,
modifications, or derivative works.  See the project ~LICENSE~ file
for the full text.
