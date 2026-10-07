import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyEvent, progress, formatDuration, snapshot, publicSession, SILENT_AFTER_MS } from '../lib/state.js';

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
    'activity', 'agents', 'contextPct', 'costUsd', 'currentStep', 'duration', 'model', 'project', 'sid',
    'startedAt', 'status', 'stepsDone', 'stepsTotal', 'title', 'updatedAt', 'workflow',
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
