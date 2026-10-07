// Réponse depuis l'iPhone (app ou bouton de la Live Activity) : { id, allow: true | false }.
import { route } from '../lib/http.js';
import * as store from '../lib/store.js';

export default route('POST', async (b, req, res) => {
  const a = b.id ? await store.getApproval(String(b.id)) : null;
  if (!a) return res.status(404).json({ error: 'Demande expirée' });
  if (a.decision !== 'pending') return res.status(409).json({ error: 'Déjà traitée', decision: a.decision });
  // Garde-fou : une commande dangereuse ne s'autorise que sur le Mac.
  if (b.allow === true && a.danger) return res.status(403).json({ error: 'Commande sensible : à valider sur le Mac' });
  const done = await store.decideApproval(a.id, b.allow === true ? 'allow' : 'deny');
  res.status(200).json({ ok: true, decision: done.decision });
});
