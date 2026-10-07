// Reçoit les événements des hooks Claude Code (mac/hook.sh).
import { route } from '../lib/http.js';
import { withLock } from '../lib/redis.js';
import { applyEvent } from '../lib/state.js';
import { sessionAlert } from '../lib/alerts.js';
import { notify, ntfyEnabled } from '../lib/notify.js';
import * as store from '../lib/store.js';

export default route('POST', async (ev, req, res) => {
  if (!ev.sid || !ev.e) return res.status(400).json({ error: 'sid et e requis' });
  const now = Date.now();
  const { status, alert } = await withLock(ev.sid, async () => {
    const prev = await store.loadSession(ev.sid);
    const s = applyEvent(prev, ev, now);
    await store.saveSession(s);
    return { status: s.status, alert: ntfyEnabled() ? sessionAlert(prev, s, now) : null };
  });
  if (alert) await notify(alert);
  res.status(200).json({ status });
});
