#!/bin/bash
# connect.sh — Open a psql shell to the mydocsdb database.
# Run INSIDE mypostgresql_db-container.
# Usage:
#   ./connect.sh          → connect as docs_user
#   ./connect.sh --admin  → connect as postgres superuser
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$SCRIPT_DIR/.." && pwd)/.env"

if [ "${1:-}" = "--admin" ]; then
    exec psql -U "$PG_SUPERUSER" -h "$PG_HOST" -p "$PG_PORT" -d "$DOCS_DB"
else
    exec psql -U "$DOCS_USER" -h "$PG_HOST" -p "$PG_PORT" -d "$DOCS_DB"
fi
