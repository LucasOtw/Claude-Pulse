// Reçoit les événements des hooks Claude Code (mac/hook.sh).
import { route } from '../lib/http.js';
import { withLock } from '../lib/redis.js';
import { applyEvent } from '../lib/state.js';
import * as store from '../lib/store.js';

export default route('POST', async (ev, req, res) => {
  if (!ev.sid || !ev.e) return res.status(400).json({ error: 'sid et e requis' });
  const now = Date.now();
  const status = await withLock(ev.sid, async () => {
    const s = applyEvent(await store.loadSession(ev.sid), ev, now);
    await store.saveSession(s);
    return s.status;
  });
  res.status(200).json({ status });
});
