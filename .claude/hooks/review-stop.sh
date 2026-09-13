#!/usr/bin/env bash
# Stop hook: the code-review gate.
#
# Claude Code runs this outside the Nix dev shell, so the gate binary is not
# reliably on PATH: direnv supplies it once a shell has entered the project,
# and `nix develop` supplies it otherwise.  Preferring the one already on PATH
# keeps the common case free of a shell evaluation on every turn end.

if command -v rust-template-review-stop > /dev/null 2>&1; then
  exec rust-template-review-stop "$@"
fi

exec nix develop --command rust-template-review-stop "$@"
