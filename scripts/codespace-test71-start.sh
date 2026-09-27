#!/usr/bin/env bash
set -u
cd /workspaces/redzed-store || exit 1
mkdir -p /tmp/redzed-test71
pkill -f "python3 -m http.server 8000" 2>/dev/null || true
nohup python3 -m http.server 8000 --bind 0.0.0.0 --directory /workspaces/redzed-store >/tmp/redzed-test71/http.log 2>&1 &
if ! pgrep -f "scripts/codespace-test71-auto-sync.sh" >/dev/null 2>&1; then
  nohup bash scripts/codespace-test71-auto-sync.sh >/tmp/redzed-test71/sync.log 2>&1 &
fi
echo "TEST71 preview: port 8000"
