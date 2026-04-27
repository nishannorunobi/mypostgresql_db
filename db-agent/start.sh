#!/bin/bash
# start.sh — Start the PostgreSQL DB Agent inside the container.
# Usage:
#   ./start.sh                          # interactive chat
#   ./start.sh "check connections"      # one-shot
# Run INSIDE mypostgresql_db-container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED="\033[31m"; YELLOW="\033[33m"; RESET="\033[0m"

[ -d ".venv" ]      || { echo -e "${RED}[ERROR]${RESET} .venv not found. Run ./build.sh first."; exit 1; }
[ -f "agent.conf" ] || { echo -e "${RED}[ERROR]${RESET} agent.conf not found. Run ./build.sh first."; exit 1; }

source agent.conf
[ -n "${ANTHROPIC_API_KEY:-}" ] || { echo -e "${RED}[ERROR]${RESET} ANTHROPIC_API_KEY not set in agent.conf"; exit 1; }

# Warn if PostgreSQL is not running (agent still starts — DB may come up later)
if ! pg_isready -h localhost -p 5432 -q 2>/dev/null; then
    echo -e "${YELLOW}[WARN]${RESET}  PostgreSQL is not running."
    echo -e "         Start it first: cd /mypostgresql_db && ./umsdb/scripts/startdb.sh --prepare-only"
    echo ""
fi

if [ $# -gt 0 ]; then
    .venv/bin/python agent.py "$@"
else
    .venv/bin/python agent.py
fi
