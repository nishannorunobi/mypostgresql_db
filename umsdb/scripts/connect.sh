#!/bin/bash
# connect.sh — Open a psql shell to the UMS database.
# Run INSIDE the dev container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$SCRIPT_DIR/.." && pwd)/.env"

# --admin flag connects as postgres superuser
if [ "${1:-}" = "--admin" ]; then
    exec psql -U "$PG_SUPERUSER" -h "$PG_HOST" -p "$PG_PORT" -d "$UMS_DB"
else
    exec psql -U "$UMS_USER" -h "$PG_HOST" -p "$PG_PORT" -d "$UMS_DB"
fi
