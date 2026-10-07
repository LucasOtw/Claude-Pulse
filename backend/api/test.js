// Démo depuis l'app pour vérifier la chaîne : {"step": "start" | "waiting" | "end"}.
// Crée une fausse session « Démo » que l'app affiche comme une vraie.
import { route } from '../lib/http.js';
import { withLock } from '../lib/redis.js';
import { applyEvent } from '../lib/state.js';
import * as store from '../lib/store.js';

const SID = 'demo';

export default route('POST', async (b, req, res) => {
  const step = b.step || 'start';
  const now = Date.now();
  const status = await withLock(SID, async () => {
    let s = step === 'start' ? null : await store.loadSession(SID);
    if (step === 'start') {
      // On fait comme si la tâche durait depuis une minute.
      s = applyEvent(null, { e: 'UserPromptSubmit', sid: SID, project: 'Démo' }, now - 60_000);
      s = applyEvent(s, {
        e: 'PreToolUse',
        sid: SID,
        tool: 'Edit',
        todos: [
          { c: 'Analyser le code', s: 'completed' },
          { c: 'Écrire les tests', s: 'completed' },
          { c: 'Implémenter la fonctionnalité', s: 'in_progress' },
          { c: 'Lancer la CI', s: 'pending' },
        ],
      }, now);
    } else if (step === 'waiting') {
      s = applyEvent(s, { e: 'Notification', sid: SID, ntype: 'permission_prompt', message: 'Claude needs your permission to use Bash' }, now);
    } else {
      s = applyEvent(s, { e: 'Stop', sid: SID, bg: [] }, now);
    }
    await store.saveSession(s);
    return s.status;
  });
  res.status(200).json({ status });
});
