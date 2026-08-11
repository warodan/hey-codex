#!/usr/bin/env sh
# Daily update check for Codex CLI. Called at the start of the `codex` skill.
# Skips instantly if checked less than 24h ago; otherwise compares the installed
# version with npm and runs `codex update` when behind.
# Output is one ASCII line (Windows consoles mangle non-ASCII in piped stdout).

STAMP="$HOME/.codex/.claude-skill-update-check"
TTL=86400

if ! command -v codex >/dev/null 2>&1; then
  echo "update-check: codex not found in PATH - install it with 'npm install -g @openai/codex'" >&2
  exit 0
fi

NOW=$(date +%s)
LAST=0
[ -f "$STAMP" ] && LAST=$(cat "$STAMP" 2>/dev/null | tr -dc '0-9')
[ -z "$LAST" ] && LAST=0
AGE=$((NOW - LAST))

if [ "$AGE" -lt "$TTL" ]; then
  echo "update-check: skipped (last check ${AGE}s ago, ttl ${TTL}s)"
  exit 0
fi

CUR=$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
LATEST=$(npm view @openai/codex version 2>/dev/null | tr -d '\r')

# Stamp regardless of outcome: at most one attempt per day, even if npm is down.
mkdir -p "$(dirname "$STAMP")" 2>/dev/null
echo "$NOW" > "$STAMP"

if [ -z "$LATEST" ]; then
  echo "update-check: npm unreachable, staying on ${CUR:-unknown}"
  exit 0
fi

if [ "$CUR" = "$LATEST" ]; then
  echo "update-check: up to date ($CUR)"
  exit 0
fi

echo "update-check: $CUR -> $LATEST, updating now"
codex update >/dev/null 2>&1
NEW=$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

if [ "$NEW" = "$LATEST" ]; then
  echo "update-check: updated to $NEW"
else
  echo "update-check: update FAILED, still on ${NEW:-unknown} (latest $LATEST) - run 'codex update' manually" >&2
fi
