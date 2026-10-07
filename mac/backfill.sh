#!/bin/bash
# Claude Pulse — envoie l'historique de tokens encore présent sur ce Mac (toutes les sessions
# Claude Code gardées dans ~/.claude/projects, 30 derniers jours par défaut).
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/.claude/projects"
[ -d "$ROOT" ] || { echo "   Aucun historique Claude Code trouvé."; exit 0; }
count=$(find "$ROOT" -mindepth 2 -maxdepth 2 -name '*.jsonl' | wc -l | tr -d ' ')
echo "📊 Lecture de l'historique : $count session(s)…"
find "$ROOT" -mindepth 2 -maxdepth 2 -name '*.jsonl' -print0 | xargs -0 "$DIR/tokens.sh"
echo "✅ Historique des tokens envoyé"
