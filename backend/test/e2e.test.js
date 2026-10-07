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
    case 'EXISTS': return kv.has(a[0]) ? 1 : 0;
    case 'INCRBYFLOAT': { const v = Number(kv.get(a[0]) ?? 0) + Number(a[1]); kv.set(a[0], String(v)); return String(v); }
    case 'SADD': { const s = sets.get(a[0]) ?? new Set(); s.add(a[1]); sets.set(a[0], s); return 1; }
    case 'SCARD': return sets.get(a[0])?.size ?? 0;
    case 'HSET': { const h = hashes.get(a[0]) ?? new Map(); h.set(a[1], a[2]); hashes.set(a[0], h); return 1; }
    case 'HDEL': { const h = hashes.get(a[0]); a.slice(1).forEach((f) => h?.delete(f)); return 1; }
    // Comme Upstash : tableau plat [champ, valeur, …]
    case 'HGET': return hashes.get(a[0])?.get(a[1]) ?? null;
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

// --- Faux ntfy ---
const notifications = [];
const ntfyServer = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    notifications.push(JSON.parse(body));
    res.end('{}');
  });
});

let api;
before(async () => {
  const port = await new Promise((r) => redisServer.listen(0, '127.0.0.1', () => r(redisServer.address().port)));
  const ntfyPort = await new Promise((r) => ntfyServer.listen(0, '127.0.0.1', () => r(ntfyServer.address().port)));
  Object.assign(process.env, {
    KV_REST_API_URL: `http://127.0.0.1:${port}`,
    KV_REST_API_TOKEN: 'x',
    PULSE_TOKEN: 'secret',
    NTFY_URL: `http://127.0.0.1:${ntfyPort}`,
    NTFY_TOPIC: 'pulse-test',
  });
  api = {
    hook: (await import('../api/hook.js')).default,
    usage: (await import('../api/usage.js')).default,
    state: (await import('../api/state.js')).default,
    tokens: (await import('../api/tokens.js')).default,
    stats: (await import('../api/stats.js')).default,
    session: (await import('../api/session.js')).default,
    approval: (await import('../api/approval.js')).default,
    decide: (await import('../api/decide.js')).default,
    remote: (await import('../api/remote.js')).default,
  };
});
after(() => {
  redisServer.close();
  ntfyServer.close();
});

function call(handler, method, body, token = 'secret', query = {}) {
  return new Promise((resolve) => {
    const res = {
      code: 200,
      status(c) { this.code = c; return this; },
      setHeader() {},
      json(data) { resolve({ status: this.code, data }); },
    };
    handler({ method, headers: { authorization: `Bearer ${token}` }, body, query }, res);
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
  assert.equal(commands.length, 7, 'une lecture = 7 commandes Redis');
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

test('tokens envoyés par le Mac, puis statistiques', async () => {
  const day = (await import('../lib/store.js')).day(Date.now());
  const sessions = [
    { sid: 'a', days: { [day]: { 'claude-opus-5-5': [1000, 2000, 0, 0, 1_000_000] } } },
    { sid: 'b', days: { [day]: { 'claude-sonnet-4-5-20250929': [1_000_000, 0, 0, 0, 0] } } },
  ];
  assert.equal((await call(api.tokens, 'POST', { sessions })).status, 200);
  // Renvoyer la même session ne compte pas double.
  await call(api.tokens, 'POST', { sessions: [sessions[0]] });
  const st = (await call(api.stats, 'GET')).data;
  assert.equal(st.sessions, 2);
  assert.equal(st.totals.tokens, 2_003_000);
  // Opus 5.5 : 1000×4 + 2000×20 + 1 M×0,20 = 0,244 $ ; Sonnet 4.5 : 1 M×3 = 3 $
  assert.equal(st.totals.costUsd, 3.24);
  assert.equal(st.periods.today.costUsd, 3.24);
  assert.equal(st.days.length, 30);
  assert.equal(st.days.at(-1).day, day);
  assert.deepEqual(st.models.map((m) => m.model), ['Sonnet 4.5', 'Opus 5.5']);
  assert.equal((await call(api.tokens, 'POST', { sessions: [] })).status, 400);
});

test('vue détaillée d’une session', async () => {
  const sid = 'detail-1';
  await call(api.hook, 'POST', { e: 'UserPromptSubmit', sid, project: 'App' });
  await call(api.hook, 'POST', { e: 'PreToolUse', sid, tool: 'Agent', detail: 'Audit sécurité' });
  await call(api.hook, 'POST', { e: 'SubagentStart', sid, agentId: 'x', agentType: 'general-purpose' });
  const day = (await import('../lib/store.js')).day(Date.now());
  await call(api.tokens, 'POST', { sessions: [{ sid, days: { [day]: { 'claude-opus-5-5': [0, 1_000_000, 0, 0, 0] } } }] });
  const r = await call(api.session, 'GET', null, 'secret', { sid });
  assert.equal(r.status, 200);
  assert.equal(r.data.session.project, 'App');
  assert.equal(r.data.agents[0].description, 'Audit sécurité');
  assert.equal(r.data.tokens.costUsd, 20);
  assert.equal((await call(api.session, 'GET', null, 'secret', { sid: 'inconnue' })).status, 404);
  assert.equal((await call(api.session, 'GET', null, 'secret', {})).status, 400);
});

test('ntfy : validation demandée, fin de tâche, limite 80 % et remise à zéro (une seule fois)', async () => {
  notifications.length = 0;
  const sid = 'ntfy-1';
  await call(api.hook, 'POST', { e: 'UserPromptSubmit', sid, project: 'App' });
  await call(api.hook, 'POST', { e: 'Notification', sid, ntype: 'permission_prompt', message: 'Claude needs your permission to use Bash' });
  assert.equal(notifications.at(-1).title, 'App attend ta validation');
  assert.equal(notifications.at(-1).topic, 'pulse-test');

  const resetsAt = Math.floor(Date.now() / 1000) + 3600;
  const reading = { sid, costUsd: 1, contextPct: 10, fiveHour: { pct: 82, resetsAt } };
  await call(api.usage, 'POST', reading);
  await call(api.usage, 'POST', { ...reading, fiveHour: { pct: 85, resetsAt } });
  const limit = notifications.filter((n) => n.title.startsWith('Limite'));
  assert.deepEqual(limit.map((n) => n.title), ['Limite 5 h à 82 %', 'Limite 5 h remise à zéro']);
  assert.equal(limit[1].delay, String(resetsAt), 'remise à zéro programmée chez ntfy');

  const st = (await call(api.state, 'GET')).data;
  assert.equal(st.ntfy, true);
  assert.ok(st.limits.updatedAt > 0, 'âge du relevé des limites');
});

test('validation à distance : éteinte, allumée, garde-fou, décision', async () => {
  const ask = (input) => call(api.approval, 'POST', { sid: 's', project: 'App', tool: 'Bash', input });
  assert.equal((await ask({ command: 'npm test' })).data.remote, false, 'éteinte par défaut');

  assert.equal((await call(api.remote, 'POST', { on: true })).data.on, true);
  const ok = (await ask({ command: 'npm test', description: 'Run tests' })).data;
  const risky = (await ask({ command: 'rm -rf build' })).data;
  assert.equal(ok.remote, true);

  let st = (await call(api.state, 'GET')).data;
  assert.equal(st.remote, true);
  assert.deepEqual(st.approvals.map((a) => [a.text, a.danger]), [['npm test', false], ['rm -rf build', true]]);

  // Commande sensible : refus possible, autorisation impossible depuis le téléphone.
  assert.equal((await call(api.decide, 'POST', { id: risky.id, allow: true })).status, 403);
  assert.equal((await call(api.decide, 'POST', { id: risky.id, allow: false })).data.decision, 'deny');

  assert.equal((await call(api.approval, 'GET', null, 'secret', { id: ok.id })).data.decision, 'pending');
  assert.equal((await call(api.decide, 'POST', { id: ok.id, allow: true })).data.decision, 'allow');
  assert.equal((await call(api.approval, 'GET', null, 'secret', { id: ok.id })).data.decision, 'allow');
  assert.equal((await call(api.decide, 'POST', { id: ok.id, allow: false })).status, 409, 'une seule réponse');

  st = (await call(api.state, 'GET')).data;
  assert.equal(st.approvals.length, 0);
  await call(api.remote, 'POST', { on: false });
  assert.equal((await ask({ command: 'ls' })).data.remote, false);
});
