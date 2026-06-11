#!/bin/bash
# reset_db.sh — DROP and fully recreate mydocsdb. DEV ONLY.
# All data is destroyed. Plane's migrator will recreate tables on next start.
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
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

PSQL_SUPER="psql -U $PG_SUPERUSER -h $PG_HOST -p $PG_PORT"

echo ""
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
warn "  This will DROP database '$DOCS_DB'."
warn "  ALL DATA WILL BE LOST."
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "${1:-}" != "--yes" ]; then
    read -rp "Type YES to confirm: " CONFIRM
    [ "$CONFIRM" = "YES" ] || { info "Cancelled."; exit 0; }
fi

info "Terminating active connections to '$DOCS_DB'..."
$PSQL_SUPER -c \
    "SELECT pg_terminate_backend(pid)
     FROM   pg_stat_activity
     WHERE  datname = '$DOCS_DB' AND pid <> pg_backend_pid();" -q

info "Dropping database '$DOCS_DB'..."
$PSQL_SUPER -c "DROP DATABASE IF EXISTS \"$DOCS_DB\";" -q
success "Database dropped."

info "Re-creating from scratch..."
bash "$SCRIPT_DIR/startdb.sh" --prepare-only
