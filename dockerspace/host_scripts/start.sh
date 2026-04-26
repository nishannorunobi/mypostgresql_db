#!/bin/bash
# start.sh — Build the image (if needed) and start the container.
# Run on the HOST from anywhere.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$DOCKERSPACE_DIR/.." && pwd)"

source "$DOCKERSPACE_DIR/project.conf"

FULL_IMAGE="$IMAGE_NAME:$IMAGE_VERSION"

# ── Build image ───────────────────────────────────────────────────────────────
if docker image inspect "$FULL_IMAGE" &>/dev/null; then
    echo "Image $FULL_IMAGE already exists — skipping build."
else
    echo "Building image $FULL_IMAGE..."
    docker build \
        --build-arg BASE_IMAGE=postgres:16 \
        --build-arg CONTAINER_WORKDIR="$CONTAINER_WORKDIR" \
        -t "$FULL_IMAGE" "$DOCKERSPACE_DIR"
fi

# ── Start container ───────────────────────────────────────────────────────────
if [ "${FORCE_RECREATE_CONTAINER}" = true ]; then
    echo "Force recreate: removing existing container $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm   "$CONTAINER_NAME" 2>/dev/null || true
fi

if docker container inspect "$CONTAINER_NAME" &>/dev/null; then
    echo "Container $CONTAINER_NAME already exists — starting it..."
    docker start "$CONTAINER_NAME"
else
    echo "Creating container $CONTAINER_NAME..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --hostname "$CONTAINER_NAME" \
        -v "$PROJECT_ROOT":"$CONTAINER_WORKDIR" \
        "$FULL_IMAGE" \
        tail -f /dev/null
fi

echo "Container is ready."
echo "  Login : bash loginto_docker.sh"
echo "  Ports : bash run_in_host.sh"
