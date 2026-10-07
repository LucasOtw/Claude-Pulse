#!/bin/bash
# Claude Pulse — hook Claude Code.
# Reçoit l'événement JSON sur stdin, n'en garde que les métadonnées utiles
# (jamais le texte de tes prompts ni le contenu des fichiers) et l'envoie au backend.
# Lancé en "async": il ne ralentit jamais Claude, et il échoue toujours en silence.

CONF="${CLAUDE_PULSE_CONFIG:-$HOME/.claude/claude-pulse/config}"
[ -f "$CONF" ] || exit 0
# shellcheck source=/dev/null
. "$CONF"
[ -n "$PULSE_URL" ] && [ -n "$PULSE_TOKEN" ] || exit 0
command -v jq >/dev/null || exit 0

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
[ -n "$event" ] || exit 0

# PreToolUse arrive à chaque outil. Pour ménager le quota gratuit, on envoie :
#  - toujours les outils qui changent la progression (TodoWrite, Agent, Workflow) ;
#  - dès que Claude change d'outil (au plus toutes les 5 s) ;
#  - sinon un battement toutes les PULSE_HEARTBEAT secondes.
if [ "$event" = "PreToolUse" ]; then
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
  case "$tool" in
    TodoWrite|Workflow|Agent|Task) ;;
    *)
      sid=$(printf '%s' "$input" | jq -r '.session_id // "x"' | tr -cd 'A-Za-z0-9_-')
      stamp="${TMPDIR:-/tmp}/claude-pulse-hb-$sid"
      now=$(date +%s)
      { read -r last last_tool < "$stamp"; } 2>/dev/null || { last=0; last_tool=""; }
      elapsed=$((now - ${last:-0}))
      if [ "$elapsed" -lt "${PULSE_HEARTBEAT:-30}" ]; then
        [ "$tool" != "$last_tool" ] && [ "$elapsed" -ge 5 ] || exit 0
      fi
      echo "$now $tool" > "$stamp"
      ;;
  esac
fi

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
transcript="${transcript/#\~/$HOME}"

# Fin de tour : ce que Claude a fait (fichiers modifiés, commandes, sous-agents), pour la notification.
recap=null
if [ "$event" = "Stop" ] && [ -f "$transcript" ]; then
  recap=$(tail -n 4000 "$transcript" | jq -R -n -c -f "$(dirname "$0")/turn.jq" 2>/dev/null) || recap=null
  [ -n "$recap" ] || recap=null
fi

payload=$(printf '%s' "$input" | jq -c --arg summary_on "${PULSE_SUMMARY:-0}" --argjson recap "$recap" '
  def cut($n): if type == "string" then .[0:$n] else . end;
  def workflow:
    (.tool_input.script // "" | .[0:4000]) as $head
    | {
        name: ((.tool_input.name // ($head | capture("name:\\s*[\"'"'"'`](?<n>[^\"'"'"'`]+)") | .n)) // "workflow"),
        phases: ([$head | scan("title:\\s*[\"'"'"'`]([^\"'"'"'`]+)") | .[0]] | .[0:8])
      };
  {
    v: 1,
    e: .hook_event_name,
    sid: .session_id,
    project: (.cwd // "" | split("/") | last),
    title: (.session_title // null | cut(60)),
    tool: (.tool_name // null),
    # Précision affichée sur le téléphone : nom du fichier (pas son chemin), description courte
    # que Claude donne à sa commande ou à son sous-agent, domaine de la page web lue.
    detail: (
      if (.tool_name | IN("Edit", "MultiEdit", "Write", "Read", "NotebookEdit"))
        then ((.tool_input.file_path // .tool_input.notebook_path // "") | split("/") | last)
      elif (.tool_name | IN("Bash", "Agent", "Task")) then .tool_input.description
      elif .tool_name == "WebFetch"
        then ([(.tool_input.url // "") | capture("^[a-z]+://(?<h>[^/]+)") | .h] | first)
      elif .tool_name == "Skill" then (.tool_input.skill // .tool_input.name)
      else null end
      | if type == "string" and length > 0 then .[0:80] else null end
    ),
    agentId: (.agent_id // null),
    agentType: (.agent_type // null),
    ntype: (.notification_type // null),
    message: (.message // null | cut(120)),
    taskId: (.task_id // null),
    taskSubject: (.task_subject // null | cut(80)),
    todos: (if .tool_name == "TodoWrite"
            then [.tool_input.todos[]? | {c: ((.activeForm // .content // "") | cut(80)), s: .status}]
            else null end),
    workflow: (if .tool_name == "Workflow" then workflow else null end),
    bg: (if .background_tasks then [.background_tasks[] | {type, status, name: ((.name // .description // "") | cut(60))}] else null end),
    error: (.error // .error_type // .reason // null | if type == "string" then .[0:60] else null end),
    # Résumé de fin de tâche (désactivé par défaut) : première phrase de la réponse de Claude.
    summary: (if $summary_on == "1" and .hook_event_name == "Stop"
      then (.last_assistant_message // ""
        | gsub("```[\\s\\S]*?```"; " ") | gsub("[`*_#>|]"; "") | gsub("\\s+"; " ") | ltrimstr(" ")
        | if length == 0 then null
          else ((capture("^(?<s>.{12,180}?[.!?…])(\\s|$)") | .s) // .[0:160]) end)
      else null end),
    recap: (if .hook_event_name == "Stop" then $recap else null end)
  }
  | with_entries(select(.value != null))' 2>/dev/null) || exit 0

curl -sS -m 8 -X POST "$PULSE_URL/api/hook" \
  -H "Authorization: Bearer $PULSE_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary "$payload" >/dev/null 2>&1

# Fin de tour : on recompte les tokens de la session (vue détaillée de l'app).
if [ "$event" = "Stop" ] || [ "$event" = "SessionEnd" ]; then
  [ -n "$transcript" ] && "$(dirname "$0")/tokens.sh" "$transcript"
fi
exit 0
