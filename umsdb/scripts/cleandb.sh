#!/bin/bash
# cleandb.sh — DROP umsdb and ums_user completely. Leaves a clean slate.
# Opposite of startdb.sh. Run INSIDE mypostgresql_db-container.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }

PSQL_SUPER="psql -U $PG_SUPERUSER -h $PG_HOST -p $PG_PORT"

echo ""
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
warn "  DROP database '$UMS_DB' and user '$UMS_USER'"
warn "  ALL DATA WILL BE LOST. Nothing is recreated."
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "${1:-}" != "--yes" ]; then
    read -rp "Type YES to confirm: " CONFIRM
    [ "$CONFIRM" = "YES" ] || { info "Cancelled."; exit 0; }
fi

info "Terminating active connections to '$UMS_DB'..."
$PSQL_SUPER -c \
    "SELECT pg_terminate_backend(pid)
     FROM pg_stat_activity
     WHERE datname = '$UMS_DB' AND pid <> pg_backend_pid();" -q

info "Dropping database '$UMS_DB'..."
$PSQL_SUPER -c "DROP DATABASE IF EXISTS \"$UMS_DB\";" -q
success "Database '$UMS_DB' dropped."

info "Dropping user '$UMS_USER'..."
$PSQL_SUPER -c "DROP ROLE IF EXISTS \"$UMS_USER\";" -q
success "User '$UMS_USER' dropped."

echo ""
success "Clean complete — run startdb.sh to recreate from scratch."
