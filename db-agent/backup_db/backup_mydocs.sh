#!/bin/bash
# backup_mydocs.sh — Dump mydocsdb to a timestamped gzipped SQL file.
# Run INSIDE mypostgresql_db-container.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../mydocsdb/.env"

BACKUP_DIR="/backups/mydocs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/mydocsdb_$TIMESTAMP.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[INFO] Backing up $DOCS_DB..."
pg_dump -U "$DOCS_USER" -h "$PG_HOST" -p "$PG_PORT" "$DOCS_DB" | gzip > "$BACKUP_FILE"
echo "[OK]  Saved to $BACKUP_FILE"
