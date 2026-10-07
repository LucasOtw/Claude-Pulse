// Interrupteur « validation à distance » de l'iPhone. S'éteint tout seul au bout de 12 h.
import { route } from '../lib/http.js';
import { REMOTE_TTL } from '../lib/approval.js';
import * as store from '../lib/store.js';

export default route(['GET', 'POST'], async (b, req, res) => {
  if (req.method === 'POST') await store.setRemote(b.on === true, REMOTE_TTL);
  res.status(200).json({ on: await store.getRemote() });
});
