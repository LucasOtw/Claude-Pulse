// Reçoit les événements des hooks Claude Code (mac/hook.sh).
import { route } from '../lib/http.js';
import { withLock } from '../lib/redis.js';
import { applyEvent } from '../lib/state.js';
import { runAction } from '../lib/live.js';
import * as store from '../lib/store.js';

export default route('POST', async (ev, req, res) => {
  if (!ev.sid || !ev.e) return res.status(400).json({ error: 'sid et e requis' });
  const now = Date.now();
  const result = await withLock(ev.sid, async () => {
    const prev = await store.loadSession(ev.sid);
    const { state, action } = applyEvent(prev, ev, now);
    let push = null;
    if (action) {
      const limits = await store.getLimits();
      push = await runAction(state, action, limits, now).catch((e) => ({ error: e.message }));
    }
    await store.saveSession(state, now);
    return { status: state.status, action: action?.kind ?? null, push };
  });
  res.status(200).json(result);
});
