#!/bin/bash
# clean.sh — Remove build artifacts so build.sh recreates a fresh environment.
# Run INSIDE mypostgresql_db-container.
# Removes : .venv, __pycache__, *.pyc
# Preserves: agent.conf, memory/ (runtime data)
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
