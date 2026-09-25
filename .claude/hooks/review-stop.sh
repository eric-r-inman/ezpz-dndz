#!/usr/bin/env bash
# Stop hook: the code-review gate, which keeps a turn from ending while the
# working tree holds changes the review has not cleared.
#
# The template ships no gate for this hook, so the gate lives here, over the
# review tool the dev shell provides.  See CONTRIBUTING.org, Code review.

set -uo pipefail

# The reviewer is itself a Claude Code session in this repository, so without
# this marker its own turn end would run the gate, and the gate would review
# the reviewer.
if [[ -n ${EZPZ_REVIEW_GATE_REVIEWING:-} ]]; then
  exit 0
fi

stuck="The gate keeps blocking the turn until it can run.  Do not work around \
the gate; if the cause is not yours to fix, report this error to the human \
verbatim."

# A gate that cannot run blocks rather than stands aside.  Claude Code hands a
# hook's stderr to the session as the reason when the hook exits 2.
fail() {
  echo "$*  $stuck" >&2
  exit 2
}

# Claude Code runs the hook in the session's current directory, which follows
# the session's shell after a `cd`; left there, the gate would review whatever
# tree the session last wandered into.
if [[ -z ${CLAUDE_PROJECT_DIR:-} ]] || ! cd "$CLAUDE_PROJECT_DIR"; then
  fail "The review gate could not enter the project directory," \
    "'${CLAUDE_PROJECT_DIR:-}'."
fi

input=$(cat)

# A plan-mode turn cannot edit the tree, so blocking it on a finding would
# leave the session nothing it could do.  jq is not on PATH until the dev shell
# below loads, and a plan-mode turn should not pay to load it, so the mode is
# matched as a pattern rather than parsed.
if [[ $input =~ \"permission_mode\"[[:space:]]*:[[:space:]]*\"plan\" ]]; then
  exit 0
fi

git rev-parse --is-inside-work-tree > /dev/null 2>&1 ||
  fail "The review gate found no git work tree at $PWD."
changes=$(git status --porcelain --untracked-files=all)
if [[ -z $changes ]]; then
  exit 0
fi

# Claude Code runs this outside the Nix dev shell, so the tools are on PATH
# only when direnv has already loaded it; otherwise the gate runs again inside
# one.
if ! command -v review > /dev/null 2>&1 || ! command -v jq > /dev/null 2>&1; then
  if [[ -z ${EZPZ_REVIEW_GATE_IN_SHELL:-} ]] &&
    printf '%s' "$input" |
    EZPZ_REVIEW_GATE_IN_SHELL=1 nix develop --command "$0"; then
    exit 0
  fi
  fail "The review gate could not reach the review tool in the Nix dev shell;" \
    "the error is above."
fi

# Claude Code takes a block from this document on stdout; a release is a hook
# that prints nothing.
block() {
  jq --null-input --arg reason "$1" '{decision: "block", reason: $reason}'
  exit 0
}

# `git status --porcelain` wraps a path holding unusual characters in double
# quotes, hence the optional closing quote; and a case-insensitive filesystem
# compiles MAIN.RS as readily as main.rs, so the extension matches in any case.
if grep -qiE '\.rs"?$' <<< "$changes"; then
  if ! clippy=$(cargo clippy --workspace --all-targets --all-features \
    --color never -- --deny warnings 2>&1); then
    block "clippy reported problems on the Rust changes this turn.  Resolve \
every warning before ending the turn; this is the same gate CI enforces:

    cargo clippy --workspace --all-targets --all-features -- --deny warnings

$clippy"
  fi
fi

log=$(mktemp)
trap 'rm -f "$log"' EXIT
report=$(EZPZ_REVIEW_GATE_REVIEWING=1 review --diff head --reviewer-model opus \
  2> "$log")
case $? in
  0)
    exit 0
    ;;
  1)
    block "The review found problems in the working tree:

$report

Address every finding.  The gate reviews the tree again when the turn next \
ends, and releases only when the review finds nothing."
    ;;
  *)
    # The review tool colours its log while a block reason is plain text, and a
    # run that stalls leaves a log of any length, so the reason carries only the
    # log's last lines, with the colour codes stripped.
    block "The review gate could not complete.

$report
$(sed $'s/\e\\[[0-9;]*m//g' "$log" | tail -n 20)

$stuck"
    ;;
esac
