#!/bin/bash
# reset_db.sh — DROP and fully recreate the UMS database. DEV ONLY.
# All data is destroyed. Use prepare_db.sh to rebuild from scratch.
set -euo pipefail

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
warn "  This will DROP database '$UMS_DB'."
warn "  ALL DATA WILL BE LOST."
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Skip confirmation if --yes flag passed
if [ "${1:-}" != "--yes" ]; then
    read -rp "Type YES to confirm: " CONFIRM
    [ "$CONFIRM" = "YES" ] || { info "Cancelled."; exit 0; }
fi

info "Terminating active connections to '$UMS_DB'..."
$PSQL_SUPER -c \
    "SELECT pg_terminate_backend(pid)
     FROM   pg_stat_activity
     WHERE  datname = '$UMS_DB' AND pid <> pg_backend_pid();" -q

info "Dropping database '$UMS_DB'..."
$PSQL_SUPER -c "DROP DATABASE IF EXISTS \"$UMS_DB\";" -q
success "Database dropped."

info "Re-running startdb.sh..."
bash "$SCRIPT_DIR/startdb.sh" --prepare-only
