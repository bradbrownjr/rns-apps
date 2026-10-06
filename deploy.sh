#!/bin/bash
# Deploy rns-apps to a Docker host (built for Unraid).
#
#   RNS_APPS_HOST=root@your-unraid ./deploy.sh          # sync pages/lib/apps.json
#   RNS_APPS_HOST=root@your-unraid ./deploy.sh --build  # also build a local image
#
# The published image is ghcr.io/bradbrownjr/rns-apps (built by GitHub
# Actions). --build is only for testing docker/ changes before pushing.
#
# App code is bind-mounted read-only into the container, so a page change is
# live on the next request. New page files are picked up within
# PAGE_REFRESH_INTERVAL minutes (default 5).
set -euo pipefail

HOST="${RNS_APPS_HOST:?set RNS_APPS_HOST, e.g. root@your-unraid}"
DEST="${RNS_APPS_DEST:-/mnt/user/appdata/rns-apps/app}"
IMAGE="${RNS_APPS_IMAGE:-rns-apps:local}"

cd "$(dirname "$0")"

for f in pages/*.mu lib/*.py tools/*.py docker/entrypoint.py; do
    python3 -m py_compile "$f"
done
python3 -c "import json; json.load(open('apps.json'))"
find . -name __pycache__ -prune -exec rm -rf {} +

ssh "$HOST" "mkdir -p '$DEST' && find '$DEST' -mindepth 1 -delete"
tar -czf - pages lib tools data apps.json feeds.json docker | ssh "$HOST" "tar -xzf - -C '$DEST'"
echo "Synced to $HOST:$DEST"

if [[ "${1:-}" == "--build" ]]; then
    ssh "$HOST" "docker build -t '$IMAGE' '$DEST/docker'"
    echo "Built $IMAGE - point a test container at it; the Unraid template uses GHCR."
fi
