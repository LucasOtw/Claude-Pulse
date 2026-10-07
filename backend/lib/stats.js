// Agrège les tokens lus dans les transcripts Claude Code (par session, par jour, par modèle).
import { costOf, modelLabel } from './pricing.js';

const ZERO = () => [0, 0, 0, 0, 0];
const add = (a, b) => a.map((v, i) => v + (b[i] || 0));
const total = (t) => t.reduce((s, v) => s + v, 0);

function shiftDay(day, delta) {
  const d = new Date(`${day}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
}

/**
 * @param sessions { sid: { day: { model: [in, out, w5, w1, read] } } }
 * @param today    « 2026-10-07 » dans le fuseau de l'utilisateur
 */
export function buildStats(sessions, today) {
  const byDay = new Map(); // day -> { tokens, cost }
  const byModel = new Map(); // model -> { tokens, cost }
  let sum = ZERO();
  let cost = 0;
  let since = null;

  const weekStart = shiftDay(today, -6);
  const byProject = new Map(); // projet -> { week, total }
  for (const entry of Object.values(sessions)) {
    const { project, days } = entry && entry.days ? entry : { project: null, days: entry };
    const name = project || 'Autre';
    for (const [day, models] of Object.entries(days || {})) {
      for (const [model, raw] of Object.entries(models || {})) {
        const t = ZERO().map((_, i) => Number(raw?.[i]) || 0);
        const c = costOf(model, t);
        sum = add(sum, t);
        cost += c;
        if (!since || day < since) since = day;
        const d = byDay.get(day) ?? { tokens: ZERO(), cost: 0 };
        byDay.set(day, { tokens: add(d.tokens, t), cost: d.cost + c });
        const m = byModel.get(model) ?? { tokens: ZERO(), cost: 0 };
        byModel.set(model, { tokens: add(m.tokens, t), cost: m.cost + c });
        const p = byProject.get(name) ?? { project: name, weekTokens: 0, weekCostUsd: 0, tokens: 0, costUsd: 0 };
        p.tokens += total(t);
        p.costUsd += c;
        if (day >= weekStart && day <= today) {
          p.weekTokens += total(t);
          p.weekCostUsd += c;
        }
        byProject.set(name, p);
      }
    }
  }

  const period = (n) => {
    let tokens = 0;
    let c = 0;
    for (let i = 0; i < n; i++) {
      const d = byDay.get(shiftDay(today, -i));
      if (d) {
        tokens += total(d.tokens);
        c += d.cost;
      }
    }
    return { tokens, costUsd: round2(c) };
  };

  const days = [];
  for (let i = 29; i >= 0; i--) {
    const day = shiftDay(today, -i);
    const d = byDay.get(day);
    days.push({ day, tokens: d ? total(d.tokens) : 0, costUsd: d ? round2(d.cost) : 0 });
  }

  // Plusieurs identifiants peuvent désigner le même modèle (suffixes de date) : on regroupe par libellé.
  const models = new Map();
  for (const [model, v] of byModel) {
    const label = modelLabel(model);
    const m = models.get(label) ?? { model: label, tokens: 0, costUsd: 0 };
    m.tokens += total(v.tokens);
    m.costUsd += v.cost;
    models.set(label, m);
  }

  return {
    since,
    totals: {
      tokens: total(sum),
      input: sum[0],
      output: sum[1],
      cacheWrite: sum[2] + sum[3],
      cacheRead: sum[4],
      costUsd: round2(cost),
    },
    periods: { today: period(1), week: period(7), month: period(30) },
    days,
    models: [...models.values()]
      .map((m) => ({ ...m, costUsd: round2(m.costUsd) }))
      .sort((a, b) => b.costUsd - a.costUsd),
    projects: [...byProject.values()]
      .map((p) => ({ ...p, weekCostUsd: round2(p.weekCostUsd), costUsd: round2(p.costUsd) }))
      .sort((a, b) => b.weekTokens - a.weekTokens || b.tokens - a.tokens),
    sessions: Object.keys(sessions).length,
  };
}

const round2 = (n) => Math.round(n * 100) / 100;
