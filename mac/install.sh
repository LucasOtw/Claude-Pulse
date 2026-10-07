#!/bin/bash
# Installe Claude Pulse dans Claude Code (hooks + status line), pour tous tes projets.
# Usage : ./install.sh [URL_DU_BACKEND] [PULSE_TOKEN]
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/.claude/claude-pulse"
SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null || { echo "❌ jq est requis : brew install jq"; exit 1; }
command -v curl >/dev/null || { echo "❌ curl est requis"; exit 1; }

URL="${1:-}"
TOKEN="${2:-}"
[ -n "$URL" ] || read -rp "URL du backend (ex. https://claude-pulse-xxx.vercel.app) : " URL
[ -n "$TOKEN" ] || { read -rsp "PULSE_TOKEN : " TOKEN; echo; }
URL="${URL%/}"

mkdir -p "$DIR"
cp "$SRC/hook.sh" "$SRC/statusline.sh" "$SRC/tokens.sh" "$SRC/tokens.jq" "$SRC/backfill.sh" "$SRC/approve.sh" "$DIR/"
chmod +x "$DIR/hook.sh" "$DIR/statusline.sh" "$DIR/tokens.sh" "$DIR/backfill.sh" "$DIR/approve.sh"

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
BACKUP="$SETTINGS.bak-claude-pulse-$(date +%Y%m%d%H%M%S)"
cp "$SETTINGS" "$BACKUP"

# Si tu avais déjà une status line, Claude Pulse continue de l'afficher.
INNER=$(jq -r '.statusLine.command // empty' "$SETTINGS")
if [[ "$INNER" == *claude-pulse* ]]; then
  INNER=""
  if [ -f "$DIR/config" ]; then
    INNER=$( (. "$DIR/config"; printf '%s' "${PULSE_INNER_STATUSLINE:-}") )
  fi
fi

# Tes autres réglages (PULSE_SUMMARY, PULSE_REMOTE_APPROVAL…) sont conservés.
EXTRA=""
[ -f "$DIR/config" ] && EXTRA=$(grep -vE '^(PULSE_URL|PULSE_TOKEN|PULSE_INNER_STATUSLINE)=' "$DIR/config" || true)

umask 077
{
  printf 'PULSE_URL=%q\n' "$URL"
  printf 'PULSE_TOKEN=%q\n' "$TOKEN"
  [ -z "$INNER" ] || printf 'PULSE_INNER_STATUSLINE=%q\n' "$INNER"
  [ -z "$EXTRA" ] || printf '%s\n' "$EXTRA"
} > "$DIR/config"
chmod 600 "$DIR/config"

TMP=$(mktemp)
jq --arg hook "$DIR/hook.sh" --arg approve "$DIR/approve.sh" --arg sl "$DIR/statusline.sh" '
  def entry($m): {hooks: [{type: "command", command: $hook, async: true}]}
    | if $m then . + {matcher: $m} else . end;
  def add($ev; $m):
    .hooks[$ev] = (((.hooks[$ev] // []) | map(select((.hooks // []) | all(.command != $hook)))) + [entry($m)]);
  .hooks = (.hooks // {})
  | add("UserPromptSubmit"; null)
  | add("PreToolUse"; "*")
  | add("Notification"; null)
  | add("SubagentStart"; null)
  | add("SubagentStop"; null)
  | add("TaskCreated"; null)
  | add("TaskCompleted"; null)
  | add("Stop"; null)
  | add("StopFailure"; null)
  | add("SessionEnd"; null)
  # Validation à distance : hook synchrone, il peut attendre ta réponse sur le téléphone.
  | .hooks.PermissionRequest = (((.hooks.PermissionRequest // []) | map(select((.hooks // []) | all(.command != $approve))))
      + [{matcher: "*", hooks: [{type: "command", command: $approve, timeout: 600}]}])
  | .statusLine = {type: "command", command: $sl}
' "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"

echo "✅ Installé dans $DIR"
echo "   Sauvegarde de tes réglages : $BACKUP"

code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -H "Authorization: Bearer $TOKEN" "$URL/api/state" || true)
case "$code" in
  200) echo "✅ Backend joignable et jeton accepté." ;;
  401) echo "⚠️  Le backend refuse le jeton : vérifie PULSE_TOKEN dans Vercel." ;;
  *)   echo "⚠️  Backend injoignable (HTTP $code) : vérifie l'URL." ;;
esac
[ "$code" = "200" ] && "$DIR/backfill.sh"
echo "👉 Relance tes sessions Claude Code pour activer les hooks."
