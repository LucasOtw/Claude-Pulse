import { redis, pipeline, getJSON } from './redis.js';

const TZ = process.env.PULSE_TZ || 'Europe/Paris';
const SESSION_TTL = 2 * 24 * 3600;
const ACTIVE_WINDOW_MS = 6 * 3600 * 1000;

export const day = (now) => new Intl.DateTimeFormat('sv-SE', { timeZone: TZ }).format(new Date(now));

// L'usage (coût, contexte, modèle) vit dans sa propre clé u:<sid>, écrite par la status line
// sans verrou ; on le fusionne dans la session à la lecture.
const merge = (rawSession, rawUsage) => {
  if (!rawSession) return null;
  const s = JSON.parse(rawSession);
  if (rawUsage) {
    const u = JSON.parse(rawUsage);
    s.usage = { costUsd: u.costUsd, contextPct: u.contextPct, model: u.model };
    if (!s.title && u.title) s.title = u.title;
  }
  return s;
};

export async function loadSession(sid) {
  const [raw, usage] = await pipeline([
    ['GET', `s:${sid}`],
    ['GET', `u:${sid}`],
  ]);
  return merge(raw, usage);
}

export async function saveSession(s, now) {
  const { usage, ...rest } = s;
  await pipeline([
    ['SET', `s:${s.sid}`, JSON.stringify(rest), 'EX', SESSION_TTL],
    ['ZADD', 'sessions', now, s.sid],
    ['ZREMRANGEBYSCORE', 'sessions', '-inf', now - SESSION_TTL * 1000],
  ]);
}

export async function listSessions(now) {
  const ids = await redis('ZREVRANGEBYSCORE', 'sessions', '+inf', now - ACTIVE_WINDOW_MS, 'LIMIT', 0, 10);
  if (!ids.length) return [];
  const raw = await redis('MGET', ...ids.flatMap((id) => [`s:${id}`, `u:${id}`]));
  const out = [];
  for (let i = 0; i < raw.length; i += 2) {
    const s = merge(raw[i], raw[i + 1]);
    if (s) out.push(s);
  }
  return out;
}

export const getUsage = (sid) => getJSON(`u:${sid}`);

/**
 * Enregistre un relevé de la status line en une seule requête :
 * usage de la session, limites du compte, coût du jour, session créée si inconnue.
 */
export async function recordUsage({ sid, usage, limits, costDelta, newSession }, now) {
  const d = day(now);
  const DAY_TTL = 40 * 24 * 3600;
  const cmds = [
    ['SET', `u:${sid}`, JSON.stringify(usage), 'EX', SESSION_TTL],
    ['SET', `s:${sid}`, JSON.stringify(newSession), 'NX', 'EX', SESSION_TTL],
    ['ZADD', 'sessions', 'GT', now, sid],
    ['SADD', `day:${d}:sessions`, sid],
    ['EXPIRE', `day:${d}:sessions`, DAY_TTL],
  ];
  if (limits) cmds.push(['SET', 'limits', JSON.stringify(limits), 'EX', 8 * 24 * 3600]);
  if (costDelta > 0) cmds.push(['INCRBYFLOAT', `day:${d}:cost`, costDelta.toFixed(6)], ['EXPIRE', `day:${d}:cost`, DAY_TTL]);
  await pipeline(cmds);
}

export const getLimits = () => getJSON('limits');

export async function today(now) {
  const d = day(now);
  const [cost, sessions] = await pipeline([
    ['GET', `day:${d}:cost`],
    ['SCARD', `day:${d}:sessions`],
  ]);
  return { costUsd: Math.round(Number(cost || 0) * 100) / 100, sessions: Number(sessions || 0) };
}

export const getStartToken = () => redis('GET', 'tok:start');
export const setStartToken = (t) => redis('SET', 'tok:start', t);
export const delStartToken = () => redis('DEL', 'tok:start');
export const getActivityToken = (sid) => redis('GET', `tok:la:${sid}`);
export const setActivityToken = (sid, t) => redis('SET', `tok:la:${sid}`, t, 'EX', 12 * 3600);
export const delActivityToken = (sid) => redis('DEL', `tok:la:${sid}`);
