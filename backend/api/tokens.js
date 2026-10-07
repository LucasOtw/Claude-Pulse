// Reçoit les totaux de tokens calculés sur le Mac à partir des transcripts (mac/tokens.sh).
// Chaque envoi remplace les totaux de la session : renvoyer deux fois la même session ne compte pas double.
import { route } from '../lib/http.js';
import * as store from '../lib/store.js';

export default route('POST', async (b, req, res) => {
  const sessions = Array.isArray(b.sessions) ? b.sessions : [];
  const valid = sessions.filter((s) => typeof s?.sid === 'string' && s.sid && s.days && typeof s.days === 'object');
  if (!valid.length) return res.status(400).json({ error: 'sessions[] requis : { sid, project?, days }' });
  await store.saveTokens(valid.slice(0, 500));
  res.status(200).json({ ok: true, saved: Math.min(valid.length, 500) });
});
