#!/usr/bin/env bash
set -u
cd /workspaces/redzed-store || exit 1
BRANCH="test71-real-chat-e2e-finalization"
while true; do
  current="$(git branch --show-current 2>/dev/null || true)"
  if [ "$current" = "$BRANCH" ] && [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    git fetch -q origin "$BRANCH" || true
    local_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    remote_sha="$(git rev-parse "origin/$BRANCH" 2>/dev/null || true)"
    if [ -n "$remote_sha" ] && [ "$local_sha" != "$remote_sha" ]; then
      if git merge-base --is-ancestor "$local_sha" "$remote_sha" 2>/dev/null; then
        git merge --ff-only -q "origin/$BRANCH" && echo "[TEST71 auto-sync] $(date '+%H:%M:%S') -> $(git rev-parse --short HEAD)"
      fi
    fi
  fi
  sleep 10
done
