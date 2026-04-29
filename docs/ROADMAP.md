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

9. **Initiative roller**
   - The existing "🎲 Roll" button → integrated with the dice domain.
   - Auto-sorts the encounter queue by rolled values + tiebreakers.

10. **Encounter timer / round timer**
    - The stopwatch icon on card row 3 gets a real implementation.
    - Per-creature time-on-turn tracking, optional total-encounter
      stopwatch.

## Smaller polish (any time)

- Round-trip parsing tests for `Dice.parse` (set up `elm-test`).
- `gh` CLI in `flake.nix` `devPackages` for in-shell GitHub workflows.
- Type-driven creature-name colors on card row 1 (PCs orange, undead
  cyan, fiends red, etc.).
- Branch protection + CI workflow (Rust check, Elm compile check) on
  the GitHub repo.
- Replace hard-coded color hexes in `style.css` with CSS variables
  so all dice / button colors are themable in one place.
