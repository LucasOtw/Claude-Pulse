// Traduit une action de la machine à états en push Live Activity.
import { attributes, contentState, markPushed } from './state.js';
import { sendLiveActivity, isDeadToken } from './apns.js';
import * as store from './store.js';

/**
 * Exécute l'action et met à jour s.la (l'appelant sauvegarde la session ensuite).
 * @returns {Promise<object>} un résumé pour le debug
 */
export async function runAction(s, action, limits, now) {
  const ts = Math.max(Math.floor(now / 1000), (s.la.lastTs || 0) + 1);
  const cs = contentState(s, limits, now);
  const alert = action.alert ? { ...action.alert, sound: 'default' } : undefined;

  if (action.kind === 'start') {
    const token = await store.getStartToken();
    if (!token) return { skipped: 'pas de jeton push-to-start (ouvre l’app sur l’iPhone)' };
    const payload = {
      aps: {
        timestamp: ts,
        event: 'start',
        'content-state': cs,
        'attributes-type': 'PulseAttributes',
        attributes: attributes(s),
        alert,
        'stale-date': ts + 2 * 3600,
      },
    };
    const r = await sendLiveActivity(token, payload, { priority: 10 });
    if (isDeadToken(r)) await store.delStartToken();
    if (r.status === 200) {
      await store.delActivityToken(s.sid); // la nouvelle activité enverra son propre jeton
      s.la.started = true;
      s.la.pendingEnd = false;
      s.la.startedAt = now;
      markPushed(s, now, ts);
    }
    return { start: r };
  }

  const token = await store.getActivityToken(s.sid);

  if (action.kind === 'end') {
    if (!token) {
      // L'iPhone n'a pas encore envoyé le jeton de l'activité : on la terminera à sa réception.
      s.la.pendingEnd = true;
      return { skipped: 'jeton de l’activité inconnu, fin différée' };
    }
    const payload = {
      aps: { timestamp: ts, event: 'end', 'content-state': cs, 'dismissal-date': ts + 30 * 60, alert },
    };
    const r = await sendLiveActivity(token, payload, { priority: 10 });
    s.la.started = false;
    s.la.pendingEnd = false;
    markPushed(s, now, ts);
    await store.delActivityToken(s.sid);
    return { end: r };
  }

  // update
  if (!token) return { skipped: 'jeton de l’activité inconnu' };
  const payload = { aps: { timestamp: ts, event: 'update', 'content-state': cs, 'stale-date': ts + 2 * 3600 } };
  if (alert) payload.aps.alert = alert;
  const r = await sendLiveActivity(token, payload, { priority: action.priority });
  if (isDeadToken(r)) {
    // Activité fermée à la main sur l'iPhone : on n'en relance pas avant la prochaine demande.
    s.la.started = false;
    s.la.dismissed = true;
    await store.delActivityToken(s.sid);
  } else if (r.status === 200) {
    markPushed(s, now, ts);
  }
  return { update: r };
}
