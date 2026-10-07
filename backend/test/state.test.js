import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyEvent, progress, formatDuration, snapshot, publicSession, toolLabel, sessionDetail, SILENT_AFTER_MS } from '../lib/state.js';

const SID = 's1';
const T0 = 1_700_000_000_000;
const sec = (n) => T0 + n * 1000;

// Rejoue une suite d'événements [secondes, event].
function play(steps, initial = null) {
  let s = initial;
  for (const [t, ev] of steps) s = applyEvent(s, { sid: SID, project: 'demo', ...ev }, sec(t));
  return s;
}

test('cycle complet : prompt, outils, fin', () => {
  let s = play([[0, { e: 'UserPromptSubmit' }]]);
  assert.equal(s.status, 'running');
  assert.equal(s.activity, 'Réfléchit…');
  s = play([[10, { e: 'PreToolUse', tool: 'Bash' }]], s);
  assert.equal(s.activity, 'Exécute des commandes');
  s = play([[20, { e: 'PreToolUse', tool: 'mcp__github__create_pull_request' }]], s);
  assert.equal(s.activity, 'Utilise github');
  s = play([[300, { e: 'Stop', bg: [] }]], s);
  assert.equal(s.status, 'done');
  assert.equal(publicSession(snapshot(s), null, sec(9999)).duration, '5 min');
});

test('demande de validation, puis reprise', () => {
  let s = play([
    [0, { e: 'UserPromptSubmit' }],
    [7, { e: 'Notification', ntype: 'permission_prompt', message: 'Claude needs your permission to use Bash' }],
  ]);
  assert.equal(s.status, 'waiting');
  assert.equal(s.activity, 'Veut utiliser Bash : à valider');
  s = play([[20, { e: 'PreToolUse', tool: 'Bash' }]], s);
  assert.equal(s.status, 'running');
});

test('idle_prompt est ignoré, les autres demandes sont traduites', () => {
  const s = play([
    [0, { e: 'UserPromptSubmit' }],
    [5, { e: 'Stop', bg: [] }],
    [65, { e: 'Notification', ntype: 'idle_prompt', message: 'Claude is waiting for your input' }],
  ]);
  assert.equal(s.status, 'done');
  const s2 = play([[0, { e: 'Notification', ntype: 'elicitation_dialog', message: 'MCP server needs input' }]]);
  assert.equal(s2.activity, 'Attend ta réponse');
});

test('Stop avec un workflow en arrière-plan garde la session active', () => {
  const s = play([
    [0, { e: 'UserPromptSubmit' }],
    [5, { e: 'PreToolUse', tool: 'Workflow', workflow: { name: 'review-changes', phases: ['Review', 'Verify'] } }],
    [6, { e: 'SubagentStart', agentId: 'a1', agentType: 'general-purpose' }],
    [6, { e: 'SubagentStart', agentId: 'a2', agentType: 'general-purpose' }],
    [8, { e: 'Stop', bg: [{ type: 'workflow', status: 'running', name: 'review-changes' }] }],
    [40, { e: 'SubagentStop', agentId: 'a1', agentType: 'general-purpose' }],
  ]);
  assert.equal(s.status, 'background');
  assert.equal(s.activity, 'Workflow « review-changes » en arrière-plan');
  const snap = snapshot(s);
  assert.equal(snap.workflow, 'review-changes');
  assert.equal(snap.agents, 1);
});

test('progression : TodoWrite prioritaire, sinon TaskCreated/TaskCompleted', () => {
  const s = play([
    [0, { e: 'UserPromptSubmit' }],
    [1, { e: 'TaskCreated', taskId: '1', taskSubject: 'Analyser' }],
    [2, { e: 'TaskCreated', taskId: '2', taskSubject: 'Coder' }],
    [3, { e: 'TaskCompleted', taskId: '1', taskSubject: 'Analyser' }],
  ]);
  assert.deepEqual(progress(s), { done: 1, total: 2, current: 'Coder' });
  const s2 = play([
    [4, { e: 'PreToolUse', tool: 'TodoWrite', todos: [{ c: 'A', s: 'completed' }, { c: 'Écrit B', s: 'in_progress' }, { c: 'C', s: 'pending' }] }],
  ], s);
  assert.deepEqual(progress(s2), { done: 1, total: 3, current: 'Écrit B' });
});

test('la TodoWrite d’un sous-agent ne remplace pas celle de la session', () => {
  const s = play([
    [0, { e: 'PreToolUse', tool: 'TodoWrite', todos: [{ c: 'A', s: 'in_progress' }] }],
    [1, { e: 'PreToolUse', tool: 'TodoWrite', agentId: 'x', todos: [{ c: 'Z', s: 'completed' }] }],
  ]);
  assert.equal(progress(s).current, 'A');
});

test('StopFailure passe en erreur', () => {
  const s = play([[0, { e: 'UserPromptSubmit' }], [50, { e: 'StopFailure', error: 'rate_limit' }]]);
  assert.equal(s.status, 'error');
  assert.equal(s.activity, 'Erreur : rate_limit');
});

test('un nouveau prompt pendant une tâche ne remet pas le chrono à zéro', () => {
  const s = play([[0, { e: 'UserPromptSubmit' }], [30, { e: 'Notification', ntype: 'permission_prompt' }], [40, { e: 'UserPromptSubmit' }]]);
  assert.equal(snapshot(s).startedAt, Math.floor(sec(0) / 1000));
  const s2 = play([[100, { e: 'Stop', bg: [] }], [200, { e: 'UserPromptSubmit' }]], s);
  assert.equal(snapshot(s2).startedAt, Math.floor(sec(200) / 1000));
});

test('une session en cours restée muette (Échap) passe en inactive', () => {
  const s = play([[0, { e: 'UserPromptSubmit' }]]);
  const snap = snapshot(s);
  assert.equal(publicSession(snap, null, sec(60)).status, 'running');
  const later = publicSession(snap, null, sec(0) + SILENT_AFTER_MS + 1000);
  assert.equal(later.status, 'idle');
});

test('publicSession : clés attendues par Swift et usage fusionné', () => {
  const s = play([[0, { e: 'UserPromptSubmit' }]]);
  const p = publicSession(snapshot(s), { costUsd: 1.234, contextPct: 41.6, model: 'Opus', title: 'Refonte' }, sec(90));
  assert.deepEqual(Object.keys(p).sort(), [
    'activity', 'agents', 'contextPct', 'costUsd', 'currentStep', 'duration', 'etaSeconds', 'model', 'project',
    'sid', 'startedAt', 'status', 'stepsDone', 'stepsTotal', 'title', 'updatedAt', 'workflow',
  ]);
  assert.equal(p.costUsd, 1.23);
  assert.equal(p.contextPct, 42);
  assert.equal(p.title, 'Refonte');
  assert.equal(p.duration, '2 min');
});

test('formatDuration', () => {
  assert.equal(formatDuration(10_000), "moins d'1 min");
  assert.equal(formatDuration(5 * 60_000), '5 min');
  assert.equal(formatDuration(65 * 60_000), '1 h 05');
  assert.equal(formatDuration(120 * 60_000), '2 h');
});

test('ce que fait Claude, précisément', () => {
  assert.equal(toolLabel('Edit', 'ContentView.swift'), 'Modifie ContentView.swift');
  assert.equal(toolLabel('Write', 'README.md'), 'Écrit README.md');
  assert.equal(toolLabel('Read', 'state.js'), 'Lit state.js');
  assert.equal(toolLabel('Bash', 'run backend tests'), 'Run backend tests');
  assert.equal(toolLabel('Bash', ''), 'Exécute des commandes');
  assert.equal(toolLabel('Agent', 'Explore auth flow'), 'Sous-agent : Explore auth flow');
  assert.equal(toolLabel('WebFetch', 'docs.anthropic.com'), 'Lit docs.anthropic.com');
  const s = play([[0, { e: 'PreToolUse', tool: 'Edit', detail: 'LiveMonitor.swift' }]]);
  assert.equal(s.activity, 'Modifie LiveMonitor.swift');
});

test('temps restant estimé à partir des étapes faites', () => {
  const todos = (done) => Array.from({ length: 5 }, (_, i) => ({ c: `É${i}`, s: i < done ? 'completed' : i === done ? 'in_progress' : 'pending' }));
  let s = play([[0, { e: 'UserPromptSubmit' }], [60, { e: 'PreToolUse', tool: 'TodoWrite', todos: todos(0) }]]);
  assert.equal(publicSession(snapshot(s), null, sec(120)).etaSeconds, -1, 'aucune étape faite : pas d’estimation');
  // 2 étapes en 4 min depuis l'apparition de la liste → 2 min par étape → 3 restantes = 6 min
  s = play([[300, { e: 'PreToolUse', tool: 'TodoWrite', todos: todos(2) }]], s);
  assert.equal(publicSession(snapshot(s), null, sec(300)).etaSeconds, 360);
  s = play([[400, { e: 'Stop', bg: [] }]], s);
  assert.equal(publicSession(snapshot(s), null, sec(400)).etaSeconds, -1, 'terminé : pas d’estimation');
});

test('une liste terminée ne réapparaît pas au tour suivant', () => {
  let s = play([
    [0, { e: 'UserPromptSubmit' }],
    [10, { e: 'PreToolUse', tool: 'TodoWrite', todos: [{ c: 'A', s: 'completed' }, { c: 'B', s: 'completed' }] }],
    [20, { e: 'Stop', bg: [] }],
    [100, { e: 'UserPromptSubmit' }],
  ]);
  assert.deepEqual(progress(s), { done: 0, total: 0, current: '' });
});

test('sous-agents : description, ce qu’ils font, puis terminés', () => {
  let s = play([
    [0, { e: 'UserPromptSubmit' }],
    [5, { e: 'PreToolUse', tool: 'Agent', detail: 'Explore auth flow' }],
    [6, { e: 'SubagentStart', agentId: 'a1', agentType: 'Explore' }],
    [9, { e: 'PreToolUse', tool: 'Read', detail: 'auth.ts', agentId: 'a1', agentType: 'Explore' }],
  ]);
  let d = sessionDetail(s, null, sec(10));
  assert.equal(d.agents.length, 1);
  assert.deepEqual(
    { type: d.agents[0].type, description: d.agents[0].description, activity: d.agents[0].activity, status: d.agents[0].status },
    { type: 'Explore', description: 'Explore auth flow', activity: 'Lit auth.ts', status: 'running' },
  );
  assert.equal(d.session.agents, 1);
  s = play([[40, { e: 'SubagentStop', agentId: 'a1', agentType: 'Explore' }]], s);
  d = sessionDetail(s, null, sec(41));
  assert.equal(d.agents[0].status, 'done');
  assert.equal(d.agents[0].endedAt - d.agents[0].startedAt, 34);
  assert.equal(d.session.agents, 0);
  assert.equal(d.log[0].text, 'Sous-agent Explore terminé', 'journal du plus récent au plus ancien');
});

test('anciennes sessions : agent stocké comme simple type', () => {
  const s = play([[0, { e: 'UserPromptSubmit' }]]);
  s.agents = { old: 'general-purpose' };
  const d = sessionDetail(s, null, sec(5));
  assert.equal(d.agents[0].type, 'general-purpose');
  const s2 = play([[6, { e: 'Stop', bg: [] }]], s);
  assert.equal(sessionDetail(s2, null, sec(7)).agents[0].status, 'done');
});

test('vue détaillée : toutes les étapes avec leur statut', () => {
  const s = play([[0, { e: 'PreToolUse', tool: 'TodoWrite', todos: [{ c: 'A', s: 'completed' }, { c: 'B', s: 'in_progress' }, { c: 'C', s: 'pending' }] }]]);
  assert.deepEqual(sessionDetail(s, null, sec(1)).steps, [
    { text: 'A', status: 'completed' },
    { text: 'B', status: 'in_progress' },
    { text: 'C', status: 'pending' },
  ]);
  const t = play([
    [0, { e: 'TaskCreated', taskId: '1', taskSubject: 'X' }],
    [1, { e: 'TaskCreated', taskId: '2', taskSubject: 'Y' }],
    [2, { e: 'TaskCompleted', taskId: '1', taskSubject: 'X' }],
  ]);
  assert.deepEqual(sessionDetail(t, null, sec(3)).steps.map((x) => x.status), ['completed', 'in_progress']);
});
