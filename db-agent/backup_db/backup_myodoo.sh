#!/bin/bash
# backup_myodoo.sh — Dump the myodoo (Odoo) database to a timestamped gzipped SQL file.
# Run INSIDE mypostgresql_db-container.
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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../myodoo/.env"

BACKUP_DIR="/backups/myodoo"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/myodoo_$TIMESTAMP.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[INFO] Backing up $ODOO_DB..."
pg_dump -U "$ODOO_USER" -h "$PG_HOST" -p "$PG_PORT" "$ODOO_DB" | gzip > "$BACKUP_FILE"
echo "[OK]  Saved to $BACKUP_FILE"
