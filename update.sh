#!/bin/bash
# Met Claude Pulse à jour sur ce Mac en une commande :
#   ~/claude-pulse/update.sh     puis ⌘R dans Xcode.
# Récupère la dernière version, met à jour les scripts Claude Code et régénère le projet Xcode
# en gardant ton équipe. Le backend, lui, se redéploie tout seul sur Vercel.
set -euo pipefail
cd "$(dirname "$0")"

echo "⬇️  Récupération de la dernière version…"
git pull --ff-only --quiet
echo "   $(git log -1 --format='%h · %s')"

if [ -d "$HOME/.claude/claude-pulse" ]; then
  cp mac/hook.sh mac/statusline.sh "$HOME/.claude/claude-pulse/"
  chmod +x "$HOME/.claude/claude-pulse/hook.sh" "$HOME/.claude/claude-pulse/statusline.sh"
  echo "✅ Scripts Claude Code à jour"
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
