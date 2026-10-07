#!/bin/bash
# Claude Pulse — status line Claude Code.
# Affiche une ligne d'état et envoie (au plus toutes les PULSE_USAGE_EVERY secondes)
# le coût, le contexte et les limites d'abonnement 5 h / 7 jours au backend.

CONF="${CLAUDE_PULSE_CONFIG:-$HOME/.claude/claude-pulse/config}"
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"

input=$(cat)

# 1. Envoi de l'usage, en arrière-plan pour ne jamais ralentir l'affichage.
if [ -n "$PULSE_URL" ] && [ -n "$PULSE_TOKEN" ] && command -v jq >/dev/null; then
  sid=$(printf '%s' "$input" | jq -r '.session_id // "x"' | tr -cd 'A-Za-z0-9_-')
  stamp="${TMPDIR:-/tmp}/claude-pulse-usage-$sid"
  now=$(date +%s)
  last=$(cat "$stamp" 2>/dev/null || echo 0)
  if [ $((now - last)) -ge "${PULSE_USAGE_EVERY:-60}" ]; then
    echo "$now" > "$stamp"
    payload=$(printf '%s' "$input" | jq -c '
      def win: if . then {pct: .used_percentage, resetsAt: .resets_at} else null end;
      {
        sid: .session_id,
        project: ((.workspace.project_dir // .cwd // "") | split("/") | last),
        title: (.session_name // null),
        model: (.model.display_name // null),
        costUsd: (.cost.total_cost_usd // 0),
        contextPct: (.context_window.used_percentage // 0),
        fiveHour: (.rate_limits.five_hour | win),
        sevenDay: (.rate_limits.seven_day | win)
      }' 2>/dev/null)
    if [ -n "$payload" ]; then
      ( curl -sS -m 8 -X POST "$PULSE_URL/api/usage" \
          -H "Authorization: Bearer $PULSE_TOKEN" \
          -H "Content-Type: application/json" \
          --data-binary "$payload" >/dev/null 2>&1 & )
    fi
  fi
fi

# 2. Affichage : ta status line d'avant si tu en avais une, sinon une ligne simple.
if [ -n "$PULSE_INNER_STATUSLINE" ]; then
  printf '%s' "$input" | bash -c "$PULSE_INNER_STATUSLINE"
elif command -v jq >/dev/null; then
  printf '%s' "$input" | jq -r '
    [ "[\(.model.display_name // "Claude")]",
      "ctx \((.context_window.used_percentage // 0) | floor)%",
      (if .rate_limits.five_hour then "5h \(.rate_limits.five_hour.used_percentage | floor)%" else empty end),
      (if .rate_limits.seven_day then "7j \(.rate_limits.seven_day.used_percentage | floor)%" else empty end),
      "$\((.cost.total_cost_usd // 0) * 100 | floor / 100)"
    ] | join(" · ")'
fi
