#!/bin/bash
# restore_wholedb.sh — Restore all databases from a pg_dumpall backup.
# Run INSIDE mypostgresql_db-container.
# Usage: bash restore_wholedb.sh <backup_file.sql.gz>
set -euo pipefail

# ── Mirror logging ─────────────────────────────────────────────────────────────
_SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
_BASE="$(basename "$_SELF_ABS")"; _EXT="${_BASE##*.}"; _STEM="${_BASE%.*}"
_REL_DIR="$(dirname "${_SELF_ABS#${CONTAINER_WORKDIR:-}/}")"
[ "$_REL_DIR" = "." ] && _REL_DIR="" || _REL_DIR="/$_REL_DIR"
LOG_FILE="${LOG_MIRROR_ROOT:-/tmp/logs}${_REL_DIR}/${_STEM}_${_EXT}.log"
mkdir -p "$(dirname "$LOG_FILE")" && export LOG_FILE
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' | tee -a "$LOG_FILE") 2>&1
echo "[logging] → $LOG_FILE"
# ──────────────────────────────────────────────────────────────────────────────

BACKUP_FILE="${1:-}"
if [ -z "$BACKUP_FILE" ]; then
    echo "[ERROR] Usage: bash restore_wholedb.sh <backup_file.sql.gz>"
    exit 1
fi
if [ ! -f "$BACKUP_FILE" ]; then
    echo "[ERROR] File not found: $BACKUP_FILE"
    exit 1
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../umsdb/.env"

echo "[INFO] Restoring all databases from $BACKUP_FILE..."
gunzip -c "$BACKUP_FILE" | psql -U "$PG_SUPERUSER" -h "$PG_HOST" -p "$PG_PORT" postgres
echo "[OK]  Restore complete."
