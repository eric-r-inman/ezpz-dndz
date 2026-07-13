#!/usr/bin/env bash
#
# backup.sh — snapshot ezpz-dndz state to a compressed archive.
#
# Runtime state lives under the data dir: the SQLite database
# (`ezpz-dndz.db`, the default backend) plus the legacy JSON files
# kept as import inputs / rollback copies.  This script snapshots
# that directory to a single `.tar.gz` per run, named after the
# current UTC timestamp so the archive list sorts chronologically.
# The live SQLite file is never copied raw — it is snapshotted
# consistently through sqlite3's online-backup API first, and the
# snapshot goes into the archive in its place.  Designed to be
# invoked by a systemd timer (Linux) or launchd job (macOS) on a
# daily cadence, but safe to run by hand from any shell.
#
# PostgreSQL deployments (`--database-url postgres://…`) keep no
# database file in the data dir; back those up with pg_dump on its
# own schedule — that is out of scope for this script.
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
#   4  SQLite snapshot failed (a database file exists but could
#      not be snapshotted consistently; nothing is archived).

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
      sed -n '4,50p' "$0"
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
TMP_TAR="$DEST.partial.tar"
STAGING=""

# Trap unfinished writes — the atomic rename onto $DEST only happens
# on success, and the database-snapshot staging dir never outlives
# the run.
cleanup() {
  rm -f "$TMP" "$TMP_TAR"
  if [[ -n "$STAGING" && -d "$STAGING" ]]; then
    rm -rf "$STAGING"
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
EXCLUDES=()
if [[ "$BACKUP_ABS" == "$DATA_ABS"/* ]]; then
  EXCLUDES+=(--exclude="./${BACKUP_ABS#"$DATA_ABS"/}")
fi

# ── SQLite snapshot ─────────────────────────────────────────────────
# A live SQLite file must never be plain-copied — a copy taken while
# the server is mid-write is torn.  Snapshot it consistently into a
# staging dir via sqlite3's online-backup API (`.backup`), falling
# back to `VACUUM INTO` for sqlite3 builds without the dot-command,
# then archive the snapshot in place of the raw file.  The raw file
# and its -wal/-shm/-journal sidecars are excluded from the tar.
DB_NAME="ezpz-dndz.db"
DB_FILE="$DATA_ABS/$DB_NAME"
if [[ -f "$DB_FILE" ]]; then
  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "backup.sh: $DB_FILE exists but sqlite3 is not installed;" \
         "refusing to plain-copy a live database" >&2
    exit 4
  fi
  STAGING="$(mktemp -d "${TMPDIR:-/tmp}/ezpz-dndz-backup.XXXXXX")"
  if ! sqlite3 "$DB_FILE" ".backup '$STAGING/$DB_NAME'"; then
    echo "backup.sh: sqlite3 .backup failed; retrying with VACUUM INTO" >&2
    rm -f "$STAGING/$DB_NAME"
    if ! sqlite3 "$DB_FILE" "VACUUM INTO '$STAGING/$DB_NAME'"; then
      echo "backup.sh: SQLite snapshot failed" >&2
      exit 4
    fi
  fi
  EXCLUDES+=(
    --exclude="./$DB_NAME"
    --exclude="./$DB_NAME-wal"
    --exclude="./$DB_NAME-shm"
    --exclude="./$DB_NAME-journal"
  )
fi

# Create uncompressed first, append the database snapshot in a
# second invocation, then compress.  The append can't ride on the
# create call: tar's exclude patterns normalize the `./` prefix, so
# `--exclude=./ezpz-dndz.db` (needed to keep the raw live file out)
# would also swallow the staged snapshot entry of the same name.
# The `${arr[@]+…}` expansion keeps `set -u` happy on bash 3.2
# (macOS), where expanding an empty array is an unbound-variable
# error.
tar ${EXCLUDES[@]+"${EXCLUDES[@]}"} \
    -cf "$TMP_TAR" \
    -C "$DATA_ABS" \
    . || {
  echo "backup.sh: tar failed" >&2
  exit 3
}
if [[ -n "$STAGING" ]]; then
  tar -rf "$TMP_TAR" -C "$STAGING" "$DB_NAME" || {
    echo "backup.sh: tar append of the database snapshot failed" >&2
    exit 3
  }
fi
gzip -c "$TMP_TAR" > "$TMP" || {
  echo "backup.sh: gzip failed" >&2
  exit 3
}
rm -f "$TMP_TAR"

mv "$TMP" "$DEST"

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
