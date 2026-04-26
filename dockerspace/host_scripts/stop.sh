#!/bin/bash
# stop.sh — Stop (and optionally remove) the container and image.
# Run on the HOST from anywhere.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$DOCKERSPACE_DIR/project.conf"

FULL_IMAGE="$IMAGE_NAME:$IMAGE_VERSION"

# ── Stop container ────────────────────────────────────────────────────────────
if docker container inspect "$CONTAINER_NAME" &>/dev/null; then
    echo "Stopping container $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME"
    docker rm   "$CONTAINER_NAME"
    echo "Container removed."
else
    echo "Container $CONTAINER_NAME is not running."
fi

# ── Remove image ──────────────────────────────────────────────────────────────
if [ "${REMOVE_IMAGE_ON_STOP}" = true ]; then
    if docker image inspect "$FULL_IMAGE" &>/dev/null; then
        echo "Removing image $FULL_IMAGE..."
        docker rmi "$FULL_IMAGE"
        echo "Image removed."
    fi
fi
