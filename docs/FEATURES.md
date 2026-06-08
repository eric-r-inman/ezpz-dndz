#+title:     eZpZ-dndZ — Features
#+subtitle:  A guide to every feature in the combat manager
#+language:  en

* Welcome

~eZpZ-dndZ~ is a free D&D combat encounter manager.  It handles
initiative order, hit points, conditions, and much more —
offloading combat minutiae from the DM's brain so they can stay
focused on the story.

You can start using it without signing in.  An account unlocks
multi-device sync and named server-side saves, but every
feature (compendium editing, named saves, dice history) works
in your browser anonymously too.  See [[*Using without an account][Using without an account]]
below.

* License

eZpZ-dndZ is source-available under the *PolyForm Strict License
1.0.0*: noncommercial / personal use only; no distribution, forks,
modifications, or derivative works.  See the project ~LICENSE~ file
for the full text.

* This Document

This document is a feature-by-feature tour: what each feature is for,
where to find it in the UI, and how to use it.

** Note on beta status

eZpZ-dndZ is in active beta.  The core encounter loop
(initiative, HP, conditions, dice roller) is stable, as is the
server.  Breaking changes can happen without warning.  Use this
app at your own risk.

Your feedback is welcome and will guide the development of this
app.  Use the *Leave Feedback* link on the Account page, the
*Contact* link in the footer, or email ~feedback@ezpzdndz~
directly.

** Conventions in this document

- Buttons are referred to by their visible label and emoji where
  applicable (e.g. "🎲 Roll").
- "The encounter" means the live queue of creatures currently in
  combat.
- "The compendium" means your personal monster library — the
  catalogue you build encounters from.

* Using without an account

Open the site and start playing.  No account required.

Anonymous sessions are backed entirely by your browser's
~localStorage~, with parity to the signed-in experience on every
common surface:

- The live encounter, dice history, and full compendium
  (creatures + groups) all persist across reloads.
- The Save / Load buttons on the encounter controls show *To
  Browser* / *From Browser* labels and write to ~localStorage~
  under names you choose (overwrite, rename, and delete all
  work the same as the server-backed flow).
- The compendium has full New / Paste / Edit / Duplicate /
  Delete / Create Group / Edit Group / Delete Group support
  with everything persisted locally.

What you give up without an account: cross-device sync (your
work lives in one browser), and the two genuinely-server-only
flows behind the compendium *Save/Load Snapshot to Server*
items (which redirect to the sign-in page with a tooltip).

** Promoting an anonymous session into an account

Sign in or create an account whenever you're ready.  The app
automatically uploads two pieces of your anonymous work to your
account in the background:

- Your live encounter is archived under the name *Local — <today>*
  in Save → Load.
- Your compendium (creatures + groups) is imported into your
  account.

You'll see one toast per migrated piece.  After that, every
mutation persists to the server instead.

** Signing out (preserves anonymous data)

Sign out via the Account page.  Your session ends and you
return to the anonymous experience.  Critically, anonymous
~localStorage~ data is *deliberately preserved* — if you had
work in this browser before signing in, it comes back on
sign-out instead of being wiped.

* Getting started with an account

An account unlocks:

- Cross-device sync (sign in on a different browser or device
  and your data follows you).
- Named server-side compendium snapshots (Save/Load Snapshot
  in the Compendium modal).

** Creating an account

Click the *Sign in* link in the AppBar (top right when
anonymous) to visit the sign-in form.

- *Create account* — toggle the form into Create mode; you'll
  be signed in automatically on success.
- *Sign in* — for returning users.  The email and password are
  the same ones you registered with.

Sessions are cookie-based and survive browser restarts.  Closing
the tab does not log you out.

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
  to edit inline), AC (click to edit inline), and any note.  A 🩸
  marker appears to the right of the name when the active creature
  is bloodied.
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

*** Quick-List view (↗ button)

To the right of the Difficulty button is a small *↗* link that
opens a standalone read-only view of the combat queue in a
fresh browser tab.  Park it on a second monitor for a clean
at-a-glance reference while you run the table.

- Cards are sorted by initiative; the active creature gets the
  same accent the main view uses, so "whose turn it is" is
  obvious from across the room.
- Each card is at most two lines:
  - *Line 1* — initiative badge · name · (optional note) · AC ·
    HP / Max HP (with the same green / muted-gray colors as the
    main view).
  - *Line 2* — only renders when something is on: bloodied,
    condition / effect chips, then cover, concentrating,
    hiding, dodging, flying (+height), readied, memo, timer.
- Cards are read-only — no buttons, no chips you can click.
- The page auto-updates as you mutate state in the main tab,
  via a same-browser ~BroadcastChannel~ — no polling, no
  server round-trip.  Works for both anonymous and authenticated
  sessions, in whichever theme you've picked.
- The AppBar is suppressed on this page so every pixel is queue
  rows.

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
  suffix ("Goblin 2") for duplicates.  Minion-style duplicates (via
  the Duplicate modal or a Black Pudding split) name themselves as
  *Goblin Minion 1*, *Goblin Minion 2*, etc., always numbered from
  1 — splitting a minion stays flat rather than nesting.
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
- *Bloodied marker* — surfaces when current HP is half of max or
  lower, per SRD 5.2.1.
- *Cover cycle (⬜/◻/◭/⬛)* — click to step through None → Half →
  Three-Quarters → Total cover.
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
- *Reaction (⚡ Reaction)* — a one-per-round pip representing
  the creature's reaction for the round.  Click to mark spent
  (gray); refills automatically at the start of the creature's
  next turn.
- *Recharge chip* — appears to the left of any condition badges
  when a creature has a Recharge X-Y feature (e.g. dragon
  breath, *Hellfire Spellcasting* on a Pit Fiend).  Three
  visual states:
  * *Green* (ready) — click marks spent.
  * *Gray, strikethrough* (spent, idle creature OR same-turn
    use) — click marks ready manually.
  * *Split prompt with a blinking 🎲* — appears at the START
    of the creature's next turn after the ability was spent.
    Click 🎲 to roll the d6 (success ≥ ~low~ → ready, failure
    → stays spent and the prompt clears until next turn).
    Click the ability name to mark ready without rolling.
  Spending the ability mid-turn doesn't raise the dice on the
  same turn — it waits for the begin-of-turn lifecycle hook,
  matching the 5e RAW "once per turn" recharge attempt.
- *Memo slot* — a tiny inline label (up to 15 chars), e.g. "leg
  res used".  Click to edit.
- *Timer slot (⏱️)* — opens the *Timer* modal to attach a countdown
  to the card.

*** Right rail — destruction and visibility

- *Remove (×)* — pop this creature out of the encounter.
- *Inactive toggle (⧉)* — keep the card visible but exclude it from
  the turn order.  Useful for downed enemies you want to remember.
- *Replace (⇄)* — opens *Quick Add* in "Replace mode": picking a
  creature swaps it in place, keeping the old card's initiative
  value but adopting the new creature's HP, AC, and stats.  The
  modal title reads *Replace <old name> with…* until you pick or
  cancel.
- *Duplicate (⧉ second group)* — opens the *Duplicate* picker with
  five options (see below).

*** Lifecycle badge (top-center on the card)

Every card carries a small lifecycle pill across the top edge
that reflects its current state at a glance:

- *💤 DOWN* (amber) — current HP is 0 and death-save tracking
  hasn't been opened yet, or no successes are stored.
- *💤 DOWN, STABLE* (green) — 0 HP with three death-save
  successes recorded.
- *💀 DEAD* (red) — three failures or otherwise marked dead.
- *⏭ SKIPPED* (gray) — the creature is being walked past in
  the turn order (downed without death saves opened, inactive,
  or readying).

The DOWN and DEAD pills are clickable buttons that form a
reversible toggle: clicking DOWN flips the creature to DEAD
(failures set to 3); clicking DEAD flips it back to DOWN
(failures cleared, successes preserved).  Hover previews the
destination state.  The card's left-edge color stripe mirrors
the badge color.

*** Optional — Death Saves column

When a creature drops to 0 HP, a single *Death Saves* opt-in
button appears in place of the pip strip.  Most downed enemies
never need actual death saves rolled, so the strip stays
hidden until you ask for it.  Click the button and the usual
column of three success circles and three failure × marks
appears — click any circle or × to toggle it manually.

- *Roll Death Save (🎲)* — auto-rolls 1d20.  A roll of 10 or higher
  is a success; 9 or lower is a failure; natural 20 returns the
  creature to 1 HP; natural 1 counts as two failures.
- The card flips to *Stable* (three successes) or *Dead*
  (three failures) automatically, and the lifecycle badge
  follows along.
- Healing the creature above 0 HP resets the opt-in flag, so
  the next downing starts from a clean tracker.

*** Optional — Legendary pips column

When the pinned stat block has legendary actions or *Legendary
Resistance*, the card grows a small column of pip indicators.  Click
each pip to mark it used/available — handy for tracking "1/day"
resources without leaving the table.

** Encounter Controls (middle cluster)

The middle pane is where global encounter actions live.

*** Dice quick-roll cluster

- *Last total* — a flashing readout of the most recent dice result.
  Up to three previous totals render to the left of it in muted
  text (oldest first) so you can see the last few rolls without
  expanding the strip or opening the modal.
- *Expand arrow (→)* — toggles the inline dice-history strip.
- *Roll (🎲)* — opens the full *Dice Roller* (see *Dice* below).

*** Action grid (six buttons, three rows of two)

1. *Quick Add (➕)* — lightweight creature picker.  See *Quick Add*.
2. *Save (💾)* — split button.  The dropdown picks destination:
   - *To Server* — saves to your account (signed in).  Shows as
     *To Browser* when anonymous — same Save modal, same name
     conflict handling, but the snapshot lands in this browser's
     storage instead of the server.
   - *To Device* — downloads a JSON file via the browser.  Works
     the same regardless of sign-in.

   The button face turns orange/yellow when the encounter has
   unsaved changes.

3. *Load (📂)* — split button:
   - *From Server* (or *From Browser* when anonymous) — opens
     the Load modal listing your saved encounters.
   - *From Device* — pick a JSON file from disk.
4. *Next Turn / Run (>❯ / ▶)* — advances the turn.  Before round 1
   the label is *Run* and pressing it kicks off combat (rolls
   initiative-tied effects, ticks per-turn countdowns).  After that,
   the label switches to *Next Turn*.
5. *Reset (⟲)* — keeps every creature in the roster but wipes
   per-fight state: HP back to full, no temp HP, no conditions
   or save notices, death-save counters cleared, every status
   toggle off (cover, concentration, hiding, dodging, flying,
   readied, inactive, bloodied), legendary actions and resistances
   refilled, timers cleared.  Identity and combat baselines
   (name, kind, initiative, AC, max HP, note, memo, source) are
   preserved.  Round counter goes back to 0 so you can press *Run
   Encounter* to start combat over with the same lineup.  Asks
   for confirmation first.
6. *Clear (🗑)* — empties the encounter back to a blank slate
   (no creatures at all).  Also asks for confirmation.

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

- *Standard condition* — badges for all 15 standard 5e
  conditions; selecting one pre-fills the name.  Click the same
  badge again to deselect it and clear the name field — useful
  for switching from "I'll pick a standard" to "I want a custom
  one" without retyping.
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

*** Condition presets

The footer of the Condition modal has a *Save / Load* row that
remembers full condition configurations under names you choose,
so a "Bardic Inspiration" that auto-rolls a DC 12 save at end of
turn (with a 10-char note) can be one click away forever.

- *Save* — type a name, pick a category from the dropdown, hit
  *Save*.  Both fields are required; the Save button stays
  disabled (with a tooltip explaining why) until both are set.
  Stores the current condition's name, custom name, note,
  duration mode, save-to-end settings, auto-roll mode, and the
  picked category.
- *Load ▾* — dropdown of every available preset.  Your own
  saves render in a flat list at the top; below that the bundled
  defaults appear in five collapsible categories — *Player
  Classes* / *Spell Effects* / *Monster Abilities* / *Items* /
  *Environment* — each starting collapsed with a parenthesised
  count.  Within each section presets sort alphabetically,
  case-insensitive.
- *× per row* — delete one of your own presets.  Bundled
  defaults are read-only; you can override them by saving your
  own preset with the same name (yours wins).

**** Bundled defaults

A fresh visitor's Load menu ships pre-populated with ~60+ common
SRD 5.2.1 effects across the five categories:

- *Player Classes* — 33 presets covering all 12 standard 5e
  classes.  Highlights: Stunning Strike, Trip / Menacing /
  Goading / Pushing / Disarming Attack, Bardic Inspiration
  (d6 / d8 / d10), Bless, Hex, Hunter's Mark, Searing /
  Wrathful / Staggering / Branding Smite, Turn Undead, Rage,
  Reckless Attack, Vicious Mockery, Guidance, Sanctuary,
  Shield of Faith, Wild Shape, Spike Growth, Action Surge,
  Patient Defense, Pass Without Trace, Ensnaring Strike,
  Sneak Attack, Hexblade's Curse, Shield, Haste.
- *Spell Effects* — Hold Person / Monster, Sleep, Charm
  Person, Fear / Cause Fear, Hypnotic Pattern, Hideous
  Laughter, Suggestion, Slow, Web, Entangle, Banishment,
  Stinking Cloud, Greater Invisibility, Blindness, Faerie
  Fire, Black Tentacles, etc.
- *Monster Abilities* — Petrifying Gaze (Medusa), Mind Blast
  (Mind Flayer), Frightful Presence (Dragon), Horrifying
  Visage (Ghost), Paralyzing Touch (Ghoul), Vampire Charm,
  Luring Song (Harpy), Web (Giant Spider), Tendril (Roper),
  Sleep Ray (Beholder), Carrion Crawler Tentacles, Mummy Rot.
- *Items* — Wand of Paralysis, Wand of Fear, Staff of
  Charming, Potion of Invisibility / Heroism / Climbing /
  Giant Strength, Dust of Sneezing & Choking, Dust of
  Disappearance, Net.
- *Environment* — Quicksand, Slippery Surface, Heavy
  Obscurement, Drowning, On Fire, Extreme Cold / Heat, Pit
  Trap.

DCs default to SRD stat-block values; the GM tweaks per cast
(dragon Frightful Presence scales by CR, Stunning Strike DC
scales with the Monk's Wisdom, etc.).  The defaults seed on
the very first boot (when no ~conditionPresets~ key exists in
~localStorage~) and are otherwise always available as a
read-only layer underneath your saved presets — deleting your
own never removes a bundled default.

User-saved presets persist to your browser's localStorage
(anonymous and authenticated sessions both round-trip through it
today).  They are not yet synced to the server.

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

  The Timer modal also has a *Save / Load* footer (mirror of the
  Condition modal's preset row) that remembers timer setups —
  turn count, phase, and label — under names you choose.
  Dropdown is sorted alphabetically (case-insensitive); presets
  persist to ~localStorage~.

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
  roll to re-run it (appends a new entry).  Each row's *↻* button
  opens a two-item menu: *Reroll* repeats the original expression;
  *Reroll, no modifier* strips the constant before re-rolling, so
  you can ask "what if I hadn't been at -2?" without retyping the
  dice.  *Clear History* wipes the list (with confirmation).

Roll history is persisted to your account — it survives logout and
appears on other devices when you sign back in.

* Quick Add

Open from the *➕ Quick Add* button.  This is the fastest way to drop
a creature into the encounter without leaving the table view.

- *Placeholder row* — pinned italic entry at the top of the list.
  Adds a stub combatant (Initiative 0, HP 1/1, AC 10, name
  *Placeholder N*) when the roster isn't fully resolved yet.  Click
  the card's name later to rename it; use the right-rail ⇄ button
  to swap in a real creature once you've decided.
- *Sort toggle* — switch the list between alphabetical and CR order.
- *Creature list* — every creature in your compendium, with its CR
  on the right.  Click a row to add one instance to the encounter at
  full HP with no conditions.

Use Quick Add when you know what you want; use the full Compendium
when you want to read stat blocks first.

** Placeholder combatants

When you want a slot in the queue but don't know who fills it
yet, drop in a *Placeholder*:

- The full-width dashed *+* row at the bottom of the queue adds
  one with a single click.
- Quick Add's pinned *Placeholder* entry does the same thing.

A placeholder behaves like any other creature — takes its turn,
holds conditions, etc. — but spawns at Initiative 0 so it
naturally lands at the back of the queue until you sort it in.
Click the card's name to rename it inline.  When you're ready to
fill it in with a real stat block, use the right-rail *⇄* button
to swap it for any creature from the compendium without
disturbing the initiative order.

* The Compendium

The Compendium is your personal monster library.  It powers Quick
Add, the right-panel stat block, and the encounter's per-creature
data (initiative bonuses, AC, max HP, traits, etc.).

** Opening the Compendium

Click *📖 Open* on the right Compendium Panel.  The library opens as
a two-column modal: a filterable list on the left, a stat block and
action bar on the right.

The Compendium modal also has a *↗* button next to the close ×.
Click it to open the same compendium as a *full-page tab* (route
~/compendium~) — useful on a second monitor while combat runs in
the main tab.  When that tab is open, clicking *📖 Open* on the
main page focuses the existing tab instead of opening the modal
again; closing the tab restores the modal-open behaviour.  Each
tab runs its own Elm instance, so edits in the standalone tab
don't live-sync to the main tab's right panel until you reload
the main page.

** Browsing and filtering

- *Search* — live filter as you type (placeholder reads
  "Search by name, type, etc.").  Matches against creature
  name, race, alignment, source, and CR.
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

- *Kind badge* — a small coloured chip next to the creature name
  marking it Player (blue), Enemy (red), or NPC (yellow).
- *Ability scores* — clicking an ability cell (STR, DEX, …) opens
  an *Ability Save* roll prompt.
- *Inline dice* — any dice expression in a trait or action
  (e.g. "2d6+3 fire damage") is clickable and pops a floating
  result above the cursor.  Blue pills are damage rolls.
- *Attack-roll pills* — red pills attached to attack lines
  (recognising both the SRD 5.2.1 ~Melee Attack Roll: +N~ /
  ~Ranged Attack Roll: +N~ header and the legacy ~+N to hit~
  form).  One click rolls 1d20 + modifier and lands the result
  in the dice history.
- *Tag badges* — if the creature has any user tags, they appear as
  small pills on the right side of the name row in the
  Compendium-modal stat block.  In the pinned right-rail Compendium
  Panel on the main page, the same tags collapse to a single 🏷
  icon next to the name; hover the icon to see the full list.
- *Habitat / Treasure row* — at the very bottom of the stat block,
  below custom sections and lore, the 2024 Monster Manual habitat
  and treasure tags appear as labeled rows.  Hovering the Habitat
  row shows the tooltip *"Inferred from online public sources"* —
  the bundled habitats were filled in by a deterministic name +
  race rule pass (Open5e's SRD dataset exposes the field but
  ships no values), so treat them as best-guess unless you've
  edited them yourself.  Planar habitats render
  inside a "Planar (…)" wrapper to mirror the printed format.

** Adding to the encounter

- *Add to Encounter* — drops one instance into the queue at
  initiative 0; the GM rolls or types the initiative when ready
  (no dice-history pollution from add flows).
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

*** Lore groupings (in the same modal)

Below the Group editor's Create button, a *Lore groupings*
section is the editor for the Random Encounter generator's
*Lore-leaning* toggle.  Two collapsible lists:

- *Your lore groups* — what you've authored.  ▾ to expand a row
  and see its members; ✎ to edit; × to delete (with confirm).
- *Bundled lore groups* — ~50 hand-authored canonical
  combos (Goblinoid Warband, Adult Dragon's Tribute, Hag Coven,
  Pit Fiend's Retinue, etc.).  Read-only; expand-only.

Click *➕ New lore group* to author your own.  The inline form
takes a name, a weight slider (1 = rare, 10 = common), a member
list (each with a *Role* — Leader / Member / Minion / Pet — and
a min/max count range), and a creature picker to add new
members.  Saved groups land in your *Your lore groups* list and
flow into the Random Encounter generator alongside the bundled
set on the very next roll.  Persisted to ~localStorage~ so your
canon survives reloads.

Bundled groups can't be edited.  If you want to tweak one —
say, change the Hobgoblin Patrol's worg count — create a new
lore group with the same composition and tune from there.

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

The Compendium toolbar carries plain single-click *📥 Import*,
*📤 Export*, *↺ Reset*, and *🗑 Clear* buttons.  Import and
Export both open modals that mirror the encounter Save / Load
shape — Server / Device radio at top, body changes based on
the picked option.

- *Export* — opens the Save Compendium modal.  *Device* writes
  a JSON file to your machine; *Server* writes a named snapshot
  to your account.  Sign-in required for Server (an inline hint
  explains; the Save button stays disabled until you flip to
  Device or sign in).
- *Import* — opens the Load Compendium modal.  *Device* opens
  the file picker; *Server* lists your saved snapshots so you
  can replace the live compendium with one of them.  Same
  sign-in gating as Export.
- *Import file errors* — if the file doesn't parse (an old
  format from before a software update, etc.) a popup with a
  single *OK* button explains the file may have compatibility
  issues.  The current compendium isn't touched.
- *Reset to bundled* — restores the small set of bundled example
  creatures and clears all groups.
- *Clear* — splits into *Clear All* / *Clear Selected*.

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

Note: the party roster persists across browser sessions in
~localStorage~ (shared with the Random Encounter modal below).
Server-side persistence so the party follows a signed-in user
across devices is on the roadmap.

* Random Encounter generator

The *🎲 Random Encounter* button on the right Compendium panel
opens a generator that builds an encounter to a party's XP
budget and drops it into your queue.  It's a planning tool
("what does a Moderate forest fight look like for my level-5
party?") and a flavor tool ("give me a Hag Coven for tonight's
session") in one.

The algorithm is community-derived and may not reflect official
2024 DMG guidance — the in-modal blurb says so.  The XP-budget
math reuses the same per-character table the CR Calculator
uses, so the two stay aligned.

** Party

Same party roster as the CR Calculator — opening either modal
seeds 4 level-1 PCs if no party exists yet.  Edits in one show
in the other.  Persisted in ~localStorage~.

** Parameters

- *Difficulty* — Low / Moderate / High.  The live "Budget" pill
  shows the XP target derived from the party.
- *Scale* — *One* (1 creature, a boss), *Few (2-4)* (a hunting
  band), *Many (4+)* (a swarm / mob).  Caps the total creature
  count regardless of how many bodies a lore group or top-up
  pass would otherwise add.
- *Habitat* — *Any* (wildcard) or one of 24 habitat tags
  (Forest, Coastal, Underdark, Abyss, Feywild, …).  Filters the
  pool to creatures whose stat block lists the habitat.
- *Type* — *Any* or one of the 14 standard 5e creature types.
  Click *Any* on the empty trailing dropdown to add another
  type — the filter is OR-of-types so you can mix Dragon +
  Fiend for a chaos roll.
- *Include minions* — adds 2–6 low-CR creatures (xp ≤ 100) on
  top of the random fill, sharing 20% of the budget.  Marked
  with a *MINION* badge in the result.
- *Lore-leaning* — when on, the generator prefers
  hand-authored canonical groupings (Goblinoid Warband, Adult
  Dragon's Tribute, Hag Coven, Pit Fiend's Retinue, etc.).
  Bundled + user lore groups are pooled together; weights and
  filters decide which wins on any given roll.

** Specific creatures

A "Specific creatures" panel below the parameters lets you
shape the roll further:

- *➕ Pin a creature* opens a searchable picker; pick to lock
  the creature into the roll.  Pinned creatures appear in the
  result with no badge.  Per-pin *−*/*+* buttons adjust the
  count; *×* removes the pin.  Pinned XP comes off the budget
  before the random fill rolls, so a Pit Fiend pin will eat
  most of a low-level budget on its own.
- *🚫 Exclude a creature* opens the same picker for the
  opposite intent — any creature in the exclude list gets
  filtered out of the random fill (and minions).  Pinned beats
  exclude if both are set for the same creature.
- A *budget summary row* appears whenever you've pinned at
  least one creature — shows pinned XP vs total budget and
  flags when pins overflow the budget.

** Result panel

Click *🎲 Generate* (or *🎲 Reroll*) and the result shows up as
a list of ~count × Creature~ rows with CR + group XP.  Pinned
creatures appear first, then the random fill, then minions.
Each row has two affordances on the right:

- *🚫* — adds the creature to the Exclude list for next time
  (works on both random and minion rows; hidden on pinned rows
  since exclude-vs-pin is a contradiction).
- *📌* — pins the creature for next time (or bumps the count
  if it's already pinned).

A *Total* line at the bottom sums the encounter XP.  Both
actions reset the result panel to encourage a fresh reroll so
you see the new outcome immediately.

** Add to Encounter

*Add to Encounter* spawns every group into the queue at
initiative 0 (the GM rolls per card once combat starts).
Duplicate species get auto-suffixed (Goblin, Goblin 2,
Goblin 3) so the queue doesn't collide.  The modal closes on
success with a toast confirming the count.

* Card Customization (deferred for launch)

The *Card Editor* — a layout tool for choosing which widgets
appear on creature cards and how they're arranged — is hidden in
the launch build.  The supporting code (editor modal, layout
data model, save/load endpoints, anonymous-mode localStorage
snapshot) is still in place, but the *🎨 Customize card* button
and *Custom: on / off* switch are commented out in the app bar
and the encounter always renders with the classic card.  Once
the widget set is filled out the entry points will come back.

* Saving and loading encounters

** Saving

Open the *Save* modal from the middle-pane *💾 Save* button.
The button is a plain single-click affordance — no dropdown.

- *Save to* — a Server / Device radio pair.  The Server label
  reads "Server" when you're signed in and "Browser" when
  anonymous (same destination value either way; anonymous saves
  land in your browser's localStorage with a name, signed-in
  saves go to the server).
- *Filename* — required.  The text input gets autofocus when
  the modal opens.
- *Existing saves* — listed underneath when saving to Server (and
  you're signed in).  Each row can be renamed (pencil),
  overwritten (click the row), or deleted (×).  Inline
  confirmation banners replace the buttons while a destructive
  action is pending.
- *Save button* — always reads *Save* (regardless of destination)
  and stays disabled until a name is typed.

The button face turns yellow when the encounter has unsaved
roster changes since the last *Save* / *Load*.

Encounters auto-save their live state to the server (signed in)
or localStorage (anonymous) on every change, so reopening the
app picks up exactly where you left off — but those auto-saves
overwrite each other.  Use *Save* to bookmark named snapshots
you can return to (e.g. "Goblin ambush — round 0").

** Loading

Open the *Load* modal from the middle-pane *📂 Load* button —
also a plain single-click button.

- *Load from* — a Server / Device radio pair mirroring the Save
  modal.  Server (or "Browser" when anonymous) shows the list
  of saved encounters; Device shows the file-picker for a
  JSON snapshot.
- *Server saves list* — every saved encounter on your account
  (or in this browser, anonymous).  Click a row to load it (with
  confirmation), use the pencil to rename, the × to delete.
- *Choose file…* — picks a JSON file from your device.  After
  selection, a confirmation banner explains that loading replaces
  the current encounter.

Loading any encounter forces the round counter back to 0 — the
round state is part of the snapshot, so a save made on round 5
reloads at round 5; only *Reset* and *Clear* alter the round
outside of a load.

** Signing in mid-build (anonymous → authenticated)

If you've been building an encounter as an anonymous user and
then sign in, the encounter you were just working on stays as
the live one — it's *not* replaced by the server's last-active
save.  Your in-progress work is also pushed to the server as
the new current active so a second device picks it up on next
load.  The pre-sign-in state is additionally archived to your
account under *Local — <today>* as a safety net.

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
- *Sign Out* — clears your session and returns you to the
  anonymous experience.  Anonymous data stored in this browser
  before you signed in (live encounter, custom card layout,
  saved compendium edits, named saves) is *preserved*, so a
  sign-out doesn't wipe your work.

* Site chrome

** App Bar (top)

- *eZpZ-dndZ* — brand text, top-left.  When you're anonymous, an
  italic tagline rides next to it: *"Sign in to save your
  encounters and compendium changes."*
- *Encounter* — link to the main view at ~/~.
- *User badge / Sign in* — shows your display name (links to
  ~/me~) when signed in.  When anonymous, shows a *Sign in*
  link that takes you to the sign-in form.  On the sign-in page
  itself the link is suppressed (it would point back to
  itself).
- *About* — link to a short ~/about~ page describing what
  eZpZ-dndZ is and how it works.
- *Donate* — link to ~/donate~.
- *⚙ settings* — opens the *Set Theme* popover with the Theme
  picker (and future preferences).  The radio list stacks
  vertically; Accessible carries an italic *(alpha)* badge.

** Footer (fixed at the bottom)

- *Copyright and license summary* on the left.  *PolyForm Strict
  1.0.0* is a link out to ~polyformproject.org~ for the full
  license text.
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

The *⚙ settings* button at the right of the app bar opens a
popover with the *Theme* picker:

- *Modern* — Linear/Vercel-style light palette: off-white
  surfaces, indigo accents, hairline borders, Inter for UI text
  plus JetBrains Mono for numerics.
- *Dark* — classic dark palette with the system font stack.
- *Auto* — resolves to Modern or Dark per your OS's current
  colour-scheme preference.
- *Accessible* — WCAG AAA-targeted high-contrast theme: bumped
  font sizes across every panel, B&W creature-card buttons that
  flip to black-fill / white-text on hover, larger touch
  targets, 3-pixel focus rings, 24px checkboxes.  Honours
  ~prefers-reduced-motion: reduce~ globally — animations
  (including the Readied pulse) fall back to static highlights
  when the OS asks for less motion.

The picker is available in all sessions — anonymous or signed
in — and your choice persists across reloads via your browser.
The sign-in page itself always renders in the Dark palette
regardless of your selected theme, so the form has a consistent
look.

Other always-on visual cues:

- Selected creature cards highlight with a border and accent fill.
- Dead creatures grey out and surface their death-save column.
- Inactive creatures dim and step out of the turn order.
- The *Save* button outlines yellow when the encounter has
  unsaved changes.

* Keyboard and mouse shortcuts

- *Escape* — closes any open modal, dropdown, or popover.  On
  the sign-in form (~/login~), Escape returns to the encounter
  page.
- *Skip to main content* — at the very start of the tab order
  on every page; jumps past the AppBar links straight to the
  encounter pane.  Visually hidden until focused.
- *Click outside the modal* — same as Escape.
- *Enter inside a single-line text field* — submits the form
  (Apply / Save / Roll).
- *Shift + Click on a creature checkbox or card* — extends the
  multi-select range from the last checked item to this one.
- *Click the inline ability cell or dice expression in a stat
  block* — rolls it.
- *Tab inside a modal* — wraps within the modal back to the
  close button rather than escaping into the underlying page.
- *Drag a modal's header* — repositions the modal.  *Drag any
  edge or corner* — resizes the modal.  The chrome clamps to
  the viewport so a modal can't be dragged off-screen.

* Honest limitations and rough edges (today)

We'd rather you know about these in advance than be surprised by
them at the table.

- *Card Editor* is hidden for launch.  Every creature card uses
  the classic built-in layout.  See [[*Card Customization (deferred for launch)][Card Customization (deferred for launch)]].
- *Compendium Edit's advanced sections* — Legendary Actions, Lair
  Actions, Regional Effects, and Spellcasting — are partially
  editable.  Existing data is preserved on save, but the editor
  surfaces a banner when it can't round-trip a section.  Paste
  Stat Block is the safest way to refresh those sections.
- *CR Calculator party* persists for the session but not yet to
  the server.  Restarting the app re-empties it.
- *Mobile/tablet polish* is incomplete.  The app is targeted at
  laptop and desktop screens for now.
- *Anonymous named saves don't auto-migrate.*  When you sign
  in, your live encounter is auto-archived to your account.
  Your *named* encounter saves stay in your browser — sign out
  to access them anonymously again, or open each and re-save
  under your account.

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
