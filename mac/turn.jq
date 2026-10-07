# Récapitulatif du dernier tour (de ta dernière demande jusqu'à maintenant), pour la
# notification « terminé ». Métadonnées seulement : noms de fichiers, nombres.
# Usage : tail -n 4000 session.jsonl | jq -R -n -c -f turn.jq
def prompt:
  .type == "user" and (.isMeta != true)
  and (.message.content | (type == "string") or (type == "array" and any(.[]; .type == "text")));
def empty_turn: {files: [], commands: 0, agents: 0};

reduce (inputs | fromjson? // empty) as $l (empty_turn;
  if ($l | prompt) then empty_turn
  elif $l.type == "assistant" then
    reduce ($l.message.content[]? | objects | select(.type == "tool_use")) as $t (.;
      if ($t.name | IN("Edit", "MultiEdit", "Write", "NotebookEdit")) then
        (($t.input.file_path // $t.input.notebook_path // "") | split("/") | last) as $f
        | if ($f | length) == 0 or any(.files[]; . == $f) then . else .files += [$f] end
      elif $t.name == "Bash" then .commands += 1
      elif ($t.name | IN("Agent", "Task")) then .agents += 1
      else . end)
  else . end)
| {files: [.files[] | .[0:60]][0:8], fileCount: (.files | length), commands, agents}
