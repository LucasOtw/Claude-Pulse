// Tarifs publics de l'API Claude, en dollars par million de tokens (relevés en septembre 2026).
// Écriture du cache : 1,25 × l'entrée (5 min) ou 2 × (1 h). Lecture du cache : propre à chaque modèle.
// Plus le préfixe est précis, plus il est prioritaire (l'ordre compte).
const TABLE = [
  ['claude-fable-5-1', 10, 50, 0.25],
  ['claude-mythos-5-1', 10, 50, 0.25],
  ['claude-fable-5', 10, 50, 1.0],
  ['claude-mythos-5', 10, 50, 1.0],
  ['claude-opus-5-5', 4, 20, 0.2],
  ['claude-opus-5', 5, 25, 0.5],
  ['claude-opus-4-8', 5, 25, 0.5],
  ['claude-opus-4-7', 5, 25, 0.5],
  ['claude-opus-4-6', 5, 25, 0.5],
  ['claude-opus-4-5', 5, 25, 0.5],
  ['claude-opus-4', 15, 75, 1.5], // Opus 4 / 4.1
  ['claude-sonnet-5-5', 2, 10, 0.2],
  ['claude-sonnet-5', 2, 10, 0.2],
  ['claude-sonnet-4', 3, 15, 0.3], // Sonnet 4 / 4.5 / 4.6
  ['claude-3-7-sonnet', 3, 15, 0.3],
  ['claude-haiku-4-5', 1, 5, 0.1],
  ['claude-3-5-haiku', 0.8, 4, 0.08],
];

// Modèle inconnu : on se rabat sur la famille.
const FAMILIES = [
  ['fable', 10, 50, 0.25],
  ['mythos', 10, 50, 0.25],
  ['opus', 5, 25, 0.5],
  ['sonnet', 3, 15, 0.3],
  ['haiku', 1, 5, 0.1],
];

export function priceFor(model) {
  const m = String(model || '').toLowerCase();
  const hit = TABLE.find(([prefix]) => m.startsWith(prefix)) ?? FAMILIES.find(([family]) => m.includes(family));
  if (!hit) return null;
  const [, input, output, cacheRead] = hit;
  return { input, output, cacheWrite5m: input * 1.25, cacheWrite1h: input * 2, cacheRead };
}

/** tokens = [entrée, sortie, écriture cache 5 min, écriture cache 1 h, lecture cache] */
export function costOf(model, tokens) {
  const p = priceFor(model);
  if (!p) return 0;
  const [i, o, w5, w1, r] = tokens;
  return (i * p.input + o * p.output + w5 * p.cacheWrite5m + w1 * p.cacheWrite1h + r * p.cacheRead) / 1e6;
}

/** « claude-opus-5-5 » → « Opus 5.5 » */
export function modelLabel(model) {
  const m = /claude-(?:(\d)-(\d)-)?([a-z]+)-?(\d+)?(?:-(\d+))?/.exec(String(model || ''));
  if (!m) return model || 'Inconnu';
  const [, oldMaj, oldMin, family, maj, min] = m;
  const name = family.charAt(0).toUpperCase() + family.slice(1);
  if (oldMaj) return `${name} ${oldMaj}.${oldMin}`;
  if (!maj) return name;
  return min && min.length <= 2 ? `${name} ${maj}.${min}` : `${name} ${maj}`;
}
