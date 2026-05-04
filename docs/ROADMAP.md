# Roadmap

A working list of features beyond the current "single-user mock with
turn tracking + dice roller" baseline. Order is intent, not
commitment — items shift as priorities change. See
[ARCHITECTURE.md](ARCHITECTURE.md) for the layering rules and the
deployment context.

## Near-term (next few sessions)

1. **Per-user named encounter saves**
   - Live-encounter auto-save / auto-load is shipped at
     `/api/encounter` (single slot, opaque JSON, gates on
     `model.encounter` mutation).
   - Remaining: the named-snapshot system —
     `GET / POST / DELETE /api/me/encounters[/:id]` for
     per-user save slots, wire the existing 💾 Save / 📁 Load
     buttons in the encounter controls panel, list-of-saves
     picker, and an auto-snapshot policy (one rolling
     auto-save per Next Turn debounced to ~5s + retain
     N=20 most recent + retain all manual / undo-point
     snapshots forever).

2. **Dice history per-user when authed**
   - Move `/api/dice/history` → `/api/me/dice/history`, scoped by
     session.
   - With OIDC enabled, each authenticated user gets their own slot.
   - Anonymous (OIDC-disabled) deployments stay single-slot.

3. **Compendium write-API auth gating**
   - All compendium write routes (`POST` / `PUT` / `DELETE` /
     `import` / `reset`) currently open in dev / homelab mode.
   - Once the `users` table exists, gate them on `role = admin`
     so only authorized users can mutate the shared library.
   - Add `visibility = private | shared | official` on each
     creature so non-admins can author private customs.

## Production deployment milestones

4. **SQLite-backed storage**
   - One `<data_dir>/ezpz-dndz.db` file replaces the assorted JSON
     files. Likely backend: `sqlx` (async, type-checked queries)
     unless compile-time cost gets unwieldy, in which case
     `rusqlite` + `tokio::task::spawn_blocking`.
   - Migrations via `refinery` or `sqlx-cli`.
   - Rough table sketch — to be refined when the first real feature
     lands:
     ```sql
     users(id, oidc_subject UNIQUE, display_name, role, created_at)
     creatures(id, owner_id NULLABLE, name, json, visibility, updated_at)
     encounters(id, owner_id, name, state_json, updated_at)
     dice_rolls(id, user_id NULLABLE, created_at, roll_json)
     ```

5. **OIDC integration polish**
   - Scaffolding already exists in `crates/server/src/auth.rs`; what
     production needs:
     - Documented Authelia / Keycloak / Authentik config example.
     - First-login user record creation (insert into `users` on
       first session for an unknown OIDC subject).
     - `role` field for admin-only mutations (compendium write, user
       management).

6. **Frontend auth flow**
   - `/me` already returns `auth_enabled` + name.
   - Add a "Sign in" link in the app bar when `auth_enabled` is true
     but the session is anonymous.
   - 401 responses on API calls trigger a redirect or a soft prompt.

## Larger features

7. **Real-time co-DM mode**
   - WebSocket channel for live encounter state sharing.
   - One DM, several spectator players, optional collaborator role.
   - Probably uses `axum::extract::ws` + a broadcast channel keyed
     by encounter id.

8. **Total-encounter stopwatch**
   - Wall-clock stopwatch for total encounter duration (separate
     from the per-creature row-3 turn-counter timers, which are
     already implemented). Likely lives in the encounter title
     bar next to the round counter.

9. **Compendium polish**
   - Edit-form support for the four advanced sections currently
     pass-through-only (legendary actions, lair actions,
     regional effects, spellcasting).
   - Creature images / token portraits — storage path under
     `<data_dir>/compendium/images/`, multipart upload
     endpoints.
   - Spell-slot / legendary-action consumption tracking on live
     instances.

## Smaller polish (any time)

- Round-trip parsing tests for `Dice.parse` (set up `elm-test`).
- `gh` CLI in `flake.nix` `devPackages` for in-shell GitHub workflows.
- Type-driven creature-name colors on card row 1 (PCs orange, undead
  cyan, fiends red, etc.).
- Branch protection + CI workflow (Rust check, Elm compile check) on
  the GitHub repo.
- Replace remaining hard-coded color hexes in `style.css` with CSS
  variables so all dice / button colors are themable in one place.
- Damage scaling: resistance / vulnerability / immunity multipliers
  on `HpChange.DamageSpec`, surfaced as a select in the Damage
  modal.
- Save-against-half flow on the Damage modal (ability + DC + roll),
  per the JS app's Roll Save toggle.

## Done in recent sessions

- **Empty default + auto-persist live encounter.** Boot encounter
  is `Encounter.empty` (no creatures); a previous session's state
  loads from `/api/encounter` on app boot. `update` is a thin
  wrapper that diffs `model.encounter` before/after each Msg and
  batches a `persistEncounterCmd` whenever it changed, so saves
  fire automatically without per-branch wiring. Save failures
  surface as a red toast; success is silent.
- **Bundled creatures + version-aware ADD-ONLY merge.** Eight
  SRD-derived creatures (Goblin / Skeleton / Hobgoblin / Dire
  Wolf / Ogre / Knight / Owlbear / Young White Dragon) replace
  the previous 5 placeholders. Stable hand-picked UUIDs let a
  `BUNDLED_VERSION` constant drive an ADD-ONLY merge on every
  boot: new content lands automatically, existing customs and
  edits are never overwritten.
- **`just promote-to-bundle <uuid>`** — Python helper that fetches
  a custom creature from the running dev server, rewrites it
  with a stable bundle UUID, appends to `bundled-creatures.json`,
  and bumps `BUNDLED_VERSION`. Removes the manual JSON-editing
  step from the bundle authoring workflow.
- **Compendium UI Phases 3–9 shipped end-to-end.** Browser modal
  with two-column layout, sticky filter bar, search /
  kind-chip / sort-dropdown filters, count input + ➕ Add to
  Encounter handoff (auto-numbered names, batch initiative
  rolls), ✏️ Edit / 📋 Duplicate / 🗑 Delete (red trash icon
  with red inline confirmation banner), 📋 Paste Stat Block with
  live preview, ↺ Reset to Bundled / 📥 Import / 📤 Export bulk
  ops, top-right toast notifications on save / delete / import /
  reset success and error, empty-state messaging that
  distinguishes "library is empty" from "filtered to nothing",
  loading skeleton on first fetch, `/` keyboard shortcut to
  focus the search input.
- **Stat-block parser.** `Compendium.Parser.parseStatBlock`
  handles canonical SRD form, D&D Beyond 2024 short-form
  prefixes (`AC`, `HP`, `CR`, bare `Immunities` etc.),
  tab-separated ability tables, `Mod\tSave` headers (skipped),
  fuzzy `<X> Lairs` / `<X> Regional Effects` headings even when
  arriving mid-lore, lore-paragraph detection at the tail (parks
  remaining text into a `Description` custom section instead of
  bleeding into the last action), and lair-effect descriptions
  with clickable inline dice (`1d20`, `2d4`, etc.). Locked in
  by 26+ assertions across 7 fixture stat blocks.
- **Dice scan picks up trailing punctuation.** `Dice.scan` now
  recognizes inline dice followed by any common punctuation
  (`1d20.`, `1d20,`, `1d20 `, etc.), not just standalone dice
  formulas. Two parser bugs fixed: `Parser.int` was treating
  trailing `.` as a malformed-float committed error (replaced
  with bare-digit chomping inside `diceInline`), and the
  optional `+N` modifier branch's `Parser.spaces` was greedily
  committing on a trailing space (now wrapped in
  `Parser.backtrackable`).
- **Click creature name to pin in side panel.** Names with a
  `creatureId` back-reference render as clickable spans with
  hover-underline; clicking pins the source compendium creature
  in the right-side Compendium panel. Legacy seed creatures
  with no compendium link render as plain non-clickable spans.
- **↗ open-in-new-window.** New SPA route
  `/compendium/creatures/:id` renders a centered max-720px
  standalone stat-block page. The side panel grows a small ↗
  link in the top-right of the rendered stat block that links
  to that route with `target="_blank"`, opening a real new
  browser tab for keep-as-reference / printing use cases.
- **Selection outline in the compendium browser.** Selected
  creature in the list now reads as a clear panel — 10% blue
  background tint + 2px inset blue box-shadow + the existing
  3px blue left border. Box-shadow chosen over real `outline`
  so the row doesn't visually shift its neighbors.
- **Quick View modal removed.** The 🔍 Quick View modal was
  redundant once the side-panel pin behavior shipped. Removed
  the per-card 🔍 button, the panel-toolbar 🔍 button, the
  modal helper, and the related Model state / Msgs.
- **Encounter creature back-reference + compendium → queue
  handoff.** New `creatureId : Maybe String` field on
  `Encounter.Creature` carrying a back-ref to the compendium
  template. Drives the "open in new window" / "pin in panel"
  features. Add-to-encounter flow auto-numbers names
  (`Goblin / Goblin 2 / Goblin 3`), rolls initiative for each
  copy in one batched Cmd, sorts the queue, and closes the
  modal.
- **Encounter title bar with live round / active-creature / HP /
  conditions placeholders.**
- Three-column creature card with selection / queue arrows /
  set-active arrow on the left rail; ✕ / 👿 / ⧉ on the right rail.
- Card center column rows 1–3 (init pip + face toggle + name +
  pencil + AC + condition placeholders; HP + bloodied + death
  saves + cover/conc/hide/fly toggles + fly-height stepper;
  Damage / Heal / Temp HP / Condition + hold action + memo /
  stopwatch / dice).
- Encounter Controls panel reflow with 🎲 Roll, ➕ Add Creature,
  💾 Save, 📁 Load, ⏭ Next Turn, ⟲ Reset, 🗑 Clear.
- Compendium panel renamed; toolbar shows 🔍 Quick View / 📖 Open /
  ⚔️ CR Calculator (the last greyed out as a future feature).
- Encounter / view layering split: `Encounter.elm`, `Dice.elm`,
  `HpChange.elm` are pure rules engines.
- Real turn tracking: `Encounter.nextTurn` advances the queue and
  bumps `round` on wrap; `Encounter.setActive` is a no-side-effect
  manual scrub.
- Dice roller: `Dice.elm` parses standard / compound / damage-
  tagged / stat-block-average notation, generates standard /
  advantage / disadvantage / coin rolls, batch rolls via
  `Dice.batchRollCmd`, scans stat-block traits for inline
  clickable formulas, and tags every roll with a
  `Source { feature, target }` for the history.
- Server-side dice history at `/api/dice/history` (atomic-rename
  writes, async-mutex'd, configurable path).
- HP change engine: `HpChange.elm` with damage / heal / temp HP
  arithmetic + auto-bloodied + revive-clears-death-saves; modal
  with manual + dice modes; last-10 log; click-to-edit current /
  max HP via `HpChange.setCurrentHp` / `setMaxHp`.
- Initiative manager: clickable init-circle, Quick Sort, batch
  Auto-roll for target / all / selected (with Advantage sister
  buttons that roll 2d20-keep-highest), Custom value apply for
  target / selected.
- Manual queue reordering via row 1 up/down arrows.
- Selection: row 1 checkbox (single toggle) + Shift+click bulk
  select-all / deselect-all.
- 5e surprise rule: `Encounter.nextTurn` skips creatures with
  `surprised = True`, auto-clearing their flag in the same step
  so their next turn after the skip happens normally.
- Per-creature note: short white-italic label edited via the row 1
  pencil button, click-to-edit on the note text once set; pipe
  separators in the row before AC and before the conditions list.
- Death-saves engine (5e): `Encounter.DeathSaves` record with
  successes / failures counters, auto-trigger keyed on
  `currentHp == 0`, 🌟/💀 pip strips with status badges,
  🎲 button that rolls 1d20 and resolves per-rule (nat 20 revives,
  nat 1 = +2 failures, etc.), `nextTurn` skips dead creatures, dead
  cards visually grey out.
- Condition / Effect engine: full modal (15 standard 5e conditions
  + custom name + 10-char note + duration block with Manual /
  Until-turn-of-X / Countdown variants + optional save-to-end with
  auto-roll). Live chips on row 1 + the encounter title bar
  replace the old placeholder. `Encounter.nextTurn` now composes
  begin / end-of-turn hooks that tick countdowns and expire
  Until-turn conditions; auto-roll saves fire as `Cmd`s on Next
  Turn.
- Dice indicator in encounter controls: bold-white latest-total
  readout left of the 🎲 Roll button, with a ← arrow signalling
  it was emitted by the roller. Yellow box-shadow ring on the
  button when the log has been updated since the modal was last
  opened; clears on open. All five roll-landing paths funnel
  through one `pushDiceRoll` helper.
- Encounter title bar: real status icons (cover / concentrating /
  hiding / flying with height) replace the placeholder set, and
  active-creature conditions now render as plain purple text
  separated by " | " rather than chips.
- Auto-scroll active card into view: every card has a stable
  `id`, and `NextTurn` / `SetActive` emit a Browser.Dom task that
  nudges the page when the active card's bottom is below the
  viewport.
- Save-to-end auto-roll modes: Manual (chip 🎲 only),
  AutoRollAtBegin, AutoRollAtEnd. `NextTurn` fires the matching
  bucket for the outgoing creature's end-of-turn and the new
  active creature's begin-of-turn separately.
- "Saved: <Condition>" notice: green chip posted on auto-roll
  save success; auto-clears on the bearer's next end-of-turn or
  via the × button.
- Until-turn target (current vs. next): `DurationUntilTurn` now
  carries `TurnTarget` so "until end of Lyra's NEXT turn" really
  takes two end-of-Lyra fires to expire. The "current" radio
  grays out when the combination is logically invalid (begin +
  active reference creature).
- Card row 3 redesign: dice icon removed; 📝 opens a 20-char memo
  modal and the memo replaces the icon as a white pill with ×;
  ⏱ opens a timer modal (count + begin/end phase) and the timer
  replaces the icon as a counting pill that flashes red and
  plays `/ping.wav` when it reaches 0.
- Apply-to-selected scope: HP-change and condition modals both
  gained an "Apply to all selected creatures (N)" checkbox.
  Hidden when no creatures are selected. Dice-mode HP shares one
  roll across all targets.
- Card right rail wired: × removes the creature (advancing the
  active marker if needed); ⧉ duplicates the creature
  (uniquified name, conditions / save-notices re-id'd).
  👿 minion placeholder removed.
