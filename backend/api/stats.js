// Vue détaillée de l'app : tokens consommés et équivalent en dollars au tarif de l'API.
import { route } from '../lib/http.js';
import { buildStats } from '../lib/stats.js';
import * as store from '../lib/store.js';

export default route('GET', async (_b, req, res) => {
  const now = Date.now();
  const sessions = await store.readTokens();
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json(buildStats(sessions, store.day(now)));
});
