#!/bin/bash
# cleandb_all.sh — DROP all project databases and users. Leaves a clean slate.
# Run INSIDE mypostgresql_db-container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/umsdb/.env"
source "$PROJECT_DIR/mydocsdb/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }

PSQL_SUPER="psql -U $PG_SUPERUSER -h $PG_HOST -p $PG_PORT"

echo ""
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
warn "  DROP all databases: '$UMS_DB', '$DOCS_DB'"
warn "  DROP all users:     '$UMS_USER', '$DOCS_USER'"
warn "  ALL DATA WILL BE LOST. Nothing is recreated."
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "${1:-}" != "--yes" ]; then
    read -rp "Type YES to confirm: " CONFIRM
    [ "$CONFIRM" = "YES" ] || { info "Cancelled."; exit 0; }
fi

for DB in "$UMS_DB" "$DOCS_DB"; do
    info "Terminating active connections to '$DB'..."
    $PSQL_SUPER -c \
        "SELECT pg_terminate_backend(pid)
         FROM pg_stat_activity
         WHERE datname = '$DB' AND pid <> pg_backend_pid();" -q
    info "Dropping database '$DB'..."
    $PSQL_SUPER -c "DROP DATABASE IF EXISTS \"$DB\";" -q
    success "Database '$DB' dropped."
done

for ROLE in "$UMS_USER" "$DOCS_USER"; do
    info "Dropping user '$ROLE'..."
    $PSQL_SUPER -c "DROP ROLE IF EXISTS \"$ROLE\";" -q
    success "User '$ROLE' dropped."
done

echo ""
success "All clean — run each startdb.sh to recreate from scratch."
