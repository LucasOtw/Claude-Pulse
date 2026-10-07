// Lu par l'app (toutes les quelques secondes pendant la surveillance) et par le widget.
import { route } from '../lib/http.js';
import { publicSession } from '../lib/state.js';
import * as store from '../lib/store.js';

const SHOW_MS = 6 * 3600 * 1000; // sessions affichées : actives ces 6 dernières heures
const FORGET_MS = 2 * 24 * 3600 * 1000;

export default route('GET', async (_b, req, res) => {
  const now = Date.now();
  const { snaps, usage, limits, today } = await store.readLive(now);

  const stale = snaps.filter((s) => now - s.updatedAt * 1000 > FORGET_MS).map((s) => s.sid);
  if (stale.length) await store.prune(stale);

  const sessions = snaps
    .filter((s) => now - s.updatedAt * 1000 <= SHOW_MS)
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, 10)
    .map((s) => publicSession(s, usage[s.sid], now));

  // Une fenêtre dont la date de remise à zéro est passée n'a plus de sens.
  const nowSec = now / 1000;
  const fresh = (l) => (l && l.resetsAt > nowSec ? l : null);

  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json({
    updatedAt: Math.floor(nowSec),
    limits: { fiveHour: fresh(limits?.fiveHour), sevenDay: fresh(limits?.sevenDay) },
    today,
    sessions,
  });
});
