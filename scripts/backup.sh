#!/usr/bin/env bash
#
# backup.sh — snapshot ezpz-dndz state to a compressed archive.
#
# The whole runtime persistence layer lives as plain JSON files under
# the data dir.  This script snapshots that directory to a single
# `.tar.gz` per run, named after the current UTC timestamp so the
# archive list sorts chronologically.  Designed to be invoked by a
# systemd timer (Linux) or launchd job (macOS) on a daily cadence,
# but safe to run by hand from any shell.
#
# Usage:
#   backup.sh                         # uses defaults
#   DATA_DIR=/var/lib/ezpz-dndz       \
#   BACKUP_DIR=/var/backups/ezpz-dndz \
#   RETENTION_DAYS=14                 \
#     backup.sh
#
#   backup.sh --data-dir <path> --backup-dir <path> --retention-days <N>
#
# Environment variables (overridden by CLI flags):
#
#   DATA_DIR        Source directory whose contents get archived.
#                   Default: $XDG_DATA_HOME/ezpz-dndz, then ./data,
#                   then ./.
#
#   BACKUP_DIR      Destination directory for the .tar.gz files.
#                   Default: $DATA_DIR/backups.  Created if missing.
#
#   RETENTION_DAYS  Maximum age of an archive in days before it's
#                   pruned.  Default: 14.  Set to 0 to keep
#                   forever.
#
# Exit codes:
#   0  Success.
#   1  Argument or configuration error.
#   2  Source directory missing or unreadable.
#   3  Archive creation failed (the partial file is removed).

set -euo pipefail

# ── defaults ────────────────────────────────────────────────────────
DATA_DIR="${DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ezpz-dndz}"
BACKUP_DIR="${BACKUP_DIR:-}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

# ── argument parsing ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-dir)
      DATA_DIR="$2"
      shift 2
      ;;
    --backup-dir)
      BACKUP_DIR="$2"
      shift 2
      ;;
    --retention-days)
      RETENTION_DAYS="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '4,40p' "$0"
      exit 0
      ;;
    *)
      echo "backup.sh: unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR="$DATA_DIR/backups"
fi

if [[ ! -d "$DATA_DIR" ]]; then
  echo "backup.sh: data dir not found: $DATA_DIR" >&2
  exit 2
fi

mkdir -p "$BACKUP_DIR"

# ── archive ─────────────────────────────────────────────────────────
# UTC ISO-8601 with colons stripped — filenames must avoid ':' on
# common filesystems.  Sorts lexicographically because the format is
# year-first, fixed-width.
TS="$(date -u +'%Y-%m-%dT%H-%M-%SZ')"
DEST="$BACKUP_DIR/ezpz-dndz-$TS.tar.gz"
TMP="$DEST.partial"

# Trap unfinished writes — atomic rename only happens on success.
cleanup() {
  if [[ -e "$TMP" ]]; then
    rm -f "$TMP"
  fi
}
trap cleanup EXIT

# Exclude the backups subdirectory itself (and previous partials)
# from the archive so backups don't snowball — each snapshot is
# only the live data, never recursive backups-of-backups.
#
# Resolve the absolute path so the exclusion matches whether the
# user pointed at a relative or absolute --data-dir.
DATA_ABS="$(cd "$DATA_DIR" && pwd)"
BACKUP_ABS="$(cd "$BACKUP_DIR" && pwd)"
EXCLUDE_REL=""
if [[ "$BACKUP_ABS" == "$DATA_ABS"/* ]]; then
  EXCLUDE_REL="${BACKUP_ABS#$DATA_ABS/}"
fi

if [[ -n "$EXCLUDE_REL" ]]; then
  tar --exclude="./$EXCLUDE_REL" \
      -czf "$TMP" \
      -C "$DATA_DIR" \
      . || {
    echo "backup.sh: tar failed" >&2
    exit 3
  }
else
  tar -czf "$TMP" -C "$DATA_DIR" . || {
    echo "backup.sh: tar failed" >&2
    exit 3
  }
fi

mv "$TMP" "$DEST"
trap - EXIT

SIZE="$(wc -c <"$DEST" | tr -d '[:space:]')"
echo "backup.sh: wrote $DEST ($SIZE bytes)"

# ── retention prune ─────────────────────────────────────────────────
# Only act on files that match our own naming so manual archives in
# the same directory are never touched.
if [[ "$RETENTION_DAYS" -gt 0 ]]; then
  find "$BACKUP_DIR" \
       -maxdepth 1 \
       -type f \
       -name 'ezpz-dndz-*.tar.gz' \
       -mtime "+$RETENTION_DAYS" \
       -print \
       -delete
fi
