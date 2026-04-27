#!/bin/bash
# startdb.sh — Start PostgreSQL, prepare the UMS database, and open a psql shell.
# Run INSIDE the dev container (postgres:16 base image).
# Flags:
#   --prepare-only   Skip the psql shell (used by reset_db.sh)
set -euo pipefail

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
echo -e "${BOLD}║       UMS DB — START                 ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
echo ""

# ── 1. Start PostgreSQL ───────────────────────────────────────────────────────
PGDATA="${PGDATA:-/var/lib/postgresql/data}"

# Initialize cluster if it has never been set up
if [ ! -f "$PGDATA/PG_VERSION" ]; then
    info "Initializing PostgreSQL cluster at $PGDATA..."
    install -d -m 0700 -o postgres "$PGDATA"
    gosu postgres initdb -D "$PGDATA" --auth=trust
    success "Cluster initialized."
fi

# Ensure trust auth (fixes clusters initialized with md5)
if grep -qE "md5|scram-sha-256" "$PGDATA/pg_hba.conf" 2>/dev/null; then
    info "Patching pg_hba.conf to use trust auth for dev..."
    sed -i -E 's/(host[[:space:]]+all[[:space:]]+all[[:space:]]+[^[:space:]]+[[:space:]]+)(md5|scram-sha-256)/\1trust/' \
        "$PGDATA/pg_hba.conf"
fi

if pg_isready -h "$PG_HOST" -p "$PG_PORT" -q 2>/dev/null; then
    warn "PostgreSQL is already running — skipping start."
else
    info "Starting PostgreSQL..."
    gosu postgres pg_ctl -D "$PGDATA" -l /tmp/postgres.log start -w -t 30 -o "-c listen_addresses='*'"
    pg_isready -h "$PG_HOST" -p "$PG_PORT" -q || {
        error "PostgreSQL did not start in time. Check /tmp/postgres.log"
        exit 1
    }
    success "PostgreSQL is running."
fi

# ── 2. Create application user ────────────────────────────────────────────────
info "Creating user '$UMS_USER'..."
$PSQL_SUPER -v UMS_USER="$UMS_USER" -v UMS_PASSWORD="$UMS_PASSWORD" \
    -f "$INIT_DIR/01_create_user.sql" -q

# ── 3. Create database ────────────────────────────────────────────────────────
info "Checking database '$UMS_DB'..."
DB_EXISTS=$($PSQL_SUPER -tc \
    "SELECT 1 FROM pg_database WHERE datname='$UMS_DB'" | tr -d '[:space:]')

if [ "$DB_EXISTS" = "1" ]; then
    warn "Database '$UMS_DB' already exists — skipping creation."
else
    info "Creating database '$UMS_DB'..."
    $PSQL_SUPER -v UMS_DB="$UMS_DB" -v UMS_USER="$UMS_USER" \
        -f "$INIT_DIR/02_create_database.sql" -q
    success "Database '$UMS_DB' created."
fi

# ── 4. Create tables + grants ─────────────────────────────────────────────────
info "Creating tables and applying grants..."
psql -U "$PG_SUPERUSER" -h "$PG_HOST" -p "$PG_PORT" -d "$UMS_DB" \
    -v UMS_DB="$UMS_DB" -v UMS_USER="$UMS_USER" \
    -f "$INIT_DIR/03_create_tables.sql" -q
success "Tables ready."

# ── 5. Seed data ──────────────────────────────────────────────────────────────
info "Seeding roles and default users..."
psql -U "$PG_SUPERUSER" -h "$PG_HOST" -p "$PG_PORT" -d "$UMS_DB" \
    -f "$INIT_DIR/04_seed_data.sql" -q
success "Seed data applied."

echo ""
success "Database is ready!"
echo ""
echo -e "  ${BOLD}Host     ${RESET}  $PG_HOST:$PG_PORT"
echo -e "  ${BOLD}Database ${RESET}  $UMS_DB"
echo -e "  ${BOLD}User     ${RESET}  $UMS_USER"
echo ""

# ── 7. Open psql shell (unless --prepare-only) ────────────────────────────────
$PREPARE_ONLY && exit 0

info "Connecting to '$UMS_DB' as '$UMS_USER'..."
echo -e "  (run ${BOLD}\\q${RESET} to exit the shell)"
echo ""
exec psql -U "$UMS_USER" -h "$PG_HOST" -p "$PG_PORT" -d "$UMS_DB"
