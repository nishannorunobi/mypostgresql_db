#!/bin/bash
# startdb.sh — Prepare the mydocsdb database and open a psql shell.
# Run INSIDE mypostgresql_db-container.
# Flags:
#   --prepare-only   Skip the psql shell (used by reset_db.sh)
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
INIT_DIR="$PROJECT_DIR/init"

source "$PROJECT_DIR/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

PREPARE_ONLY=false
[ "${1:-}" = "--prepare-only" ] && PREPARE_ONLY=true

PSQL_SUPER="psql -U $PG_SUPERUSER -h $PG_HOST -p $PG_PORT"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       MYDOCS DB — START              ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
echo ""

# ── 1. Verify PostgreSQL is running ──────────────────────────────────────────
if ! pg_isready -h "$PG_HOST" -p "$PG_PORT" -q 2>/dev/null; then
    error "PostgreSQL is not running. Start it first via the container entrypoint."
    exit 1
fi
success "PostgreSQL is running."

# ── 2. Create application user ────────────────────────────────────────────────
info "Creating user '$DOCS_USER'..."
$PSQL_SUPER -v DOCS_USER="$DOCS_USER" -v DOCS_PASSWORD="$DOCS_PASSWORD" \
    -f "$INIT_DIR/01_create_user.sql" -q

# ── 3. Create database ────────────────────────────────────────────────────────
info "Checking database '$DOCS_DB'..."
DB_EXISTS=$($PSQL_SUPER -tc \
    "SELECT 1 FROM pg_database WHERE datname='$DOCS_DB'" | tr -d '[:space:]')

if [ "$DB_EXISTS" = "1" ]; then
    warn "Database '$DOCS_DB' already exists — skipping creation."
else
    info "Creating database '$DOCS_DB'..."
    $PSQL_SUPER -v DOCS_DB="$DOCS_DB" -v DOCS_USER="$DOCS_USER" \
        -f "$INIT_DIR/02_create_database.sql" -q
    success "Database '$DOCS_DB' created."
fi

# ── 4. Apply extensions and grants ───────────────────────────────────────────
info "Applying extensions and grants..."
psql -U "$PG_SUPERUSER" -h "$PG_HOST" -p "$PG_PORT" -d "$DOCS_DB" \
    -v DOCS_DB="$DOCS_DB" -v DOCS_USER="$DOCS_USER" \
    -f "$INIT_DIR/03_grants.sql" -q
success "Grants applied."

echo ""
success "Database is ready!"
echo ""
echo -e "  ${BOLD}Host     ${RESET}  $PG_HOST:$PG_PORT"
echo -e "  ${BOLD}Database ${RESET}  $DOCS_DB"
echo -e "  ${BOLD}User     ${RESET}  $DOCS_USER"
echo ""
echo -e "  Tables will be created by Plane's migrator on first start."
echo ""

$PREPARE_ONLY && exit 0

info "Connecting to '$DOCS_DB' as '$DOCS_USER'..."
echo -e "  (run ${BOLD}\\q${RESET} to exit)"
echo ""
exec psql -U "$DOCS_USER" -h "$PG_HOST" -p "$PG_PORT" -d "$DOCS_DB"
