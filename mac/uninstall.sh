#!/bin/bash
# Retire Claude Pulse de Claude Code et remet ta status line d'avant.
set -euo pipefail

DIR="$HOME/.claude/claude-pulse"
SETTINGS="$HOME/.claude/settings.json"
command -v jq >/dev/null || { echo "❌ jq est requis : brew install jq"; exit 1; }

INNER=""
[ -f "$DIR/config" ] && INNER=$( (. "$DIR/config"; printf '%s' "${PULSE_INNER_STATUSLINE:-}") )

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-claude-pulse-$(date +%Y%m%d%H%M%S)"
  TMP=$(mktemp)
  jq --arg hook "$DIR/hook.sh" --arg inner "$INNER" '
    if .hooks then
      .hooks |= (with_entries(.value |= map(select((.hooks // []) | all((.command // "") | contains("/claude-pulse/") | not))))
                 | with_entries(select(.value | length > 0)))
      | if .hooks == {} then del(.hooks) else . end
    else . end
    | if ((.statusLine.command // "") | contains("claude-pulse")) then
        (if $inner != "" then .statusLine = {type: "command", command: $inner} else del(.statusLine) end)
      else . end
  ' "$SETTINGS" > "$TMP"
  mv "$TMP" "$SETTINGS"
fi

rm -rf "$DIR"
echo "✅ Claude Pulse désinstallé."
