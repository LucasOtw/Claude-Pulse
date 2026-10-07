#!/bin/bash
# Tests des scripts Mac (lancés aussi par GitHub Actions) : ./mac/test.sh
# Un faux backend local capture ce que les scripts envoient.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d)
trap 'kill $SERVER 2>/dev/null || true; rm -rf "$WORK"' EXIT
cd "$WORK"
fail() { echo "❌ $1"; exit 1; }
ok() { echo "✅ $1"; }

# --- Faux backend : enregistre les requêtes, répond selon le chemin.
cat > server.py <<'PY'
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, obj):
        b = json.dumps(obj).encode(); self.send_response(200)
        self.send_header('Content-Type', 'application/json'); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.startswith('/api/approval'):
            return self.reply({'decision': open('decision').read().strip()})
        self.reply({})
    def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length'])).decode()
        open('got.jsonl', 'a').write(self.path + ' ' + body + '\n')
        if self.path == '/api/approval':
            if 'cancel' in body: return self.reply({'ok': True})
            remote = open('remote').read().strip() == '1'
            return self.reply({'remote': remote, 'id': 'abc'} if remote else {'remote': False})
        self.reply({})
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
PORT=$((20000 + RANDOM % 20000))
python3 server.py "$PORT" & SERVER=$!
sleep 0.5
echo 0 > remote; echo pending > decision
export TMPDIR="$WORK/" CLAUDE_PULSE_CONFIG="$WORK/config"
printf 'PULSE_URL=http://127.0.0.1:%s\nPULSE_TOKEN=t\n' "$PORT" > config
last() { grep -v '^$' got.jsonl | tail -n 1 | cut -d' ' -f2-; }

# --- hook.sh : métadonnées seulement
echo '{"session_id":"s","cwd":"/x/App","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/x/App/A.swift","old_string":"SECRET"}}' | "$HERE/hook.sh"
[ "$(last | jq -r .detail)" = "A.swift" ] || fail "détail Edit"
grep -q SECRET got.jsonl && fail "contenu envoyé"
ok "hook.sh : nom de fichier sans contenu"

stop='{"session_id":"s2","cwd":"/x/App","hook_event_name":"Stop","last_assistant_message":"J’ai corrigé les **tests** du backend. Ensuite SECRET.","background_tasks":[]}'
echo "$stop" | "$HERE/hook.sh"
[ "$(grep '"e":"Stop"' got.jsonl | tail -n 1 | cut -d' ' -f2- | jq -r '.summary // "none"')" = "none" ] || fail "résumé envoyé sans PULSE_SUMMARY"
echo 'PULSE_SUMMARY=1' >> config
echo "$stop" | "$HERE/hook.sh"
[ "$(grep '"e":"Stop"' got.jsonl | tail -n 1 | cut -d' ' -f2- | jq -r .summary)" = "J’ai corrigé les tests du backend." ] || fail "résumé"
ok "hook.sh : résumé seulement si activé, première phrase"

cat > turn.jsonl <<'J'
{"type":"user","message":{"role":"user","content":"ancienne demande"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/old.js"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"nouvelle demande"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/App/contact.html","old_string":"SECRET"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"1","content":"SECRET"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"SECRET"}},{"type":"tool_use","name":"Edit","input":{"file_path":"/x/App/contact.html"}},{"type":"tool_use","name":"Agent","input":{}}]}}
J
echo "{\"session_id\":\"s3\",\"cwd\":\"/x/App\",\"hook_event_name\":\"Stop\",\"transcript_path\":\"$WORK/turn.jsonl\"}" | "$HERE/hook.sh"
[ "$(grep '"sid":"s3"' got.jsonl | grep '"e":"Stop"' | tail -n 1 | cut -d' ' -f2- | jq -c .recap)" = '{"files":["contact.html"],"fileCount":1,"commands":1,"agents":1}' ] || fail "récapitulatif du tour"
grep '"sid":"s3"' got.jsonl | grep -q SECRET && fail "contenu envoyé dans le récapitulatif"
ok "hook.sh : récapitulatif du dernier tour (noms de fichiers et nombres seulement)"

# --- tokens.jq : dédoublonnage, cache 1 h, sous-agents ignorés ici
cat > t.jsonl <<'J'
{"type":"assistant","requestId":"r1","timestamp":"2026-10-07T08:00:05.123Z","cwd":"/x/App","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":1000,"cache_read_input_tokens":20000,"cache_creation":{"ephemeral_1h_input_tokens":1000}}}}
{"type":"assistant","requestId":"r1","timestamp":"2026-10-07T08:00:05.500Z","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":1000,"cache_read_input_tokens":20000}}}
pas du json
J
[ "$(TZ=UTC jq -nRc -f "$HERE/tokens.jq" < t.jsonl)" = '{"2026-10-07":{"claude-opus-5-5":[100,50,0,1000,20000]}}' ] || fail "tokens.jq"
ok "tokens.jq : un message compté une fois"
"$HERE/tokens.sh" "$WORK/t.jsonl"
[ "$(last | jq -r '.sessions[0].project')" = "App" ] || { tail -n 2 got.jsonl; fail "projet des tokens"; }
ok "tokens.sh : projet envoyé"

# --- approve.sh : éteint → rien ; allumé → décision du téléphone
perm='{"session_id":"s","cwd":"/x/App","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"}}'
[ -z "$(echo "$perm" | "$HERE/approve.sh")" ] || fail "approve.sh doit rendre la main si éteint"
[ "$(last | jq -r .input.command)" = "npm test" ] || fail "commande envoyée"
echo 1 > remote; echo allow > decision
out=$(echo "$perm" | "$HERE/approve.sh")
[ "$(echo "$out" | jq -r .hookSpecificOutput.decision.behavior)" = "allow" ] || fail "autorisation"
echo deny > decision
out=$(echo "$perm" | "$HERE/approve.sh")
[ "$(echo "$out" | jq -r .hookSpecificOutput.decision.behavior)" = "deny" ] || fail "refus"
echo pending > decision
out=$(echo "$perm" | PULSE_APPROVAL_WAIT=3 "$HERE/approve.sh")
[ -z "$out" ] && last | grep -q cancel || fail "délai dépassé"
ok "approve.sh : éteint, autorisé, refusé, délai dépassé"

# --- install.sh / uninstall.sh dans un HOME jetable
H="$WORK/home"; mkdir -p "$H/.claude/claude-pulse"
echo '{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}' > "$H/.claude/settings.json"
printf 'PULSE_SUMMARY=1\n' > "$H/.claude/claude-pulse/config"
HOME="$H" CLAUDE_PULSE_CONFIG="$H/.claude/claude-pulse/config" "$HERE/install.sh" "http://127.0.0.1:$PORT" t >/dev/null
HOME="$H" CLAUDE_PULSE_CONFIG="$H/.claude/claude-pulse/config" "$HERE/install.sh" "http://127.0.0.1:$PORT" t >/dev/null
S="$H/.claude/settings.json"
[ "$(jq '.hooks.Stop | length' "$S")" = 2 ] || fail "install idempotent"
[ "$(jq -r '.hooks.PermissionRequest[0].hooks[0].timeout' "$S")" = 600 ] || fail "hook de permission"
grep -q '^PULSE_SUMMARY=1$' "$H/.claude/claude-pulse/config" || fail "réglage conservé"
HOME="$H" "$HERE/uninstall.sh" >/dev/null
[ "$(jq -c . "$S")" = '{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}' ] || fail "désinstallation"
ok "install.sh / uninstall.sh"

echo "Tous les tests des scripts Mac passent."
