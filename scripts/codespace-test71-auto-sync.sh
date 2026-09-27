#!/usr/bin/env bash
set -u
cd /workspaces/redzed-store || exit 1
BRANCH="test71-real-chat-e2e-finalization"
HEAD_FILE=".codespace-test71-head"

write_head() {
  local sha
  sha="$(git rev-parse --short=8 HEAD 2>/dev/null || true)"
  [ -n "$sha" ] && printf "%s" "$sha" > "$HEAD_FILE"
}

write_head
while true; do
  current="$(git branch --show-current 2>/dev/null || true)"
  dirty="$(git status --porcelain --untracked-files=all 2>/dev/null | grep -vE '^[?][?] \.codespace-test71-head$' || true)"

  if [ "$current" = "$BRANCH" ] && [ -z "$dirty" ]; then
    if git fetch -q origin "$BRANCH"; then
      local_sha="$(git rev-parse HEAD 2>/dev/null || true)"
      remote_sha="$(git rev-parse "origin/$BRANCH" 2>/dev/null || true)"
      if [ -n "$remote_sha" ] && [ "$local_sha" != "$remote_sha" ]; then
        if git merge-base --is-ancestor "$local_sha" "$remote_sha" 2>/dev/null; then
          if git merge --ff-only -q "origin/$BRANCH"; then
            write_head
            echo "[TEST71 auto-sync] $(date '+%H:%M:%S') -> $(git rev-parse --short=8 HEAD)"
          fi
        else
          echo "[TEST71 auto-sync] local HEAD diverged; safe skip"
        fi
      fi
    fi
  elif [ "$current" != "$BRANCH" ]; then
    echo "[TEST71 auto-sync] branch is $current; waiting for $BRANCH"
  elif [ -n "$dirty" ]; then
    echo "[TEST71 auto-sync] local changes present; safe skip"
  fi

  write_head
  sleep 10
done
