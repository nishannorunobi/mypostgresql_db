#!/bin/bash
# loginto_docker.sh — Open a shell inside the running container.
# Run on the HOST.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/run_in_host.conf"

if ! docker container inspect "$CONTAINER_NAME" &>/dev/null; then
    echo "Container '$CONTAINER_NAME' is not running."
    exit 1
fi

docker exec -it "$CONTAINER_NAME" bash
