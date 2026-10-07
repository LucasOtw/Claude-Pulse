#!/bin/bash
# Régénère ClaudePulse.xcodeproj en gardant ton équipe de signature (Local.xcconfig).
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || { echo "❌ XcodeGen manquant : brew install xcodegen"; exit 1; }

TEAM=""
if [ -f Local.xcconfig ]; then
  TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Local.xcconfig | tr -d ' \r')
fi
# Équipe choisie à la main dans Xcode : on la récupère avant d'écraser le projet.
if [ -z "$TEAM" ] && [ -f ClaudePulse.xcodeproj/project.pbxproj ]; then
  TEAM=$(grep -oE 'DEVELOPMENT_TEAM = [A-Z0-9]+;' ClaudePulse.xcodeproj/project.pbxproj | head -n 1 | sed 's/DEVELOPMENT_TEAM = //; s/;//' || true)
fi

printf '// Généré par ios/generate.sh, ignoré par git : ton équipe de signature.\nDEVELOPMENT_TEAM = %s\n' "$TEAM" > Local.xcconfig

xcodegen generate --quiet
if [ -n "$TEAM" ]; then
  echo "✅ Projet Xcode régénéré (équipe $TEAM)"
else
  echo "✅ Projet Xcode régénéré. Choisis ton équipe dans Xcode (Signing & Capabilities), une seule fois :"
  echo "   les prochaines mises à jour la garderont."
fi
