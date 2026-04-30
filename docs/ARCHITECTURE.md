# Architecture

For developers (and AI agents) joining the project. Explains how the
codebase is organized and the conventions you're expected to follow.

## Stack

- **Backend** — Rust workspace with three crates: a CLI (`ezpz-dndz-cli`),
  a server (`ezpz-dndz-server`, [axum](https://docs.rs/axum)), and a
  shared lib (`ezpz-dndz-lib`).
- **Frontend** — Elm 0.19 SPA, served as static files by the Rust
  server. The server falls back to `index.html` for any unknown path
  so client-side routing keeps working.
- **Build** — `cargo` for Rust, `elm make` for Elm. Both run inside a
  Nix dev shell defined by `flake.nix`. `just dev` and `just serve`
  auto-enter the dev shell if needed, so a fresh terminal can run them.

## Source layout

```
.
├── crates/
│   ├── cli/      ezpz-dndz-cli (binary)
│   ├── server/   ezpz-dndz-server (axum, hosts /api/dice/* + frontend)
│   └── lib/      ezpz-dndz-lib (shared types, logging)
├── frontend/
│   ├── src/
│   │   ├── Main.elm        application shell + view code
│   │   ├── Encounter.elm   encounter domain (types, rules, turn logic,
│   │   │                   queue reorder, sort)
│   │   ├── Dice.elm        dice-roller domain (parser, rolls, batch
│   │   │                   rolls, history, stat-block scanner, JSON)
│   │   └── HpChange.elm    HP-change engine (damage / heal / temp HP
│   │                       arithmetic, manual setCurrentHp / setMaxHp)
│   └── public/
│       ├── index.html      mounts Elm into #app
│       ├── style.css       all styles, dual light/dark via vars
│       └── elm.js          (gitignored, built by `elm make`)
└── docs/
    ├── ARCHITECTURE.md     this file
    └── systemd.org         deployment notes
```

## Layering: domain vs view

> **The rule:** D&D rules logic lives in domain modules
> (`Encounter.elm`, `Dice.elm`, `HpChange.elm`, …). UI code
> (`Main.elm`, any future View modules) imports them and uses their
> types and functions. Logic code never imports view code.

The reason this matters now: we're going to ship multiple UI layouts
(a "simple view" stripped of advanced controls, possibly a tablet
layout, etc.). Each layout still operates on the same encounter state
and the same turn rules. If rules code starts importing `Html`,
swapping layouts means rewriting rules — not acceptable.

In practice this means:

- `Encounter.elm`, `Dice.elm`, and `HpChange.elm` do not
  `import Html`, `Browser`, `Url`, or any rendering primitive. The
  compiler will tell you if you accidentally reach for one.
- A `Msg` branch in `Main.elm`'s `update` should be a one-liner that
  delegates the rules-y work into `Encounter`. If the branch starts
  doing list walks, comparisons against initiative, or HP arithmetic
  inline, the work belongs in `Encounter`.
- The seed encounter (`Encounter.initialEncounter`) is the
  authoritative starting state. `Main.init` just wires it into the
  Model; it doesn't pick its own creatures.

There are a few small seams in `Main.elm` that lift domain-shaped
transformations into `Model -> Model` updates so individual `update`
branches stay one-liners and the rest of `Model` (route, auth, nav
key) stays invisible to domain code:

- `withEncounter : (Encounter -> Encounter) -> Model -> Model`
- `withDice : (DiceUi -> DiceUi) -> Model -> Model`
- `withHpChange : (HpChangeUi -> HpChangeUi) -> Model -> Model`
- `withInitiative : (InitiativeUi -> InitiativeUi) -> Model -> Model`

Each modal/UI substate has its own `with*` helper. New ones follow
the same pattern.

## Turn lifecycle

5e initiative is a single linear queue: each creature acts in turn,
and after the lowest-initiative creature acts the round ends and we
loop back to the highest. The app models this with three fields on
`Encounter`:

- `creatures : List Creature` — the queue, in initiative order.
- `activeName : String` — whose turn it currently is.
- `round : Int` — 1-indexed round counter.

Turns advance through `Encounter.nextTurn`, which is invoked from the
`NextTurn` Msg branch when the user clicks the **⏭ Next Turn** button.
`nextTurn` walks to the successor in the queue and increments `round`
when it wraps from the last creature back to the first.

We anticipate four lifecycle phases that future features will hook:

| Phase             | When it fires                                          | Examples                                                          |
|-------------------|--------------------------------------------------------|-------------------------------------------------------------------|
| beginning of turn | a creature has just become active                      | per-turn ability charges reset; "start of turn" conditions tick   |
| on turn           | the creature is currently active                       | most player-driven actions (attacks, casts, moves)                |
| end of turn       | fired against the *outgoing* creature before successor | save against ongoing condition; "end of turn" durations expire    |
| off turn          | applies to every creature that is *not* active         | reaction triggers (opportunity attacks); passive observation      |

Today the only phase logic baked into `Encounter.nextTurn` is the
**surprised-skip rule** (5e surprise): if the marker would land on
a creature with `surprised = True`, the creature is skipped and the
flag is cleared in the same step. A run of consecutive surprised
creatures all get skipped on one Next Turn click. A defensive
iteration cap (= queue length) prevents an all-surprised queue from
spinning. Other phase hooks (condition tickdown, regen, "start of
turn" abilities) will land as their own pure functions called from
the update loop.

There is also a "manual scrub" path: clicking the **→** arrow on any
creature card immediately makes that creature active without
advancing the turn. It dispatches `SetActive` rather than `NextTurn`,
which routes to `Encounter.setActive`. By design, `setActive`
deliberately *does not* increment `round` or fire turn-progression
hooks — neither the would-be end-of-turn for the previous active
creature nor the would-be beginning-of-turn for the new one. Future
hook composers must therefore branch off `nextTurn`, never
`setActive`. This mirrors how a GM at the table sometimes just says
"OK, switch to X next" without it counting as a round event.

## Initiative manager

Clicking the blue init-circle on any creature card opens the
**Initiative Manager** modal. It exposes three actions:

- **Quick Sort Encounter** re-orders the queue by descending
  initiative via `Encounter.sortByInitiative`. Stable tiebreakers
  are bonus desc, then name. `activeName` is preserved across the
  sort so re-sorting mid-combat doesn't reset whose turn it is.
- **Auto-roll Initiative** rolls `1d20 + creature.initiativeBonus`
  for either the click target, all creatures, or every creature
  with `selected = True`. Each main button has a green **Advantage**
  sibling on its right that uses `Dice.advantageGenerator`
  (2d20 keep highest, plus the bonus) instead. The Msg
  `InitiativeAutoRoll RollScope RollMode` is parameterized over the
  combination — `RollScope = ScopeTarget | ScopeAll | ScopeSelected`,
  `RollMode = ModeStandard | ModeAdvantage`. A future Disadvantage
  sister drops in as a third `RollMode` constructor. Goes through
  `Dice.batchRollCmd`, which is generic over the per-spec
  `Random.Generator Roll` and shares one timestamp + one sequenced
  seed-step across the batch — solves the "8 creatures all roll
  the same number" collision a per-call `Dice.rollCmd` would hit
  when fired N times in the same millisecond. Each roll lands in
  the dice history tagged `Initiative → <creature>` (advantage
  rolls render with the formula `Adv: 1d20+N` so the mode is
  visible at a glance) and persists via `/api/dice/history`.
- **Custom Initiative** sets each named creature's initiative to a
  manually-entered number, then sorts.

Manual queue reordering also exists at the row level: the up/down
arrows on each card swap the creature one slot via
`Encounter.moveUp` / `Encounter.moveDown` without touching
initiative numbers. The contract is: any `sortByInitiative` call
afterward (Quick Sort, Auto-roll & Sort) wipes the manual order.
Per-card moves are temporary; sorts are authoritative.

The selection checkboxes drive the modal's "Selected" buttons.
A plain click toggles one creature; **Shift+click** dispatches
`ShiftToggleSelected`, which selects all when any are unselected
and deselects all when every creature is selected. Implemented as
a `preventDefaultOn "click"` handler that decodes
`event.shiftKey` so model is the single source of truth for
checkbox state (no double-toggle from the browser default).


## HP change engine

The Damage / Heal / Temp HP buttons on card row 3 — and the future
ongoing-effect ticks, save-against-half resolutions, and direct GM
overrides — all funnel through `HpChange.elm`'s single
`apply : Change -> Creature -> Creature` entry point so the
arithmetic doesn't drift between code paths.

`Change` is an ADT:

  - `Damage { amount, ignoreTemp }` — temp HP soaks first (skippable
    via `ignoreTemp`); current HP clamps at 0.
  - `Heal Int` — caps at maxHp; clears `inDeathSaves` and the three
    death-save slots when reviving from 0.
  - `TempHp Int` — replace-if-higher (5e never-stacks rule).

`bloodied` is auto-recomputed after every `apply` from current vs.
max HP, so the row 2 🩸 chip stays honest without anyone touching
it manually.

The engine also exposes manual GM overrides:

  - `setCurrentHp : Int -> Creature -> Creature`
  - `setMaxHp : Int -> Creature -> Creature`

These skip the rule-flavored side effects (no temp soak, no death-
save clearing) — they're the "I just want to type 23" path. The
inline click-to-edit on the card row 2 HP values uses these.

UI side, the HP-change modal supports two input modes:

  - **Manual**: type the amount, see the before → after preview.
  - **Roll dice**: type a Dice expression (using the same parser as
    the dice modal). Apply rolls and applies in one shot, also
    logging the roll to the dice history tagged `Damage → Brakka,
    Ogre Brute` (or Heal / Temp HP) and persisting via
    `/api/dice/history`.

A bounded log of the last 10 HP changes lives at the bottom of the
modal (across all three verbs), so the GM can see recent table
context. The log is `Model.hpChangeLog : List HpChangeEntry`,
capped at `maxHpLogEntries = 10`.


## Creature identity

Creatures are currently identified by `name : String`. Every per-
creature `Msg` carries that name as its target. This is fine for the
mock cast where names are unique, but it'll break when a real
encounter has e.g. four "Goblin Skirmisher"s. When that day comes:

1. Add `id : String` (UUID or sequence) to `Creature`.
2. Switch `mapCreature` and the per-creature `Msg` payloads to use
   `id` instead of `name`.
3. Keep `name` as a display field that can collide.

This is intentionally deferred until the feature actually demands it.

## Dice roller

The dice roller is split across the layering boundary the same way
the encounter is. `Dice.elm` is the rules engine: notation parser
(supports `1d6`, compound `1d8 + 2d6`, damage tags `2d6 fire damage`,
and stat-block average wrap `7 (1d8 + 3)`), random-roll generators,
in-memory `History`, and `Dice.scan` for finding inline notation in
stat-block text. Advantage / disadvantage / coin flip have their own
generators rather than custom syntax — the JS roller worked the same
way.

`Main.elm`'s modal is the view layer. Clicking the **🎲 Roll** button
in the encounter controls header opens it; clicking any inline dice
notation rendered into a Compendium trait fires `RollFromStatBlock`,
which opens the modal *and* rolls in one user gesture.

Persistence is server-side rather than `localStorage` so the frontend
stays JS-free. Three endpoints handled in `crates/server/src/dice.rs`:

  - `GET    /api/dice/history`  → JSON array of rolls, newest first.
  - `POST   /api/dice/history`  → append one roll, truncate to 30
    (matches `Dice.maxHistoryEntries`), respond with the new list.
  - `DELETE /api/dice/history`  → clear.

The on-disk file location is configurable via `--dice-history-path`
(default `dice-history.json` in cwd; gitignored). The server treats
each roll as opaque JSON — the schema lives in `Dice.encodeRoll` /
`Dice.decodeRoll` on the Elm side, so you can extend it without
touching the server. Concurrent writes are serialized through an
async mutex, and writes go to a sibling tempfile that's renamed over
the target so a crash mid-write can't truncate the log.

## Production deployment

The intended target is a homelab-scale deployment: a handful of
concurrent users (say 1–20), self-hosted on a small Linux box,
fronted by a reverse proxy. We are explicitly NOT designing for
public internet scale or thousands of users.

**Auth.** The server already ships an OIDC scaffold
(`crates/server/src/auth.rs`). In a typical homelab deployment a
front-end SSO (Authelia, Keycloak, Authentik, Pocket ID) issues
tokens for `ezpz-dndz`; set `--oidc-issuer / --oidc-client-id /
--oidc-client-secret-file` (or the `OIDC_ISSUER` / `OIDC_CLIENT_ID`
/ `OIDC_CLIENT_SECRET_FILE` env vars) and the server uses the OIDC
client. With OIDC unconfigured, the server runs unauthenticated and
`/me` returns a stubbed `admin` user; that's the local-dev mode.

**Persistence root.** Everything the server writes at runtime lives
under `--data-dir` (default: cwd). Today that's only the dice
history JSON (`<data_dir>/dice-history.json`); the planned SQLite
database, saved encounters, and per-user uploads will all default
to `<data_dir>/...` so a deployment only has to bind-mount one
directory. See [ROADMAP.md](ROADMAP.md) for the planned data model.

**Service unit.** The systemd service expectations live in
[systemd.org](systemd.org). `sd-notify` is wired up and the server
honors socket activation via `--listen sd-listen`.

**TLS.** Out of scope for this server. Run behind a reverse proxy
(Caddy, nginx, traefik) that terminates TLS and forwards to the
listen address. `--base-url` should be the externally-visible URL
the proxy publishes — that's what shows up in OIDC redirect URIs.

## Planned data model

Sketch of the storage we expect to land as features ship; subject
to change. Current implementation persists dice history only.

| Concern              | Today                        | Target                     |
|----------------------|------------------------------|----------------------------|
| User identity        | OIDC subject in session      | `users` table, OIDC subject as natural key |
| Compendium creatures | hardcoded `Encounter.seedCreatures` (Elm) | `creatures` table with shared/private visibility |
| Encounter saves      | none (in-memory only)        | `encounters` table, owner-scoped |
| Dice history         | per-deployment JSON file     | `dice_rolls` table, optionally per-user |

The first feature that needs persistence beyond dice will likely
introduce SQLite (rusqlite or sqlx). Until then, rolls live in JSON
and the rest is in-Elm seed data.

## Run / build / test

```sh
just dev      # build Elm, start server, open browser at 127.0.0.1:4040
just serve    # same minus opening the browser
just build    # full build (cargo + elm)
just test     # all Rust tests + Elm compile check
```

`just dev` and `just serve` self-bootstrap into the Nix dev shell if
`cargo` or `elm` aren't on PATH, so they work from a clean terminal.

## Where to put things

| Adding…                                          | Goes in…                                |
|--------------------------------------------------|------------------------------------------|
| A new per-creature toggle / state field          | `Encounter.Creature` + a `Msg` + an `update` branch + a view helper |
| A new turn-phase rule                            | a new pure function in `Encounter.elm`, called from the relevant `Msg` branch |
| A new HP-affecting effect                        | a new `HpChange.Change` variant + clause in `apply`; HP-change modal callers route through it |
| A new tag / source for a roll (so it shows up in dice history) | a `Dice.Source { feature, target }` value at the call site; `Dice.rollCmd` + friends accept it |
| A new visual element on a card / panel           | a view function in `Main.elm` (or a future View module) |
| A new modal                                      | `Maybe SomeUi` field on `Model`, `with*` helper next to `withEncounter`, view function returning `text ""` when closed |
| A new color / spacing token                      | a CSS custom property in `:root` (and its dark-mode override) in `style.css` |
| A new creature for the seed encounter            | `Encounter.seedCreatures`                |
| A new dice operator or notation form             | `Dice.elm` parser + (if shape changes) `encodeRoll` / `decodeRoll` |
| A new HTTP route handled by the backend          | `crates/server/src/web_base.rs` (or a sibling module merged in) |
| A new dev script (build / serve / package)       | `justfile`                               |

When in doubt: rules in `Encounter` / `Dice` / `HpChange`,
presentation in `Main` / CSS, ops in `justfile`.
