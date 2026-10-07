// Reçoit les événements des hooks Claude Code (mac/hook.sh).
import { route } from '../lib/http.js';
import { withLock } from '../lib/redis.js';
import { applyEvent } from '../lib/state.js';
import { sessionAlert, dedupeKey } from '../lib/alerts.js';
import { notify, ntfyEnabled } from '../lib/notify.js';
import * as store from '../lib/store.js';

export default route('POST', async (ev, req, res) => {
  if (!ev.sid || !ev.e) return res.status(400).json({ error: 'sid et e requis' });
  const now = Date.now();
  const { status, alert } = await withLock(ev.sid, async () => {
    const prev = await store.loadSession(ev.sid);
    const s = applyEvent(prev, ev, now);
    await store.saveSession(s);
    if (!ntfyEnabled()) return { status: s.status, alert: null };
    // Limite atteinte : l'heure de reprise vient du dernier relevé des limites.
    const limits = s.status === 'error' && s.error === 'rate_limit' ? await store.getLimits() : null;
    return { status: s.status, alert: sessionAlert(prev, s, now, limits) };
  });
  // Plusieurs sessions qui s'arrêtent ensemble (limite, workflow) : une seule notification.
  for (const n of [alert, alert?.followUp]) {
    if (!n) continue;
    const { key, ttl } = dedupeKey(n);
    if (await store.once(key, ttl)) await notify(n);
  }
  res.status(200).json({ status });
});
