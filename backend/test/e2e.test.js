// Bout en bout : endpoints Vercel + faux Upstash (HTTP).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

// --- Faux Upstash Redis (seulement les commandes utilisées) ---
const kv = new Map();
const hashes = new Map();
const sets = new Map();
const commands = [];
function exec([cmd, ...a]) {
  commands.push(cmd);
  switch (cmd.toUpperCase()) {
    case 'GET': return kv.get(a[0]) ?? null;
    case 'SET': {
      if (a.includes('NX') && kv.has(a[0])) return null;
      kv.set(a[0], a[1]);
      return 'OK';
    }
    case 'DEL': return kv.delete(a[0]) ? 1 : 0;
    case 'EXPIRE': return 1;
    case 'INCRBYFLOAT': { const v = Number(kv.get(a[0]) ?? 0) + Number(a[1]); kv.set(a[0], String(v)); return String(v); }
    case 'SADD': { const s = sets.get(a[0]) ?? new Set(); s.add(a[1]); sets.set(a[0], s); return 1; }
    case 'SCARD': return sets.get(a[0])?.size ?? 0;
    case 'HSET': { const h = hashes.get(a[0]) ?? new Map(); h.set(a[1], a[2]); hashes.set(a[0], h); return 1; }
    case 'HDEL': { const h = hashes.get(a[0]); a.slice(1).forEach((f) => h?.delete(f)); return 1; }
    // Comme Upstash : tableau plat [champ, valeur, …]
    case 'HGETALL': return [...(hashes.get(a[0]) ?? new Map()).entries()].flat();
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

let api;
before(async () => {
  const port = await new Promise((r) => redisServer.listen(0, '127.0.0.1', () => r(redisServer.address().port)));
  Object.assign(process.env, { KV_REST_API_URL: `http://127.0.0.1:${port}`, KV_REST_API_TOKEN: 'x', PULSE_TOKEN: 'secret' });
  api = {
    hook: (await import('../api/hook.js')).default,
    usage: (await import('../api/usage.js')).default,
    state: (await import('../api/state.js')).default,
    test: (await import('../api/test.js')).default,
  };
});
after(() => redisServer.close());

function call(handler, method, body, token = 'secret') {
  return new Promise((resolve) => {
    const res = {
      code: 200,
      status(c) { this.code = c; return this; },
      setHeader() {},
      json(data) { resolve({ status: this.code, data }); },
    };
    handler({ method, headers: { authorization: `Bearer ${token}` }, body }, res);
  });
}

test('refuse un mauvais jeton', async () => {
  assert.equal((await call(api.hook, 'POST', { sid: 'a', e: 'Stop' }, 'nope')).status, 401);
  assert.equal((await call(api.state, 'GET', null, 'nope')).status, 401);
});

test('scénario complet : usage, hooks, lecture par l’iPhone', async () => {
  const sid = 'sess-1';
  const resetsAt = Math.floor(Date.now() / 1000) + 3600;
  await call(api.usage, 'POST', {
    sid, project: 'Studio_Granit', model: 'Opus', costUsd: 1.5, contextPct: 42, title: 'Refonte accueil', durationMs: 20_000,
    fiveHour: { pct: 23.5, resetsAt }, sevenDay: { pct: 41.2, resetsAt: resetsAt - 7200 }, // 7 j déjà réinitialisé
  });
  await call(api.hook, 'POST', { e: 'UserPromptSubmit', sid, project: 'Studio_Granit' });
  await call(api.hook, 'POST', { e: 'PreToolUse', sid, tool: 'TodoWrite', todos: [{ c: 'A', s: 'completed' }, { c: 'Code', s: 'in_progress' }] });
  const r = await call(api.hook, 'POST', { e: 'Notification', sid, ntype: 'permission_prompt', message: 'Claude needs your permission to use Bash' });
  assert.equal(r.data.status, 'waiting');

  commands.length = 0;
  const st = await call(api.state, 'GET');
  assert.equal(commands.length, 5, 'une lecture = 5 commandes Redis');
  assert.equal(st.data.limits.fiveHour.pct, 23.5);
  assert.equal(st.data.limits.sevenDay, null);
  assert.deepEqual(st.data.today, { costUsd: 1.5, sessions: 1 });
  const s = st.data.sessions[0];
  assert.equal(s.project, 'Studio_Granit');
  assert.equal(s.title, 'Refonte accueil');
  assert.equal(s.status, 'waiting');
  assert.equal(s.activity, 'Veut utiliser Bash : à valider');
  assert.equal(s.stepsDone, 1);
  assert.equal(s.stepsTotal, 2);
  assert.equal(s.costUsd, 1.5);

  await call(api.hook, 'POST', { e: 'Stop', sid, bg: [] });
  await call(api.usage, 'POST', { sid, costUsd: 2.25, contextPct: 50 });
  const st2 = await call(api.state, 'GET');
  assert.equal(st2.data.sessions[0].status, 'done');
  assert.equal(st2.data.sessions[0].costUsd, 2.25);
  assert.equal(st2.data.today.costUsd, 2.25, 'le coût du jour n’additionne que les hausses');
});

test('une session déjà ouverte avant l’installation ne gonfle pas le coût du jour', async () => {
  const before = (await call(api.state, 'GET')).data.today.costUsd;
  // Session ouverte depuis 3 h, 790 $ cumulés : son premier relevé n'est pas compté…
  await call(api.usage, 'POST', { sid: 'old', costUsd: 790, contextPct: 41, durationMs: 3 * 3600 * 1000 });
  assert.equal((await call(api.state, 'GET')).data.today.costUsd, before);
  // …mais ce qu'elle dépense ensuite l'est.
  await call(api.usage, 'POST', { sid: 'old', costUsd: 791.5, contextPct: 42, durationMs: 3 * 3600 * 1000 + 60_000 });
  assert.equal((await call(api.state, 'GET')).data.today.costUsd, before + 1.5);
  // Ancien statusline.sh sans durée : même prudence.
  await call(api.usage, 'POST', { sid: 'legacy', costUsd: 50 });
  assert.equal((await call(api.state, 'GET')).data.today.costUsd, before + 1.5);
});

test('démo depuis l’app', async () => {
  await call(api.test, 'POST', { step: 'start' });
  let demo = (await call(api.state, 'GET')).data.sessions.find((s) => s.sid === 'demo');
  assert.equal(demo.status, 'running');
  assert.equal(demo.duration, '1 min');
  await call(api.test, 'POST', { step: 'waiting' });
  demo = (await call(api.state, 'GET')).data.sessions.find((s) => s.sid === 'demo');
  assert.equal(demo.status, 'waiting');
  await call(api.test, 'POST', { step: 'end' });
  demo = (await call(api.state, 'GET')).data.sessions.find((s) => s.sid === 'demo');
  assert.equal(demo.status, 'done');
});
