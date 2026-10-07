import { redis, pipeline, getJSON } from './redis.js';
import { snapshot } from './state.js';

const TZ = process.env.PULSE_TZ || 'Europe/Paris';
const SESSION_TTL = 2 * 24 * 3600;
const DAY_TTL = 40 * 24 * 3600;

// Clés Redis :
//   s:<sid>     état complet d'une session (machine à états, sous verrou)
//   u:<sid>     dernier relevé de la status line (coût, contexte, modèle)
//   live        hash sid -> snapshot() de chaque session  } lus ensemble par GET /api/state,
//   liveu       hash sid -> usage de chaque session       } en une seule requête
//   limits      limites 5 h / 7 jours du compte
//   day:<date>:cost / day:<date>:sessions

export const day = (now) => new Intl.DateTimeFormat('sv-SE', { timeZone: TZ }).format(new Date(now));

export async function loadSession(sid) {
  const [raw, usage] = await pipeline([
    ['GET', `s:${sid}`],
    ['GET', `u:${sid}`],
  ]);
  if (!raw) return null;
  const s = JSON.parse(raw);
  if (usage) s.usage = JSON.parse(usage);
  return s;
}

export async function saveSession(s) {
  const { usage, ...rest } = s;
  await pipeline([
    ['SET', `s:${s.sid}`, JSON.stringify(rest), 'EX', SESSION_TTL],
    ['HSET', 'live', s.sid, JSON.stringify(snapshot(s))],
  ]);
}

export const getUsage = (sid) => getJSON(`u:${sid}`);

/** Enregistre un relevé de la status line : usage de la session, limites du compte, coût du jour. */
export async function recordUsage({ sid, usage, limits, costDelta }, now) {
  const d = day(now);
  const cmds = [
    ['SET', `u:${sid}`, JSON.stringify(usage), 'EX', SESSION_TTL],
    ['HSET', 'liveu', sid, JSON.stringify(usage)],
    ['SADD', `day:${d}:sessions`, sid],
    ['EXPIRE', `day:${d}:sessions`, DAY_TTL],
  ];
  if (limits) cmds.push(['SET', 'limits', JSON.stringify(limits), 'EX', 8 * 24 * 3600]);
  if (costDelta > 0) cmds.push(['INCRBYFLOAT', `day:${d}:cost`, costDelta.toFixed(6)], ['EXPIRE', `day:${d}:cost`, DAY_TTL]);
  await pipeline(cmds);
}

// Upstash renvoie HGETALL sous forme de tableau plat [champ, valeur, champ, valeur…].
const hashToObject = (h) => {
  if (!h) return {};
  if (!Array.isArray(h)) return h;
  const o = {};
  for (let i = 0; i < h.length; i += 2) o[h[i]] = h[i + 1];
  return o;
};

/** Tout ce que lisent l'app et le widget, en une seule requête Redis (5 commandes). */
export async function readLive(now) {
  const d = day(now);
  const [live, liveu, limits, cost, sessions] = await pipeline([
    ['HGETALL', 'live'],
    ['HGETALL', 'liveu'],
    ['GET', 'limits'],
    ['GET', `day:${d}:cost`],
    ['SCARD', `day:${d}:sessions`],
  ]);
  const usage = hashToObject(liveu);
  const snaps = Object.values(hashToObject(live)).map((v) => JSON.parse(v));
  return {
    snaps,
    usage: Object.fromEntries(Object.entries(usage).map(([k, v]) => [k, JSON.parse(v)])),
    limits: limits ? JSON.parse(limits) : null,
    today: { costUsd: Math.round(Number(cost || 0) * 100) / 100, sessions: Number(sessions || 0) },
  };
}

/** Oublie les sessions trop anciennes des hashes « live ». */
export async function prune(sids) {
  if (sids.length === 0) return;
  await pipeline([
    ['HDEL', 'live', ...sids],
    ['HDEL', 'liveu', ...sids],
  ]);
}

// Tokens par session (hash « tokens » : sid -> { jour: { modèle: [entrée, sortie, cache 5 min, cache 1 h, lecture] } }).
export async function saveTokens(sessions) {
  await pipeline(sessions.map((s) => ['HSET', 'tokens', s.sid, JSON.stringify(s.days)]));
}

export async function readTokens() {
  const raw = hashToObject(await redis('HGETALL', 'tokens'));
  const out = {};
  for (const [sid, v] of Object.entries(raw)) {
    try {
      out[sid] = JSON.parse(v);
    } catch {}
  }
  return out;
}

export async function readSessionTokens(sid) {
  const v = await redis('HGET', 'tokens', sid);
  try {
    return v ? JSON.parse(v) : null;
  } catch {
    return null;
  }
}
