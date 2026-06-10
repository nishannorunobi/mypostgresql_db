#!/bin/bash
# start.sh — Build the image (if needed) and start the container.
# Run on the HOST from anywhere.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$DOCKERSPACE_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"
PGDATA_DIR="$WORKSPACE_ROOT/mountspace/pgdata"

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

# ── Shared network ────────────────────────────────────────────────────────────
SHARED_NETWORK="ums-network"
if ! docker network inspect "$SHARED_NETWORK" &>/dev/null; then
    echo "Creating shared network $SHARED_NETWORK..."
    docker network create "$SHARED_NETWORK"
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
    mkdir -p "$PGDATA_DIR"
    mkdir -p "$WORKSPACE_ROOT/mountspace/backups"
    mkdir -p "$HOME/.config/rclone"
    docker run -d \
        --name "$CONTAINER_NAME" \
        --hostname "$CONTAINER_NAME" \
        --network "$SHARED_NETWORK" \
        -v "$PROJECT_ROOT":"$CONTAINER_WORKDIR" \
        -v "$PGDATA_DIR":/var/lib/postgresql/data \
        -v "$WORKSPACE_ROOT/mountspace/backups":/backups \
        -v "$HOME/.config/rclone":/root/.config/rclone \
        -p 8085:8085 \
        -p 8890:8890 \
        -p 5572:5572 \
        "$FULL_IMAGE" \
        tail -f /dev/null
fi

# Connect to shared network if not already (handles containers started before this change)
if ! docker network inspect "$SHARED_NETWORK" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -qw "$CONTAINER_NAME"; then
    docker network connect "$SHARED_NETWORK" "$CONTAINER_NAME"
fi

echo "Container is ready."
echo "  Login : bash loginto_docker.sh"
echo "  Ports : bash run_in_host.sh"
