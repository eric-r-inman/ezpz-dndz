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
│   ├── server/   ezpz-dndz-server (axum)
│   └── lib/      ezpz-dndz-lib (shared types, logging)
├── frontend/
│   ├── src/
│   │   ├── Main.elm        application shell + view code
│   │   └── Encounter.elm   domain layer (types, rules, turn logic)
│   └── public/
│       ├── index.html      mounts Elm into #app
│       ├── style.css       all styles, dual light/dark via vars
│       └── elm.js          (gitignored, built by `elm make`)
└── docs/
    ├── ARCHITECTURE.md     this file
    └── systemd.org         deployment notes
```

## Layering: domain vs view

> **The rule:** D&D rules logic lives in `Encounter.elm`. UI code (`Main.elm`,
> any future View modules) imports `Encounter` and uses its types and
> functions. Logic code never imports view code.

The reason this matters now: we're going to ship multiple UI layouts
(a "simple view" stripped of advanced controls, possibly a tablet
layout, etc.). Each layout still operates on the same encounter state
and the same turn rules. If rules code starts importing `Html`,
swapping layouts means rewriting rules — not acceptable.

In practice this means:

- `Encounter.elm` does not `import Html`, `Browser`, `Url`, or any
  rendering primitive. The compiler will tell you if you accidentally
  reach for one.
- A `Msg` branch in `Main.elm`'s `update` should be a one-liner that
  delegates the rules-y work into `Encounter`. If the branch starts
  doing list walks, comparisons against initiative, or HP arithmetic
  inline, the work belongs in `Encounter`.
- The seed encounter (`Encounter.initialEncounter`) is the
  authoritative starting state. `Main.init` just wires it into the
  Model; it doesn't pick its own creatures.

There's a tiny seam: `Main.elm` defines a `withEncounter` helper that
lifts an `Encounter -> Encounter` transformation into a `Model -> Model`
update. That keeps every per-creature toggle one line and keeps the
rest of `Model` (route, auth, nav key) literally invisible to domain
code, which is what we want.

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

Today only the queue advance is implemented. Each phase will land as
its own pure function in `Encounter.elm`, and `Main`'s `update` for
`NextTurn` will compose them around the existing `nextTurn` call.

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
| A new visual element on a card / panel           | a view function in `Main.elm` (or a future View module) |
| A new color / spacing token                      | a CSS custom property in `:root` (and its dark-mode override) in `style.css` |
| A new creature for the seed encounter            | `Encounter.seedCreatures`                |
| A new HTTP route handled by the backend          | `crates/server/src/web_base.rs`          |
| A new dev script (build / serve / package)       | `justfile`                               |

When in doubt: rules in `Encounter`, presentation in `Main` / CSS,
ops in `justfile`.
