# Default address the dev server binds to.  Override with
#   just listen=127.0.0.1:8000 dev
listen := "127.0.0.1:4040"
dev_url := "http://" + listen

# Show the available recipes.
default:
    @just --list

# Build both Rust and Elm.
build: build-elm build-rust

# Build the Elm frontend.
build-elm:
    cd frontend && elm make src/Main.elm --output public/elm.js

# Build all Rust workspace crates.
build-rust:
    cargo build --workspace

# Run all tests (Elm tests + Rust test suite).
test: test-elm test-rust

# Run the Elm test suite (frontend/tests/*Test.elm).
test-elm:
    cd frontend && elm-test

# Run the Rust test suite.
test-rust:
    cargo test --workspace

# Build Elm then run via cargo, forwarding all arguments.
run *args: build-elm
    cargo run {{args}}

# Build, start the server, and open the browser. Auto-enters the Nix dev shell.
dev:
    #!/usr/bin/env bash
    set -euo pipefail
    # The user's interactive shell typically gets nix on PATH via a
    # profile script (.zshrc / .bash_profile sources it).  Bash
    # subshells spawned by `just` don't auto-load that, so source
    # the standard nix-init scripts directly if they exist.
    for nix_init in \
        /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
        "$HOME/.nix-profile/etc/profile.d/nix.sh" \
        /etc/profile.d/nix.sh; do
        if [ -f "$nix_init" ]; then
            . "$nix_init"
            break
        fi
    done
    if ! command -v cargo >/dev/null 2>&1 || ! command -v elm >/dev/null 2>&1; then
        if ! command -v nix >/dev/null 2>&1; then
            echo "error: nix not found on PATH and the nix profile init scripts" >&2
            echo "       weren't located either.  Install Nix, or run inside an" >&2
            echo "       active nix shell:" >&2
            echo "         nix develop" >&2
            echo "         just dev" >&2
            exit 1
        fi
        exec nix develop --command just dev
    fi
    ( cd frontend && elm make src/Main.elm --output public/elm.js )
    echo "Starting ezpz-dndz on {{dev_url}}"
    ( sleep 1.5 && open "{{dev_url}}" ) &
    exec cargo run -p ezpz-dndz-server -- \
        --listen {{listen}} \
        --base-url {{dev_url}}

# Same as `dev` but skip opening the browser (handy in tmux).
serve:
    #!/usr/bin/env bash
    set -euo pipefail
    for nix_init in \
        /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
        "$HOME/.nix-profile/etc/profile.d/nix.sh" \
        /etc/profile.d/nix.sh; do
        if [ -f "$nix_init" ]; then
            . "$nix_init"
            break
        fi
    done
    if ! command -v cargo >/dev/null 2>&1 || ! command -v elm >/dev/null 2>&1; then
        if ! command -v nix >/dev/null 2>&1; then
            echo "error: nix not found on PATH and the nix profile init scripts" >&2
            echo "       weren't located either.  Install Nix, or run inside an" >&2
            echo "       active nix shell:" >&2
            echo "         nix develop" >&2
            echo "         just serve" >&2
            exit 1
        fi
        exec nix develop --command just serve
    fi
    ( cd frontend && elm make src/Main.elm --output public/elm.js )
    exec cargo run -p ezpz-dndz-server -- \
        --listen {{listen}} \
        --base-url {{dev_url}}

# Promote a custom creature from the running dev server into the
# embedded bundle.  Fetches the creature via the server's REST
# API, rewrites it with a stable bundle UUID, appends to
# bundled-creatures.json, and bumps BUNDLED_VERSION.  Run while
# the dev server is up (`just dev` in another shell) and pass the
# creature's UUID — easiest way to find that is the stat-block
# panel's ↗ button (URL ends with the UUID), or click into it in
# the browser modal and inspect the network tab.
#
#   just promote-to-bundle <uuid>
promote-to-bundle id:
    @python3 scripts/promote-to-bundle.py {{id}} --server {{dev_url}}

# Allow direnv for this project so the Nix dev shell auto-activates on cd.
# Requires direnv to be installed (`brew install direnv`) and hooked into your shell.
setup-direnv:
    direnv allow

# Combine all passing open Dependabot PRs into one PR and merge it.
#
# One-shot catch-up for a Dependabot backlog: takes the versions Dependabot
# already resolved, bundles the passing bumps onto one branch, opens a single
# PR, and merges it once green (failing bumps are left for a human).  Per-PR
# auto-merge handles the steady-state trickle.  Pass --dry-run or --no-merge to
# hold back.
dependabot-combine *args:
    dependabot-combine {{args}}

# Bump every dependency the workspace's constraints allow, with changelog.
#
# The working-tree half of the scheduled dependency-bump flow: runs `cargo
# update` across the workspace, classifies each bump against `cargo audit`,
# and composes the CHANGELOG entries — then stops.  Nothing is committed or
# pushed; review the diff and commit yourself.  The scheduled workflow
# (.github/workflows/dependency-bump.yml) runs the same engine and owns the
# branch/PR/merge half.  Pass --dry-run true to preview.
dependency-bump *args:
    dependency-bump {{args}}

# Reclaim disk from stale build artifacts.
#
# Cargo names every artifact after a hash of its inputs and never
# deletes superseded ones, so target/ grows without bound — this
# project reached 8.5 GB (97% of it garbage) after three months
# before the first sweep.  `--time 14` keeps anything a build has
# touched in the last two weeks, so the current working set
# survives and nothing needs an immediate rebuild.
#
# The devshell nudges when the marker below goes stale; run this
# whenever it does, or any time target/ feels heavy.
sweep:
    cargo sweep --time 14
    @mkdir -p target && touch target/.last-sweep
    @du -sh target
