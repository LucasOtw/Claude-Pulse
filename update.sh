#!/bin/bash
# Met Claude Pulse à jour sur ce Mac en une commande :
#   ~/claude-pulse/update.sh     puis ⌘R dans Xcode.
# Récupère la dernière version, met à jour les scripts Claude Code et régénère le projet Xcode
# en gardant ton équipe. Le backend, lui, se redéploie tout seul sur Vercel.
set -euo pipefail
cd "$(dirname "$0")"

echo "⬇️  Récupération de la dernière version…"
# Une frappe accidentelle dans Xcode suffit à casser le build ou à bloquer la mise à jour :
# le code de GitHub fait foi. Les modifications locales sont mises de côté (git stash list).
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "   Modifications locales mises de côté : $(git diff --name-only HEAD | tr '\n' ' ')"
  git stash push --quiet -m "update.sh $(date '+%Y-%m-%d %H:%M')"
fi
git pull --ff-only --quiet
echo "   $(git log -1 --format='%h · %s')"

if [ -f "$HOME/.claude/claude-pulse/config" ]; then
  # Mêmes URL et jeton : scripts, hooks et status line remis à jour, réglages conservés.
  url=$( (. "$HOME/.claude/claude-pulse/config"; printf '%s' "$PULSE_URL") )
  token=$( (. "$HOME/.claude/claude-pulse/config"; printf '%s' "$PULSE_TOKEN") )
  mac/install.sh "$url" "$token" | grep -v "Relance tes sessions" || true
else
  echo "⚠️  Claude Code pas encore relié : lance une fois mac/install.sh"
fi

if [ ! -f ios/Shared/PulseSecrets.swift ]; then
  echo "⚠️  App pas encore configurée : lance une fois ios/setup.sh"
  exit 1
fi
ios/generate.sh
open ios/ClaudePulse.xcodeproj
echo "👉 Dans Xcode : ⌘R"
