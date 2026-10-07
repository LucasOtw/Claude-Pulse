#!/bin/bash
# Claude Pulse — compte les tokens de sessions Claude Code et les envoie au backend.
# Usage : tokens.sh ~/.claude/projects/<projet>/<session>.jsonl ...
# Inclut les sous-agents de chaque session. Seuls des nombres partent : jamais le contenu.
# Renvoyer une session remplace ses totaux : on peut relancer sans risque de compter double.

CONF="${CLAUDE_PULSE_CONFIG:-$HOME/.claude/claude-pulse/config}"
[ -f "$CONF" ] || exit 0
# shellcheck source=/dev/null
. "$CONF"
[ -n "$PULSE_URL" ] && [ -n "$PULSE_TOKEN" ] || exit 0
command -v jq >/dev/null || exit 0
DIR="$(cd "$(dirname "$0")" && pwd)"

batch=()
sent=0
flush() {
  [ ${#batch[@]} -gt 0 ] || return 0
  printf '%s\n' "${batch[@]}" | jq -cs '{sessions: .}' | curl -sS -m 30 -X POST "$PULSE_URL/api/tokens" \
    -H "Authorization: Bearer $PULSE_TOKEN" -H "Content-Type: application/json" \
    --data-binary @- >/dev/null 2>&1
  sent=$((sent + ${#batch[@]}))
  batch=()
}

for f in "$@"; do
  [ -f "$f" ] || continue
  sid=$(basename "$f" .jsonl)
  files=("$f")
  sub="${f%.jsonl}/subagents"
  if [ -d "$sub" ]; then
    for s in "$sub"/*.jsonl; do [ -f "$s" ] && files+=("$s"); done
  fi
  days=$(cat "${files[@]}" 2>/dev/null | jq -nRc -f "$DIR/tokens.jq" 2>/dev/null) || continue
  [ -n "$days" ] && [ "$days" != "{}" ] || continue
  project=$(jq -nRr '[inputs | fromjson? | .cwd? // empty | select(type == "string")] | first // "" | split("/") | last' "$f" 2>/dev/null)
  batch+=("$(jq -cn --arg sid "$sid" --arg project "$project" --argjson days "$days" '{sid: $sid, project: (if $project == "" then null else $project end), days: $days}')")
  [ ${#batch[@]} -ge 40 ] && flush
done
flush
[ -n "$PULSE_VERBOSE" ] && echo "$sent"
exit 0
