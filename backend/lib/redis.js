// Client Upstash Redis minimal via l'API REST (zéro dépendance).
// L'intégration Upstash de la Marketplace Vercel crée KV_REST_API_URL / KV_REST_API_TOKEN.

const URL_ = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;

async function call(path, body) {
  if (!URL_ || !TOKEN) throw new Error('Redis non configuré (KV_REST_API_URL / KV_REST_API_TOKEN manquants)');
  const res = await fetch(`${URL_}${path}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (!res.ok || data.error) throw new Error(`Redis: ${data.error || res.status}`);
  return data;
}

/** redis('SET', 'k', 'v', 'EX', 60) */
export async function redis(...cmd) {
  return (await call('', cmd.map(String))).result;
}

/** pipeline([['GET','a'], ['GET','b']]) -> [resA, resB] */
export async function pipeline(cmds) {
  if (cmds.length === 0) return [];
  const data = await call('/pipeline', cmds.map((c) => c.map(String)));
  return data.map((d) => {
    if (d.error) throw new Error(`Redis: ${d.error}`);
    return d.result;
  });
}

export async function getJSON(key) {
  const v = await redis('GET', key);
  return v ? JSON.parse(v) : null;
}

/** Verrou court par session : les hooks async arrivent en parallèle. */
export async function withLock(name, fn) {
  const key = `lock:${name}`;
  const id = Math.random().toString(36).slice(2);
  for (let i = 0; i < 30; i++) {
    if ((await redis('SET', key, id, 'NX', 'PX', 4000)) === 'OK') {
      try {
        return await fn();
      } finally {
        if ((await redis('GET', key)) === id) await redis('DEL', key);
      }
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  // Tant pis pour le verrou : mieux vaut un état un peu faux qu'un événement perdu.
  return fn();
}
