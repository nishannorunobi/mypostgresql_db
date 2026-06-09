#!/bin/bash
# clean.sh — Remove build artifacts so build.sh recreates a fresh environment.
# Run INSIDE mypostgresql_db-container.
# Removes : .venv, __pycache__, *.pyc
# Preserves: agent.conf, memory/ (runtime data)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"; YELLOW="\033[33m"; RESET="\033[0m"
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
info() { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

echo -e "\n${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   DB Agent — Clean                       ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}\n"

# Stop agent if running
if pkill -f "[u]vicorn server:app" 2>/dev/null; then
    ok "Stopped db-agent (uvicorn)"
fi

# Virtual environment
if [ -d ".venv" ]; then
    rm -rf .venv
    ok "Removed .venv"
else
    info ".venv not present — nothing to remove"
fi

# Python caches
find . -path ./.venv -prune -o -type d -name "__pycache__" -print | xargs rm -rf 2>/dev/null || true
find . -path ./.venv -prune -o -name "*.pyc"               -print -delete 2>/dev/null || true
ok "Removed __pycache__ and *.pyc"

echo ""
warn "Preserved: agent.conf, memory/ (delete manually to reset)"
echo -e "\n${GREEN}Clean complete.${RESET} Run ${BOLD}./build.sh${RESET} to rebuild.\n"
