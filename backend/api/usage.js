// Reçoit l'usage envoyé par la status line (mac/statusline.sh) : coût, contexte, limites d'abonnement.
// Pas de verrou ici : l'usage a sa propre clé, une seule requête Redis suffit (quota gratuit Upstash).
import { route } from '../lib/http.js';
import * as store from '../lib/store.js';

export default route('POST', async (u, req, res) => {
  if (!u.sid) return res.status(400).json({ error: 'sid requis' });
  const now = Date.now();
  const prev = await store.getUsage(u.sid);
  const cost = Number(u.costUsd) || 0;
  await store.recordUsage(
    {
      sid: u.sid,
      usage: { costUsd: cost, contextPct: Number(u.contextPct) || 0, model: u.model ?? null, title: u.title ?? null },
      // Les limites 5 h / 7 jours sont celles du compte : on garde le dernier relevé.
      limits: u.fiveHour || u.sevenDay ? { fiveHour: u.fiveHour ?? null, sevenDay: u.sevenDay ?? null } : null,
      // Le coût de session repart de 0 après /clear : on n'additionne que les hausses.
      costDelta: cost - (prev?.costUsd ?? 0),
    },
    now,
  );
  res.status(200).json({ ok: true });
});
