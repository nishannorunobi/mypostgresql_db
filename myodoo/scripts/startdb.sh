#!/bin/bash
# startdb.sh — Prepare the Odoo (myodoo) role + database, then open a psql shell.
# Run INSIDE mypostgresql_db-container.
# Flags:
#   --prepare-only   Skip the psql shell (used by reset_db.sh)
#   --role-only      Create ONLY the odoo role (let Odoo's web wizard create the DB)
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
ROLE_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --prepare-only) PREPARE_ONLY=true ;;
        --role-only)    ROLE_ONLY=true ;;
    esac
done

PSQL_SUPER="psql -U $PG_SUPERUSER -h $PG_HOST -p $PG_PORT"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       MYODOO DB — START              ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
echo ""

# ── 1. Verify PostgreSQL is running ──────────────────────────────────────────
if ! pg_isready -h "$PG_HOST" -p "$PG_PORT" -q 2>/dev/null; then
    error "PostgreSQL is not running. Start it first via the container entrypoint."
    exit 1
fi
success "PostgreSQL is running."

# ── 2. Create Odoo role (with CREATEDB) ──────────────────────────────────────
info "Creating role '$ODOO_USER' (with CREATEDB)..."
$PSQL_SUPER -v ODOO_USER="$ODOO_USER" -v ODOO_PASSWORD="$ODOO_PASSWORD" \
    -f "$INIT_DIR/01_create_user.sql" -q
success "Role '$ODOO_USER' ready."

if $ROLE_ONLY; then
    echo ""
    success "Role-only mode: skipping database creation."
    echo -e "  Create the database from Odoo's web UI at http://localhost:8069"
    echo -e "  (name it ${BOLD}$ODOO_DB${RESET} to match the dbfilter)."
    exit 0
fi

# ── 3. Create database ────────────────────────────────────────────────────────
info "Checking database '$ODOO_DB'..."
DB_EXISTS=$($PSQL_SUPER -tc \
    "SELECT 1 FROM pg_database WHERE datname='$ODOO_DB'" | tr -d '[:space:]')

if [ "$DB_EXISTS" = "1" ]; then
    warn "Database '$ODOO_DB' already exists — skipping creation."
else
    info "Creating database '$ODOO_DB'..."
    $PSQL_SUPER -v ODOO_DB="$ODOO_DB" -v ODOO_USER="$ODOO_USER" \
        -f "$INIT_DIR/02_create_database.sql" -q
    success "Database '$ODOO_DB' created."
fi

# ── 4. Apply extensions and grants ───────────────────────────────────────────
info "Applying extensions and grants..."
psql -U "$PG_SUPERUSER" -h "$PG_HOST" -p "$PG_PORT" -d "$ODOO_DB" \
    -v ODOO_DB="$ODOO_DB" -v ODOO_USER="$ODOO_USER" \
    -f "$INIT_DIR/03_grants.sql" -q
success "Grants applied."

echo ""
success "Database is ready!"
echo ""
echo -e "  ${BOLD}Host     ${RESET}  $PG_HOST:$PG_PORT"
echo -e "  ${BOLD}Database ${RESET}  $ODOO_DB"
echo -e "  ${BOLD}User     ${RESET}  $ODOO_USER"
echo ""
echo -e "  The DB is empty. Initialize Odoo's schema by starting the Odoo container"
echo -e "  with: ${BOLD}odoo -d $ODOO_DB -i base --stop-after-init${RESET}"
echo -e "  (or use the web wizard instead — then run this script with --role-only)."
echo ""

$PREPARE_ONLY && exit 0

info "Connecting to '$ODOO_DB' as '$ODOO_USER'..."
echo -e "  (run ${BOLD}\\q${RESET} to exit)"
echo ""
exec psql -U "$ODOO_USER" -h "$PG_HOST" -p "$PG_PORT" -d "$ODOO_DB"
