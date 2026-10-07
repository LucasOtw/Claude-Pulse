// Validation à distance, côté Mac (mac/approve.sh) :
//   POST { sid, project, tool, input }  → crée une demande si la validation à distance est allumée
//   POST { cancel: id }                 → le Mac a cessé d'attendre
//   GET  ?id=…                          → décision : pending | allow | deny
import crypto from 'node:crypto';
import { route } from '../lib/http.js';
import { describe, isDangerous, APPROVAL_TTL } from '../lib/approval.js';
import * as store from '../lib/store.js';

export default route(['GET', 'POST'], async (b, req, res) => {
  if (req.method === 'GET') {
    const id = req.query?.id ?? new URL(req.url ?? '/', 'http://local').searchParams.get('id');
    const a = id ? await store.getApproval(id) : null;
    return res.status(200).json({ decision: a?.decision ?? 'expired' });
  }

  if (b.cancel) {
    await store.dropApprovals([String(b.cancel)]);
    return res.status(200).json({ ok: true });
  }

  if (!b.sid || !b.tool) return res.status(400).json({ error: 'sid et tool requis' });
  if (!(await store.getRemote())) return res.status(200).json({ remote: false });

  const { text, note } = describe(b.tool, b.input);
  const a = {
    id: crypto.randomUUID(),
    sid: String(b.sid),
    project: String(b.project || 'Claude Code').slice(0, 80),
    tool: String(b.tool).slice(0, 80),
    text,
    note,
    danger: isDangerous(b.tool, text),
    createdAt: Math.floor(Date.now() / 1000),
    decision: 'pending',
  };
  await store.createApproval(a, APPROVAL_TTL);
  res.status(200).json({ remote: true, id: a.id });
});
