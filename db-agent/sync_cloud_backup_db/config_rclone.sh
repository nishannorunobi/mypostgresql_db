#!/bin/bash
# config_rclone.sh — Install rclone and configure Google Drive remote.
# Run on the HOST.
set -euo pipefail

REMOTE_NAME="gdrive"

# ── Install rclone if missing ─────────────────────────────────────────────────
if ! command -v rclone &>/dev/null; then
    echo "[INFO] Installing rclone..."
    curl https://rclone.org/install.sh | sudo bash
    echo "[OK]  rclone installed: $(rclone --version | head -1)"
else
    echo "[OK]  rclone already installed: $(rclone --version | head -1)"
fi

# ── Configure Google Drive remote ─────────────────────────────────────────────
if rclone listremotes | grep -q "^${REMOTE_NAME}:"; then
    echo "[OK]  Remote '${REMOTE_NAME}' already configured."
    echo "      To reconfigure: rclone config"
else
    echo ""
    echo "[INFO] Configuring Google Drive remote '${REMOTE_NAME}'..."
    echo "       Follow the prompts:"
    echo "         - Choose 'n' (new remote)"
    echo "         - Name: ${REMOTE_NAME}"
    echo "         - Storage type: drive (Google Drive)"
    echo "         - Leave client_id and client_secret blank (use defaults)"
    echo "         - Scope: 1 (full access)"
    echo "         - Auto config: y (opens browser for OAuth)"
    echo ""
    rclone config
fi

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
if rclone listremotes | grep -q "^${REMOTE_NAME}:"; then
    echo "[OK]  Remote '${REMOTE_NAME}' is ready."
    echo "      Test with: rclone lsd ${REMOTE_NAME}:"
else
    echo "[WARN] Remote '${REMOTE_NAME}' not found. Run 'rclone config' manually."
fi
