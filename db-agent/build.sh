#!/bin/bash
# build.sh — Install Python 3, create venv, and install db-agent dependencies.
# Run INSIDE mypostgresql_db-container.
set -euo pipefail

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
