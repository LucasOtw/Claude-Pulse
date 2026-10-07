#!/bin/bash
# Claude Pulse — validation à distance (hook PermissionRequest, synchrone).
# Quand Claude Code s'apprête à te demander une autorisation :
#  - si la validation à distance est éteinte sur l'iPhone, on rend la main tout de suite
#    et le terminal pose sa question comme d'habitude ;
#  - sinon la demande s'affiche sur l'iPhone (app et Live Activity) et on attend ta réponse
#    au plus PULSE_APPROVAL_WAIT secondes, puis le terminal reprend la main.
# Seuls l'outil et l'essentiel de la demande partent (commande, fichier ou URL), jamais un contenu.
# Désactiver complètement : PULSE_REMOTE_APPROVAL=0 dans ~/.claude/claude-pulse/config.

CONF="${CLAUDE_PULSE_CONFIG:-$HOME/.claude/claude-pulse/config}"
[ -f "$CONF" ] || exit 0
# shellcheck source=/dev/null
. "$CONF"
[ "${PULSE_REMOTE_APPROVAL:-1}" = "1" ] || exit 0
[ -n "$PULSE_URL" ] && [ -n "$PULSE_TOKEN" ] || exit 0
command -v jq >/dev/null || exit 0

input=$(cat)
request=$(printf '%s' "$input" | jq -c '{
  sid: .session_id,
  project: (.cwd // "" | split("/") | last),
  tool: .tool_name,
  input: ((.tool_input // {}) | {command, description, file_path, notebook_path, url} | with_entries(select(.value != null)))
}' 2>/dev/null) || exit 0

api() { curl -sS -m "$1" -H "Authorization: Bearer $PULSE_TOKEN" -H "Content-Type: application/json" "${@:2}" 2>/dev/null; }

reply=$(api 4 -X POST "$PULSE_URL/api/approval" --data-binary "$request") || exit 0
[ "$(printf '%s' "$reply" | jq -r '.remote // false' 2>/dev/null)" = "true" ] || exit 0
id=$(printf '%s' "$reply" | jq -r '.id // empty' 2>/dev/null)
[ -n "$id" ] || exit 0

deadline=$(( $(date +%s) + ${PULSE_APPROVAL_WAIT:-180} ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  sleep 2
  decision=$(api 5 "$PULSE_URL/api/approval?id=$id" | jq -r '.decision // empty' 2>/dev/null)
  case "$decision" in
    allow)
      echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
      exit 0
      ;;
    deny)
      echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Refusé depuis l’iPhone (Claude Pulse)."}}}'
      exit 0
      ;;
    expired) exit 0 ;;
  esac
done

# Pas de réponse : la demande disparaît du téléphone et le terminal reprend la main.
api 4 -X POST "$PULSE_URL/api/approval" --data-binary "{\"cancel\":\"$id\"}" >/dev/null
exit 0
