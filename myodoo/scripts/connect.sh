#!/bin/bash
# connect.sh — Open a psql shell to the myodoo (Odoo) database.
# Run INSIDE mypostgresql_db-container.
# Usage:
#   ./connect.sh          → connect as odoo
#   ./connect.sh --admin  → connect as postgres superuser
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$SCRIPT_DIR/.." && pwd)/.env"

if [ "${1:-}" = "--admin" ]; then
    exec psql -U "$PG_SUPERUSER" -h "$PG_HOST" -p "$PG_PORT" -d "$ODOO_DB"
else
    exec psql -U "$ODOO_USER" -h "$PG_HOST" -p "$PG_PORT" -d "$ODOO_DB"
fi
