#!/bin/bash
# build.sh — Install Python 3, create venv, and install db-agent dependencies.
# Run INSIDE mypostgresql_db-container.
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

RED="\033[31m"; GREEN="\033[32m"; CYAN="\033[36m"; RESET="\033[0m"

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ── Install Python 3 if missing ───────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    info "Installing Python 3..."
    apt-get update -qq && apt-get install -y python3 python3-pip python3-venv
    success "Python 3 installed."
else
    success "Python 3 found: $(python3 --version)"
fi

# ── Create virtual environment ────────────────────────────────────────────────
if [ ! -d ".venv" ]; then
    info "Creating virtual environment..."
    python3 -m venv .venv
    success "venv created."
fi

# ── Install dependencies ──────────────────────────────────────────────────────
info "Installing dependencies..."
.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet -r requirements.txt
success "Dependencies installed."

# ── Install rclone if missing ─────────────────────────────────────────────────
if ! command -v rclone &>/dev/null; then
    info "Installing rclone..."
    # curl downloads the installer; unzip is needed to extract the rclone archive.
    apt-get update -qq
    apt-get install -y -qq curl unzip
    curl -fsSL https://rclone.org/install.sh | bash
    success "rclone installed: $(rclone --version | head -1)"
else
    success "rclone found: $(rclone --version | head -1)"
fi

# ── Create agent.conf if missing ──────────────────────────────────────────────
if [ ! -f "agent.conf" ]; then
    cp agent.conf.example agent.conf
    echo ""
    echo -e "${RED}[ACTION REQUIRED]${RESET} Edit agent.conf and set your ANTHROPIC_API_KEY"
    echo "  nano agent.conf"
else
    success "agent.conf exists."
fi

# ── Create memory directory ───────────────────────────────────────────────────
mkdir -p memory
success "memory/ directory ready."

echo ""
success "Build complete. Start the agent with: ./start.sh"
