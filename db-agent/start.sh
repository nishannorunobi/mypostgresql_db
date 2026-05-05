#!/bin/bash
# start.sh — Start the DB Agent HTTP server inside mypostgresql_db-container.
# Run INSIDE the container. Starts uvicorn on PORT (default 8890).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BOLD="\033[1m"; RESET="\033[0m"

[ -d ".venv" ]      || { echo -e "${RED}[ERROR]${RESET} .venv not found. Run ./build.sh first."; exit 1; }
[ -f "agent.conf" ] || { echo -e "${RED}[ERROR]${RESET} agent.conf not found. Run ./build.sh first."; exit 1; }

source agent.conf
[ -n "${ANTHROPIC_API_KEY:-}" ] || { echo -e "${RED}[ERROR]${RESET} ANTHROPIC_API_KEY not set in agent.conf"; exit 1; }

PORT="${PORT:-8890}"
LOG_FILE="memory/server.log"
mkdir -p memory

# Warn if PostgreSQL is not running (agent still starts — DB may come up later)
if ! pg_isready -h localhost -p 5432 -q 2>/dev/null; then
    echo -e "${YELLOW}[WARN]${RESET}  PostgreSQL is not running — agent will start it on request."
fi

echo -e "\n${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   DB Agent                               ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo -e "  ${GREEN}API:${RESET}  http://localhost:${PORT}"
echo -e "  ${GREEN}Log:${RESET}  ${LOG_FILE}"
echo -e "  Press Ctrl+C to stop.\n"

.venv/bin/uvicorn server:app \
    --host 0.0.0.0 \
    --port "$PORT" \
    --log-level info \
    --access-log \
    --no-use-colors \
    2>&1 | awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' | tee -a "$LOG_FILE"
