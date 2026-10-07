// Vue détaillée d'une session : étapes, sous-agents, journal, contexte, tokens.
import { route } from '../lib/http.js';
import { sessionDetail } from '../lib/state.js';
import { buildStats } from '../lib/stats.js';
import * as store from '../lib/store.js';

export default route('GET', async (_b, req, res) => {
  const sid = req.query?.sid ?? new URL(req.url ?? '/', 'http://local').searchParams.get('sid');
  if (!sid) return res.status(400).json({ error: 'sid requis' });
  const now = Date.now();
  const [s, days] = await Promise.all([store.loadSession(sid), store.readSessionTokens(sid)]);
  if (!s) return res.status(404).json({ error: 'session inconnue' });
  const tokens = days ? buildStats({ [sid]: days }, store.day(now)).totals : null;
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json(sessionDetail(s, tokens, now));
});
