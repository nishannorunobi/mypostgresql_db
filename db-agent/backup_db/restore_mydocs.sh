#!/bin/bash
# restore_mydocs.sh — Restore mydocsdb from a gzipped SQL backup.
# Run INSIDE mypostgresql_db-container.
# Usage: bash restore_mydocs.sh <backup_file.sql.gz>
set -euo pipefail

BACKUP_FILE="${1:-}"
if [ -z "$BACKUP_FILE" ]; then
    echo "[ERROR] Usage: bash restore_mydocs.sh <backup_file.sql.gz>"
    exit 1
fi
if [ ! -f "$BACKUP_FILE" ]; then
    echo "[ERROR] File not found: $BACKUP_FILE"
    exit 1
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../mydocsdb/.env"

echo "[INFO] Restoring $DOCS_DB from $BACKUP_FILE..."
gunzip -c "$BACKUP_FILE" | psql -U "$DOCS_USER" -h "$PG_HOST" -p "$PG_PORT" "$DOCS_DB"
echo "[OK]  Restore complete."
