#!/bin/bash
# health.sh — Check PostgreSQL and db-agent health.
# Run INSIDE mypostgresql_db-container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"

ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
fail() { echo -e "${RED}[FAIL]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
info() { echo -e "${CYAN}[INFO]${RESET}  $*"; }

echo ""
echo "── PostgreSQL ───────────────────────────────────────"

# 1. Server accepting connections
if pg_isready -h localhost -p 5432 -q 2>/dev/null; then
    ok "PostgreSQL is running on localhost:5432"
else
    fail "PostgreSQL is not running — start with: umsdb/scripts/startdb.sh --prepare-only"
fi

# 2. umsdb database exists
if psql -U postgres -h localhost -p 5432 -tc \
    "SELECT 1 FROM pg_database WHERE datname='umsdb'" 2>/dev/null | grep -q 1; then
    ok "Database 'umsdb' exists"
else
    warn "Database 'umsdb' not found — run startdb.sh to initialize"
fi

# 3. ums_user role exists
if psql -U postgres -h localhost -p 5432 -tc \
    "SELECT 1 FROM pg_roles WHERE rolname='ums_user'" 2>/dev/null | grep -q 1; then
    ok "Role 'ums_user' exists"
else
    warn "Role 'ums_user' not found"
fi

echo ""
echo "── DB Agent ─────────────────────────────────────────"

# 4. Python venv + deps
if [ -d ".venv" ] && .venv/bin/python -c "import anthropic, psycopg2" 2>/dev/null; then
    ok "Python dependencies installed"
else
    warn "Dependencies not installed — run ./build.sh"
fi

# 5. agent.conf
if [ -f "agent.conf" ]; then
    source agent.conf
    if [ -n "${ANTHROPIC_API_KEY:-}" ] && [ "$ANTHROPIC_API_KEY" != "your-api-key-here" ]; then
        ok "agent.conf configured"
    else
        warn "agent.conf present but ANTHROPIC_API_KEY not set"
    fi
else
    warn "agent.conf not found — run ./build.sh"
fi

# 6. Agent process running
if pgrep -f "db-agent/agent.py" > /dev/null 2>&1; then
    ok "DB agent process is running"
else
    info "DB agent is not running (start with: ./start.sh)"
fi

echo ""
