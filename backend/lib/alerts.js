// Décide quelles notifications envoyer et rédige leur texte. Fonctions pures, testées dans
// test/alerts.test.js. Pas d'emoji : un titre qui dit quoi, un corps qui dit le détail utile.
import { formatDuration, progress } from './state.js';

const ACTIVE = new Set(['running', 'waiting', 'background']);

const plural = (n, one, many = `${one}s`) => `${n} ${n > 1 ? many : one}`;

const TZ = () => process.env.PULSE_TZ || 'Europe/Paris';
const clock = (ms) => new Date(ms).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit', timeZone: TZ() });
const dayOf = (ms) => new Date(ms).toLocaleDateString('fr-FR', { timeZone: TZ() });

/** « à 19:20 (dans 2 h 51) », ou « jeudi à 14:00 » si ce n'est pas aujourd'hui. */
function resumeAt(ms, now) {
  if (dayOf(ms) === dayOf(now)) return `à ${clock(ms)} (dans ${formatDuration(ms - now)})`;
  return `${new Date(ms).toLocaleDateString('fr-FR', { weekday: 'long', timeZone: TZ() })} à ${clock(ms)}`;
}

/** « contact.html, style.css et 3 autres » */
export function fileList(files, count) {
  const shown = files.slice(0, 3);
  const rest = Math.max(0, count - shown.length);
  if (shown.length === 0) return '';
  if (rest === 0) return shown.length === 1 ? shown[0] : `${shown.slice(0, -1).join(', ')} et ${shown.at(-1)}`;
  return `${shown.join(', ')} et ${plural(rest, 'autre')}`;
}

/** Ce que Claude veut faire, à partir du nom de l'outil (« exécuter une commande »). */
export function toolAction(tool) {
  const t = String(tool || '');
  const known = {
    Bash: 'exécuter une commande',
    Edit: 'modifier un fichier',
    MultiEdit: 'modifier un fichier',
    Write: 'créer un fichier',
    NotebookEdit: 'modifier un notebook',
    WebFetch: 'ouvrir une page web',
    WebSearch: 'faire une recherche web',
    Agent: 'lancer un sous-agent',
    Task: 'lancer un sous-agent',
    Workflow: 'lancer un workflow',
  };
  if (known[t]) return known[t];
  if (t.startsWith('mcp__')) return `utiliser ${t.split('__')[1] || 'un outil'}`;
  return t ? `utiliser ${t}` : 'continuer';
}

const ERRORS = {
  rate_limit: "Limite d'utilisation atteinte.",
  overloaded: "Les serveurs d'Anthropic sont surchargés.",
  server_error: "Erreur côté serveur d'Anthropic.",
  authentication_failed: 'Authentification refusée : reconnecte-toi avec /login.',
  billing_error: 'Problème de facturation sur ton compte.',
  invalid_request: 'Requête refusée par l’API.',
  max_output_tokens: 'Réponse trop longue, coupée par l’API.',
};

function doneMessage(s) {
  const lines = [];
  if (s.summary) lines.push(s.summary);
  const r = s.recap;
  if (r?.fileCount > 0) {
    const names = fileList(r.files ?? [], r.fileCount);
    lines.push(`${plural(r.fileCount, 'fichier modifié', 'fichiers modifiés')} : ${names}`);
  }
  const extra = [];
  const p = progress(s);
  if (p.total > 0) extra.push(`${p.done} étape${p.done > 1 ? 's' : ''} sur ${p.total}`);
  if (r?.commands > 0) extra.push(plural(r.commands, 'commande'));
  if (r?.agents > 0) extra.push(plural(r.agents, 'sous-agent'));
  if (extra.length) lines.push(extra.join(' · '));
  if (lines.length === 0) lines.push('Claude a fini et attend ta prochaine demande.');
  return lines.join('\n');
}

/**
 * Changement de statut d'une session → notification (ou null).
 * `key` / `ttl` : une notification portant la même clé n'est pas renvoyée avant `ttl` secondes
 * (sinon, clé tirée du texte, voir dedupeKey).
 */
export function sessionAlert(prev, s, now, limits = null) {
  const before = prev?.status;
  if (s.status === before) return null;
  const p = s.project;
  if (s.status === 'waiting') {
    const tool = /^Veut utiliser (.+) : à valider$/.exec(s.activity ?? '')?.[1];
    const step = progress(s).current;
    const ask = tool
      ? `Claude veut ${toolAction(tool)} et attend ton accord dans le terminal.`
      : s.activity === 'Attend ta validation'
        ? 'Claude attend ton accord dans le terminal.'
        : 'Claude te pose une question dans le terminal.';
    return {
      title: `${p} · ${(tool || s.activity === 'Attend ta validation') ? 'Accord nécessaire' : 'Question en attente'}`,
      message: step ? `${ask}\nÉtape en cours : ${step}` : ask,
      priority: 4,
    };
  }
  if (s.status === 'error' && ACTIVE.has(before)) {
    if (s.error === 'rate_limit') return rateLimitAlert(limits, now);
    const why = ERRORS[s.error] ?? (s.error ? `Erreur : ${s.error}.` : 'Erreur inconnue.');
    return {
      key: `alert:error:${p}:${s.error ?? ''}`, // même erreur sur le même projet : une fois par 10 min
      ttl: 600,
      title: `${p} · Arrêt sur erreur`,
      message: `${why}\nRelance la tâche depuis le terminal.`,
      priority: 4,
    };
  }
  if (s.status === 'done' && ACTIVE.has(before) && now - s.turnStartedAt >= 30_000) {
    return { title: `${p} · Terminé en ${formatDuration(now - s.turnStartedAt)}`, message: doneMessage(s), priority: 3 };
  }
  return null;
}

/**
 * Limite d'utilisation atteinte : elle vaut pour tout le compte, donc toutes les sessions
 * (et les sous-sessions d'un workflow) s'arrêtent en même temps. Une seule notification,
 * avec l'heure de reprise, et une autre programmée à la remise à zéro.
 */
export function rateLimitAlert(limits, now) {
  const candidates = [
    ['fiveHour', 'Limite de 5 h', limits?.fiveHour],
    ['sevenDay', 'Limite hebdomadaire', limits?.sevenDay],
  ].filter(([, , l]) => l?.resetsAt && l.resetsAt * 1000 > now);
  // La limite atteinte est la plus remplie ; à égalité, celle de 5 h.
  const hit = candidates.sort((a, b) => (b[2].pct ?? 0) - (a[2].pct ?? 0))[0];
  if (!hit) {
    return {
      key: 'alert:ratelimit',
      ttl: 3600,
      title: "Limite d'utilisation atteinte",
      message: 'Toutes tes sessions Claude Code sont en pause jusqu’à la remise à zéro de ta limite.',
      priority: 4,
    };
  }
  const [kind, label, l] = hit;
  const resetMs = l.resetsAt * 1000;
  return {
    key: `alert:ratelimit:${l.resetsAt}`,
    ttl: 8 * 24 * 3600,
    title: `${label} atteinte`,
    message: `Toutes tes sessions Claude Code sont en pause.\nReprise possible ${resumeAt(resetMs, now)}.`,
    priority: 4,
    followUp: {
      key: kind === 'fiveHour' ? `alert:reset:${l.resetsAt}` : `alert:reset7:${l.resetsAt}`,
      ttl: 8 * 24 * 3600,
      title: `${label} remise à zéro`,
      message: 'Ta limite repart de zéro : tu peux relancer Claude Code.',
      priority: 3,
      delay: l.resetsAt,
    },
  };
}

/** Clé anti-doublon par défaut : le même texte n'est pas renvoyé dans les 2 minutes. */
export function dedupeKey(n) {
  let h = 0;
  for (const c of `${n.title}\n${n.message}`) h = (Math.imul(h, 31) + c.codePointAt(0)) | 0;
  return { key: n.key ?? `alert:msg:${(h >>> 0).toString(36)}`, ttl: n.ttl ?? 120 };
}

/** Nouvelle demande de validation à distance (mac/approve.sh) → notification. */
export function approvalAlert(a) {
  const lines = [a.text];
  if (a.note && a.note !== a.text) lines.push(a.note);
  lines.push(a.danger ? 'Commande sensible : seul le Mac peut l’autoriser.' : 'Réponds depuis Claude Pulse ou la Live Activity.');
  return { title: `${a.project} · Autoriser : ${toolAction(a.tool)} ?`, message: lines.join('\n'), priority: 5 };
}

export const LIMIT_ALERT_PCT = 80;

/**
 * Relevé des limites → alertes : passage de 80 % de la limite 5 h, et remise à zéro programmée
 * (seulement si la fenêtre a dépassé 80 %, sinon elle n'intéresse personne).
 * Renvoie des alertes avec une clé unique par fenêtre, pour ne jamais les envoyer deux fois.
 */
export function limitAlerts(fiveHour, now = Date.now()) {
  if (!fiveHour || !(fiveHour.pct >= LIMIT_ALERT_PCT) || !fiveHour.resetsAt) return [];
  const resetMs = fiveHour.resetsAt * 1000;
  const reset = new Date(resetMs).toLocaleTimeString('fr-FR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: process.env.PULSE_TZ || 'Europe/Paris',
  });
  const pct = Math.round(fiveHour.pct);
  const left = resetMs > now ? ` (dans ${formatDuration(resetMs - now)})` : '';
  return [
    {
      key: `alert:80:${fiveHour.resetsAt}`,
      title: `Limite de 5 h utilisée à ${pct} %`,
      message: `Il te reste ${Math.max(0, 100 - pct)} % jusqu'à la remise à zéro à ${reset}${left}.`,
      priority: 4,
    },
    {
      key: `alert:reset:${fiveHour.resetsAt}`,
      title: 'Limite de 5 h remise à zéro',
      message: 'Ta limite repart de zéro : tu peux relancer Claude Code.',
      priority: 3,
      delay: fiveHour.resetsAt,
    },
  ];
}
