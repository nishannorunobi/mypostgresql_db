#!/bin/bash
# start.sh — Start the DB Agent HTTP server inside mypostgresql_db-container.
# Run INSIDE the container. Starts uvicorn on PORT (default 8890).
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
cd "$SCRIPT_DIR"

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BOLD="\033[1m"; RESET="\033[0m"

# Self-bootstrap: if the environment was cleaned (venv missing/incomplete), build it;
# otherwise reuse the existing venv.
if [ ! -d ".venv" ] || ! .venv/bin/python3 -c 'import anthropic' 2>/dev/null; then
    echo -e "${YELLOW}[INFO]${RESET}  venv missing/incomplete — running build.sh..."
    bash build.sh
fi

# Ensure agent.conf, and inject ANTHROPIC_API_KEY from the container env if provided.
[ -f agent.conf ] || cp agent.conf.example agent.conf 2>/dev/null || true
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    if grep -q '^ANTHROPIC_API_KEY=' agent.conf 2>/dev/null; then
        sed -i "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}|" agent.conf
    else
        echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}" >> agent.conf
    fi
fi
source agent.conf 2>/dev/null || true
# Missing key only disables chat/LLM — never block startup.
[ -n "${ANTHROPIC_API_KEY:-}" ] || echo -e "${YELLOW}[WARN]${RESET}  ANTHROPIC_API_KEY not set — chat/LLM disabled, agent still starts."

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
