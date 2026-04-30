# Roadmap

A working list of features beyond the current "single-user mock with
turn tracking + dice roller" baseline. Order is intent, not
commitment — items shift as priorities change. See
[ARCHITECTURE.md](ARCHITECTURE.md) for the layering rules and the
deployment context.

## Near-term (next few sessions)

1. **Compendium read API**
   - `GET /api/compendium/creatures` returns the shared monster list.
   - Backed initially by JSON files in `<data_dir>/compendium/`,
     switching to SQLite when we want write support.
   - Elm side: load on init; replace `Encounter.seedCreatures` as
     the source of truth for the "Add Creature" picker.

2. **Encounter save / load**
   - `GET / POST / DELETE /api/me/encounters/:id` for per-user
     encounter state.
   - Wire the existing 💾 Save / 📁 Load buttons in the encounter
     controls panel.
   - Saved encounter = `Encounter` snapshot serialized as JSON, plus
     a name and timestamp.

3. **Dice history per-user when authed**
   - Move `/api/dice/history` → `/api/me/dice/history`, scoped by
     session.
   - With OIDC enabled, each authenticated user gets their own slot.
   - Anonymous (OIDC-disabled) deployments stay single-slot.

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

7. **Compendium write API**
   - `POST / PUT / DELETE /api/compendium/creatures/:id` with author
     tracking.
   - Visibility flag: `private` / `shared` / `official`.
   - Optional admin moderation queue for community-shared submissions.

8. **Real-time co-DM mode**
   - WebSocket channel for live encounter state sharing.
   - One DM, several spectator players, optional collaborator role.
   - Probably uses `axum::extract::ws` + a broadcast channel keyed
     by encounter id.

9. **Encounter timer / round timer**
   - The stopwatch icon on card row 3 gets a real implementation.
   - Per-creature time-on-turn tracking, optional total-encounter
     stopwatch.

10. **Condition / Effect engine**
    - Card row 3 "Condition/Effect" button currently does nothing.
    - Wire to a modal that picks from the standard 5e conditions
      list + custom effects, with optional duration in rounds and
      hooks into the turn lifecycle (begin/end/off-turn) so e.g.
      poisoned ticks down at end-of-turn.

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

- Encounter title bar with live round / active-creature / HP /
  conditions placeholders.
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
