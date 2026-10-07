// Décide quelles notifications envoyer. Fonctions pures, testées dans test/alerts.test.js.
import { formatDuration } from './state.js';

const ACTIVE = new Set(['running', 'waiting', 'background']);

/** Changement de statut d'une session → notification (ou null). */
export function sessionAlert(prev, s, now) {
  const before = prev?.status;
  if (s.status === before) return null;
  const p = s.project;
  if (s.status === 'waiting') {
    return { title: `${p} attend ta validation`, message: s.activity, tags: ['raised_hand'], priority: 4 };
  }
  if (s.status === 'error' && ACTIVE.has(before)) {
    return { title: `${p} : erreur`, message: s.activity, tags: ['warning'], priority: 4 };
  }
  if (s.status === 'done' && ACTIVE.has(before) && now - s.turnStartedAt >= 30_000) {
    const duration = `En ${formatDuration(now - s.turnStartedAt)}`;
    return { title: `${p} : terminé`, message: s.summary ? `${s.summary}\n${duration}` : duration, tags: ['white_check_mark'], priority: 3 };
  }
  return null;
}

export const LIMIT_ALERT_PCT = 80;

/**
 * Relevé des limites → alertes : passage de 80 % de la limite 5 h, et remise à zéro programmée
 * (seulement si la fenêtre a dépassé 80 %, sinon elle n'intéresse personne).
 * Renvoie des alertes avec une clé unique par fenêtre, pour ne jamais les envoyer deux fois.
 */
export function limitAlerts(fiveHour) {
  if (!fiveHour || !(fiveHour.pct >= LIMIT_ALERT_PCT) || !fiveHour.resetsAt) return [];
  const reset = new Date(fiveHour.resetsAt * 1000).toLocaleTimeString('fr-FR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: process.env.PULSE_TZ || 'Europe/Paris',
  });
  return [
    {
      key: `alert:80:${fiveHour.resetsAt}`,
      title: `Limite 5 h à ${Math.round(fiveHour.pct)} %`,
      message: `Remise à zéro à ${reset}.`,
      tags: ['hourglass_flowing_sand'],
      priority: 4,
    },
    {
      key: `alert:reset:${fiveHour.resetsAt}`,
      title: 'Limite 5 h remise à zéro',
      message: 'Tu peux relancer Claude.',
      tags: ['battery'],
      priority: 3,
      delay: fiveHour.resetsAt,
    },
  ];
}
