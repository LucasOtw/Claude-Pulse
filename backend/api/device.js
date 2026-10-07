// L'app iOS enregistre ici ses jetons push :
//  - kind "start"    : jeton push-to-start (permet de lancer une Live Activity à distance)
//  - kind "activity" : jeton d'une Live Activity précise (pour la mettre à jour / la terminer)
import { route } from '../lib/http.js';
import { withLock } from '../lib/redis.js';
import { runAction } from '../lib/live.js';
import * as store from '../lib/store.js';

export default route('POST', async (b, req, res) => {
  if (!b.token || !/^[0-9a-f]{20,}$/i.test(b.token)) return res.status(400).json({ error: 'token invalide' });

  if (b.kind === 'start') {
    await store.setStartToken(b.token);
    return res.status(200).json({ ok: true });
  }

  if (b.kind === 'activity' && b.sid) {
    await store.setActivityToken(b.sid, b.token);
    const now = Date.now();
    // Rattrapage : l'état a pu changer entre le lancement de l'activité et la réception de son jeton.
    const push = await withLock(b.sid, async () => {
      const s = await store.loadSession(b.sid);
      if (!s?.la?.started) return null;
      const kind = s.status === 'done' || s.status === 'error' ? 'end' : 'update';
      const r = await runAction(s, { kind, priority: 10 }, await store.getLimits(), now).catch((e) => ({ error: e.message }));
      await store.saveSession(s, s.updatedAt);
      return r;
    });
    return res.status(200).json({ ok: true, push });
  }

  res.status(400).json({ error: 'kind doit valoir "start" ou "activity"' });
});
