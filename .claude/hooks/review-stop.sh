#!/usr/bin/env bash
# Stop hook: the code-review gate.
#
# Claude Code runs this outside the Nix dev shell, so the gate binary is not
# reliably on PATH: direnv supplies it once a shell has entered the project,
# and `nix develop` supplies it otherwise.  Preferring the one already on PATH
# keeps the common case free of a shell evaluation on every turn end.
#
# The nested reviewer is pinned to Opus.  Left unset, it follows the CLI's
# default, which is whatever model the person has selected for the session,
# so the review's judgment would drift with a choice made for other reasons.

reviewer_model=opus

if command -v rust-template-review-stop > /dev/null 2>&1; then
  exec rust-template-review-stop --reviewer-model "$reviewer_model" "$@"
fi

exec nix develop --command \
  rust-template-review-stop --reviewer-model "$reviewer_model" "$@"
