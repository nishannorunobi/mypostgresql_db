#!/bin/bash
# db_ui.sh — Install and launch pgweb (lightweight Postgres browser UI).
# Access from your host machine at http://localhost:8085
# Run INSIDE the dev container.
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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/umsdb/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

PGWEB_VERSION="0.16.1"
PGWEB_DIR="/usr/local/bin"
PGWEB_BIN="$PGWEB_DIR/pgweb"
PGWEB_PORT="8085"
PID_FILE="/tmp/pgweb.pid"

# ── Detect architecture ───────────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  PGWEB_ARCH="amd64" ;;
    aarch64) PGWEB_ARCH="arm64" ;;
    armv7l)  PGWEB_ARCH="arm"   ;;
    *)       error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

PGWEB_URL="https://github.com/sosedoff/pgweb/releases/download/v${PGWEB_VERSION}/pgweb_linux_${PGWEB_ARCH}.zip"

# ── Install pgweb ─────────────────────────────────────────────────────────────
install_pgweb() {
    if [ -x "$PGWEB_BIN" ]; then
        success "pgweb already installed: $($PGWEB_BIN --version 2>/dev/null || echo 'v?')"
        return 0
    fi

    info "Installing pgweb v$PGWEB_VERSION ($PGWEB_ARCH)..."

    # ── Ensure curl + unzip are present (postgres:16 is Debian-based) ─────────
    MISSING_PKGS=""
    command -v curl  &>/dev/null || MISSING_PKGS="$MISSING_PKGS curl"
    command -v unzip &>/dev/null || MISSING_PKGS="$MISSING_PKGS unzip"

    if [ -n "$MISSING_PKGS" ]; then
        info "Installing missing tools:$MISSING_PKGS ..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y $MISSING_PKGS -qq
        elif command -v dnf &>/dev/null; then
            dnf install -y $MISSING_PKGS -q
        elif command -v apk &>/dev/null; then
            apk add --no-cache $MISSING_PKGS
        else
            error "Cannot install$MISSING_PKGS — no supported package manager found."
            exit 1
        fi
    fi

    TMP_DIR=$(mktemp -d)
    ZIP="$TMP_DIR/pgweb.zip"

    curl -fsSL "$PGWEB_URL" -o "$ZIP"

    unzip -q "$ZIP" -d "$TMP_DIR"
    BINARY=$(find "$TMP_DIR" -type f -name "pgweb_linux_*" ! -name "*.zip" | head -1)

    if [ -z "$BINARY" ]; then
        error "Could not find pgweb binary in downloaded zip."
        rm -rf "$TMP_DIR"
        exit 1
    fi

    install -m 755 "$BINARY" "$PGWEB_BIN"
    rm -rf "$TMP_DIR"
    success "pgweb installed at $PGWEB_BIN"
}

# ── Modes ─────────────────────────────────────────────────────────────────────
MODE="${1:-}"

case "$MODE" in
    --install-only)
        install_pgweb
        exit 0
        ;;

    stop)
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
                kill "$PID"
                rm -f "$PID_FILE"
                success "pgweb stopped."
            else
                warn "pgweb not running (stale PID file removed)."
                rm -f "$PID_FILE"
            fi
        else
            warn "pgweb is not running."
        fi
        exit 0
        ;;

    ""|start)
        # Fall through to start
        ;;

    --help|-h)
        echo "Usage: $0 [start|stop|--install-only]"
        echo "  start            Install (if needed) and launch pgweb (default)"
        echo "  stop             Stop running pgweb"
        echo "  --install-only   Install pgweb binary without starting"
        exit 0
        ;;
esac

# ── Guard: already running ────────────────────────────────────────────────────
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        warn "pgweb is already running (PID $PID) → http://localhost:$PGWEB_PORT"
        exit 0
    else
        rm -f "$PID_FILE"
    fi
fi

install_pgweb

echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║     UMS DB Browser — pgweb           ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
echo ""

DB_URL="postgres://${PG_SUPERUSER}@${PG_HOST}:${PG_PORT}/postgres?sslmode=disable"

info "Starting pgweb on port $PGWEB_PORT..."
nohup "$PGWEB_BIN" \
    --url "$DB_URL" \
    --bind 0.0.0.0 \
    --listen "$PGWEB_PORT" \
    > /tmp/pgweb.log 2>&1 &

echo $! > "$PID_FILE"
sleep 1

if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    success "pgweb is running!"
    echo ""
    echo -e "  ${BOLD}Open in browser${RESET}  →  http://localhost:$PGWEB_PORT"
    echo -e "  ${BOLD}Database        ${RESET}  →  $UMS_DB  (as $UMS_USER)"
    echo -e "  ${BOLD}Stop            ${RESET}  →  ./scripts/db_ui.sh stop"
    echo -e "  ${BOLD}Logs            ${RESET}  →  tail -f /tmp/pgweb.log"
    echo ""
else
    error "pgweb failed to start. Check: cat /tmp/pgweb.log"
    rm -f "$PID_FILE"
    exit 1
fi
