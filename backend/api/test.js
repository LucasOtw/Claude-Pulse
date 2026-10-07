// Démo pour vérifier la chaîne de bout en bout depuis l'app : {"step": "start" | "waiting" | "end"}.
import { route } from '../lib/http.js';
import { withLock } from '../lib/redis.js';
import { applyEvent } from '../lib/state.js';
import { runAction } from '../lib/live.js';
import * as store from '../lib/store.js';

const SID = 'demo';

export default route('POST', async (b, req, res) => {
  const step = b.step || 'start';
  const now = Date.now();
  const result = await withLock(SID, async () => {
    let s = await store.loadSession(SID);
    const events = [];
    if (step === 'start') {
      s = null; // repart de zéro
      events.push(
        { e: 'UserPromptSubmit', sid: SID, project: 'Démo' },
        {
          e: 'PreToolUse',
          sid: SID,
          tool: 'Edit',
          todos: [
            { c: 'Analyser le code', s: 'completed' },
            { c: 'Écrire les tests', s: 'completed' },
            { c: 'Implémenter la fonctionnalité', s: 'in_progress' },
            { c: 'Lancer la CI', s: 'pending' },
          ],
        },
      );
    } else if (step === 'waiting') {
      events.push({ e: 'Notification', sid: SID, ntype: 'permission_prompt', message: 'Claude veut lancer npm test' });
    } else {
      events.push({ e: 'Stop', sid: SID, bg: [] });
    }

    let action = null;
    for (const [i, ev] of events.entries()) {
      // Pour la démo on fait comme si la tâche durait depuis une minute.
      const t = step === 'start' && i === 0 ? now - 60_000 : now;
      ({ state: s, action } = applyEvent(s, ev, t));
    }
    const push = action ? await runAction(s, action, await store.getLimits(), now).catch((e) => ({ error: e.message })) : null;
    await store.saveSession(s, now);
    return { status: s.status, action: action?.kind ?? null, push };
  });
  res.status(200).json(result);
});
