// Bout en bout : endpoints Vercel + faux Upstash (HTTP) + faux APNs (HTTP/2 en clair).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import http2 from 'node:http2';
import crypto from 'node:crypto';

// --- Faux Upstash Redis (seulement les commandes utilisées) ---
const kv = new Map();
const zsets = new Map();
const sets = new Map();
function exec([cmd, ...a]) {
  switch (cmd.toUpperCase()) {
    case 'GET': return kv.get(a[0]) ?? null;
    case 'SET': {
      if (a.includes('NX') && kv.has(a[0])) return null;
      kv.set(a[0], a[1]);
      return 'OK';
    }
    case 'DEL': return kv.delete(a[0]) ? 1 : 0;
    case 'MGET': return a.map((k) => kv.get(k) ?? null);
    case 'EXPIRE': return 1;
    case 'INCRBYFLOAT': { const v = Number(kv.get(a[0]) ?? 0) + Number(a[1]); kv.set(a[0], String(v)); return String(v); }
    case 'SADD': { const s = sets.get(a[0]) ?? new Set(); s.add(a[1]); sets.set(a[0], s); return 1; }
    case 'SCARD': return sets.get(a[0])?.size ?? 0;
    case 'ZADD': {
      const args = a.slice(1).filter((x) => !['NX', 'XX', 'GT', 'LT', 'CH'].includes(x));
      const z = zsets.get(a[0]) ?? new Map();
      if (!a.includes('GT') || !(z.get(args[1]) > Number(args[0]))) z.set(args[1], Number(args[0]));
      zsets.set(a[0], z);
      return 1;
    }
    case 'ZREMRANGEBYSCORE': return 0;
    case 'ZREVRANGEBYSCORE': {
      const z = zsets.get(a[0]) ?? new Map();
      return [...z.entries()].filter(([, sc]) => sc >= Number(a[2])).sort((x, y) => y[1] - x[1]).map(([m]) => m);
    }
    default: throw new Error(`commande non simulée : ${cmd}`);
  }
}
const redisServer = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    const parsed = JSON.parse(body);
    const out = req.url === '/pipeline' ? parsed.map((c) => ({ result: exec(c) })) : { result: exec(parsed) };
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(out));
  });
});

// --- Faux APNs ---
const pushes = [];
const apnsServer = http2.createServer();
apnsServer.on('stream', (stream, headers) => {
  let body = '';
  stream.on('data', (c) => (body += c));
  stream.on('end', () => {
    pushes.push({ headers, payload: JSON.parse(body) });
    stream.respond({ ':status': 200 });
    stream.end();
  });
});

const listen = (srv) => new Promise((r) => srv.listen(0, '127.0.0.1', () => r(srv.address().port)));
let api;

before(async () => {
  const [rp, ap] = await Promise.all([listen(redisServer), listen(apnsServer)]);
  const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  Object.assign(process.env, {
    KV_REST_API_URL: `http://127.0.0.1:${rp}`,
    KV_REST_API_TOKEN: 'x',
    APNS_HOST: `http://127.0.0.1:${ap}`,
    APNS_TEAM_ID: 'TEAM123456',
    APNS_KEY_ID: 'KEY1234567',
    APNS_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    APNS_BUNDLE_ID: 'com.example.pulse',
    PULSE_TOKEN: 'secret',
  });
  api = {
    hook: (await import('../api/hook.js')).default,
    usage: (await import('../api/usage.js')).default,
    device: (await import('../api/device.js')).default,
    state: (await import('../api/state.js')).default,
  };
});
after(() => {
  redisServer.close();
  apnsServer.close();
});

function call(handler, method, body, token = 'secret') {
  return new Promise((resolve) => {
    const res = {
      code: 200,
      headers: {},
      status(c) { this.code = c; return this; },
      setHeader(k, v) { this.headers[k] = v; },
      json(data) { resolve({ status: this.code, data }); },
    };
    handler({ method, headers: { authorization: `Bearer ${token}` }, body }, res);
  });
}

test('refuse un mauvais jeton', async () => {
  const r = await call(api.hook, 'POST', { sid: 'a', e: 'Stop' }, 'nope');
  assert.equal(r.status, 401);
});

test('scénario complet : usage, démarrage, jeton d’activité, fin', async () => {
  const sid = 'sess-1';
  // L'app enregistre son jeton push-to-start.
  assert.equal((await call(api.device, 'POST', { kind: 'start', token: 'aa'.repeat(32) })).status, 200);

  // La status line envoie l'usage.
  const resetsAt = Math.floor(Date.now() / 1000) + 3600;
  await call(api.usage, 'POST', {
    sid, project: 'Studio_Granit', model: 'Opus', costUsd: 1.5, contextPct: 42,
    fiveHour: { pct: 23.5, resetsAt }, sevenDay: { pct: 41.2, resetsAt: resetsAt + 86400 },
  });

  // Un prompt, puis une notification de permission : démarrage immédiat.
  await call(api.hook, 'POST', { e: 'UserPromptSubmit', sid, project: 'Studio_Granit' });
  const r = await call(api.hook, 'POST', { e: 'Notification', sid, ntype: 'permission_prompt', message: 'Claude veut lancer Bash' });
  assert.equal(r.data.action, 'start');
  assert.equal(r.data.push.start.status, 200);

  const start = pushes.at(-1);
  assert.equal(start.headers[':path'], `/3/device/${'aa'.repeat(32)}`);
  assert.equal(start.headers['apns-push-type'], 'liveactivity');
  assert.equal(start.headers['apns-topic'], 'com.example.pulse.push-type.liveactivity');
  assert.match(start.headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.equal(start.payload.aps.event, 'start');
  assert.equal(start.payload.aps['attributes-type'], 'PulseAttributes');
  assert.equal(start.payload.aps.attributes.sessionId, sid);
  assert.equal(start.payload.aps['content-state'].status, 'waiting');
  assert.equal(start.payload.aps['content-state'].costUsd, 1.5);
  assert.equal(start.payload.aps['content-state'].fiveHourPct, 24);

  // Fin avant que l'iPhone ait envoyé le jeton de l'activité : fin différée…
  const stop = await call(api.hook, 'POST', { e: 'Stop', sid, bg: [] });
  assert.match(stop.data.push.skipped, /différée/);

  // …puis l'iPhone envoie le jeton : on termine l'activité tout de suite.
  const n = pushes.length;
  const dev = await call(api.device, 'POST', { kind: 'activity', sid, token: 'bb'.repeat(32) });
  assert.equal(dev.data.push.end.status, 200);
  assert.equal(pushes.length, n + 1);
  assert.equal(pushes.at(-1).payload.aps.event, 'end');
  assert.ok(pushes.at(-1).payload.aps['dismissal-date'] > pushes.at(-1).payload.aps.timestamp);

  // Ce que lit le widget.
  const st = await call(api.state, 'GET');
  assert.equal(st.data.limits.fiveHour.pct, 23.5);
  assert.equal(st.data.today.costUsd, 1.5);
  assert.equal(st.data.today.sessions, 1);
  assert.equal(st.data.sessions[0].status, 'done');
  assert.equal(st.data.sessions[0].project, 'Studio_Granit');
  assert.equal(st.data.pushReady, true);

  // Le coût du jour n'additionne que les hausses.
  await call(api.usage, 'POST', { sid, costUsd: 2.25, contextPct: 50 });
  assert.equal((await call(api.state, 'GET')).data.today.costUsd, 2.25);
});
