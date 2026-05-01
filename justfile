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
    if ! command -v cargo >/dev/null 2>&1 || ! command -v elm >/dev/null 2>&1; then
        exec nix develop --command just dev
    fi
    ( cd frontend && elm make src/Main.elm --output public/elm.js )
    echo "Starting ezpz-dndz on {{dev_url}}"
    ( sleep 1.5 && open "{{dev_url}}" ) &
    exec cargo run -p ezpz-dndz-server -- \
        --listen {{listen}} \
        --base-url {{dev_url}} \
        --frontend-path frontend/public

# Same as `dev` but skip opening the browser (handy in tmux).
serve:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v cargo >/dev/null 2>&1 || ! command -v elm >/dev/null 2>&1; then
        exec nix develop --command just serve
    fi
    ( cd frontend && elm make src/Main.elm --output public/elm.js )
    exec cargo run -p ezpz-dndz-server -- \
        --listen {{listen}} \
        --base-url {{dev_url}} \
        --frontend-path frontend/public

# Allow direnv for this project so the Nix dev shell auto-activates on cd.
# Requires direnv to be installed (`brew install direnv`) and hooked into your shell.
setup-direnv:
    direnv allow
