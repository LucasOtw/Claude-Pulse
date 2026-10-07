// Reçoit l'usage envoyé par la status line (mac/statusline.sh) : coût, contexte, limites d'abonnement.
// Pas de verrou ici : l'usage a sa propre clé, une seule requête Redis suffit (quota gratuit Upstash).
import { route } from '../lib/http.js';
import { limitAlerts } from '../lib/alerts.js';
import { notify, ntfyEnabled } from '../lib/notify.js';
import * as store from '../lib/store.js';

// Premier relevé d'une session : on ne le compte dans le coût du jour que si la session vient
// de démarrer. Sinon (session déjà ouverte avant l'installation, ou reprise), son coût
// cumulé date en partie d'avant et gonflerait le total du jour.
const NEW_SESSION_MS = 3 * 60 * 1000;

function costDelta(prev, cost, durationMs) {
  // Le coût de session repart de 0 après /clear : on n'additionne que les hausses.
  if (prev) return cost - (prev.costUsd ?? 0);
  return durationMs <= NEW_SESSION_MS ? cost : 0;
}

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
      limits: u.fiveHour || u.sevenDay
        ? { fiveHour: u.fiveHour ?? null, sevenDay: u.sevenDay ?? null, updatedAt: Math.floor(now / 1000) }
        : null,
      costDelta: costDelta(prev, cost, Number(u.durationMs)),
    },
    now,
  );
  // 80 % de la limite 5 h, puis remise à zéro programmée chez ntfy : une seule fois par fenêtre.
  if (ntfyEnabled()) {
    for (const a of limitAlerts(u.fiveHour)) {
      if (await store.once(a.key, 7 * 24 * 3600)) await notify(a);
    }
  }
  res.status(200).json({ ok: true });
});
