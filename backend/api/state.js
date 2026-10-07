// Lu par l'app et le widget iOS.
import { route } from '../lib/http.js';
import { publicSession } from '../lib/state.js';
import * as store from '../lib/store.js';

export default route('GET', async (_b, req, res) => {
  const now = Date.now();
  const [limits, today, sessions, startToken] = await Promise.all([
    store.getLimits(),
    store.today(now),
    store.listSessions(now),
    store.getStartToken(),
  ]);
  const nowSec = now / 1000;
  // Une fenêtre dont la date de remise à zéro est passée n'a plus de sens.
  const fresh = (l) => (l && l.resetsAt > nowSec ? l : null);
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json({
    updatedAt: Math.floor(nowSec),
    limits: { fiveHour: fresh(limits?.fiveHour), sevenDay: fresh(limits?.sevenDay) },
    today,
    sessions: sessions.filter((s) => s.sid !== 'demo').map((s) => publicSession(s, now)),
    pushReady: Boolean(startToken),
  });
});
