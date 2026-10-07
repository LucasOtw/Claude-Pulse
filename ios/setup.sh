#!/bin/bash
# Prépare le projet Xcode : écrit Shared/PulseSecrets.swift (URL + jeton du backend), génère et ouvre le projet.
# Usage : ./setup.sh [URL_DU_BACKEND] [PULSE_TOKEN]
set -euo pipefail
cd "$(dirname "$0")"

URL="${1:-}"
TOKEN="${2:-}"
[ -n "$URL" ] || read -rp "URL du backend (ex. https://claude-pulse-xxx.vercel.app) : " URL
[ -n "$TOKEN" ] || { read -rsp "PULSE_TOKEN : " TOKEN; echo; }
URL="${URL%/}"

# Échappe les antislashs et guillemets pour une chaîne Swift.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

cat > Shared/PulseSecrets.swift <<SWIFT
// Généré par ios/setup.sh. Ignoré par git : ne le commite pas.
enum PulseSecrets {
    static let baseURL = "$(esc "$URL")"
    static let token = "$(esc "$TOKEN")"
}
SWIFT
echo "✅ Shared/PulseSecrets.swift écrit."

code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -H "Authorization: Bearer $TOKEN" "$URL/api/state" || true)
case "$code" in
  200) echo "✅ Backend joignable et jeton accepté." ;;
  401) echo "⚠️  Le backend refuse le jeton : vérifie PULSE_TOKEN dans Vercel." ;;
  *)   echo "⚠️  Backend injoignable (HTTP $code) : vérifie l'URL." ;;
esac

if ! command -v xcodegen >/dev/null; then
  echo "❌ XcodeGen manquant : brew install xcodegen, puis relance ce script."
  exit 1
fi
xcodegen
open ClaudePulse.xcodeproj
