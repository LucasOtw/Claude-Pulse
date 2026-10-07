import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyEvent, contentState, markPushed, progress, formatDuration } from '../lib/state.js';

const SID = 's1';
const T0 = 1_700_000_000_000;
const sec = (n) => T0 + n * 1000;

// Rejoue une suite d'événements [secondes, event] et renvoie l'état + toutes les actions.
function play(steps, initial = null) {
  let s = initial;
  const actions = [];
  for (const [t, ev] of steps) {
    const r = applyEvent(s, { sid: SID, project: 'demo', ...ev }, sec(t));
    s = r.state;
    if (r.action) {
      actions.push({ t, ...r.action });
      // Simule une push réussie comme le ferait lib/live.js.
      if (r.action.kind === 'start') s.la.started = true;
      if (r.action.kind === 'end') s.la.started = false;
      markPushed(s, sec(t), Math.floor(sec(t) / 1000));
    }
  }
  return { s, actions };
}

test('une réponse rapide ne lance pas de Live Activity', () => {
  const { s, actions } = play([
    [0, { e: 'UserPromptSubmit' }],
    [3, { e: 'PreToolUse', tool: 'Read' }],
    [8, { e: 'Stop', bg: [] }],
  ]);
  assert.equal(s.status, 'done');
  assert.deepEqual(actions, []);
});

test('une tâche longue démarre, se met à jour puis se termine', () => {
  const { s, actions } = play([
    [0, { e: 'UserPromptSubmit' }],
    [10, { e: 'PreToolUse', tool: 'Read' }],
    [35, { e: 'PreToolUse', tool: 'Edit' }],
    [36, { e: 'PreToolUse', tool: 'Edit' }], // même contenu : pas de push
    [60, { e: 'PreToolUse', tool: 'Bash' }],
    [300, { e: 'Stop', bg: [] }],
  ]);
  assert.deepEqual(actions.map((a) => [a.t, a.kind]), [[35, 'start'], [60, 'update'], [300, 'end']]);
  assert.equal(actions[0].alert.title, 'demo · Claude travaille');
  assert.match(actions[2].alert.title, /terminé/);
  assert.equal(actions[2].alert.body, 'En 5 min');
  assert.equal(s.la.started, false);
});

test('les mises à jour sans changement de statut sont limitées à une toutes les 5 s', () => {
  const { actions } = play([
    [0, { e: 'UserPromptSubmit' }],
    [31, { e: 'PreToolUse', tool: 'Read' }],
    [32, { e: 'PreToolUse', tool: 'Edit' }],
    [34, { e: 'PreToolUse', tool: 'Bash' }],
    [37, { e: 'PreToolUse', tool: 'Grep' }],
  ]);
  assert.deepEqual(actions.map((a) => [a.t, a.kind]), [[31, 'start'], [37, 'update']]);
});

test('une demande de validation lance tout de suite une activité avec alerte', () => {
  const { s, actions } = play([
    [0, { e: 'UserPromptSubmit' }],
    [7, { e: 'Notification', ntype: 'permission_prompt', message: 'Claude needs your permission to use Bash' }],
    [20, { e: 'PreToolUse', tool: 'Bash' }],
  ]);
  assert.equal(actions[0].kind, 'start');
  assert.equal(actions[0].alert.title, 'demo · attend ta validation');
  assert.equal(actions[1].kind, 'update');
  assert.equal(actions[1].priority, 10);
  assert.equal(s.status, 'running');
});

test('idle_prompt est ignoré', () => {
  const { s } = play([
    [0, { e: 'UserPromptSubmit' }],
    [5, { e: 'Stop', bg: [] }],
    [65, { e: 'Notification', ntype: 'idle_prompt', message: 'Claude is waiting for your input' }],
  ]);
  assert.equal(s.status, 'done');
});

test('Stop avec un workflow en arrière-plan ne termine pas l’activité', () => {
  const { s, actions } = play([
    [0, { e: 'UserPromptSubmit' }],
    [5, { e: 'PreToolUse', tool: 'Workflow', workflow: { name: 'review-changes', phases: ['Review', 'Verify'] } }],
    [6, { e: 'SubagentStart', agentId: 'a1', agentType: 'general-purpose' }],
    [6, { e: 'SubagentStart', agentId: 'a2', agentType: 'general-purpose' }],
    [8, { e: 'Stop', bg: [{ type: 'workflow', status: 'running', name: 'review-changes' }] }],
    [40, { e: 'SubagentStop', agentId: 'a1', agentType: 'general-purpose' }],
  ]);
  assert.equal(s.status, 'background');
  assert.equal(s.activity, 'Workflow « review-changes » en arrière-plan');
  assert.equal(actions[0].kind, 'start');
  const cs = contentState(s, null, sec(40));
  assert.equal(cs.workflow, 'review-changes');
  assert.equal(cs.agents, 1);
  assert.equal(cs.fiveHourPct, -1);
});

test('progression : TodoWrite prioritaire, sinon TaskCreated/TaskCompleted', () => {
  const { s } = play([
    [0, { e: 'UserPromptSubmit' }],
    [1, { e: 'TaskCreated', taskId: '1', taskSubject: 'Analyser' }],
    [2, { e: 'TaskCreated', taskId: '2', taskSubject: 'Coder' }],
    [3, { e: 'TaskCompleted', taskId: '1', taskSubject: 'Analyser' }],
  ]);
  assert.deepEqual(progress(s), { done: 1, total: 2, current: 'Coder' });

  const { s: s2 } = play([
    [4, { e: 'PreToolUse', tool: 'TodoWrite', todos: [{ c: 'A', s: 'completed' }, { c: 'Écrit B', s: 'in_progress' }, { c: 'C', s: 'pending' }] }],
  ], s);
  assert.deepEqual(progress(s2), { done: 1, total: 3, current: 'Écrit B' });
});

test('la TodoWrite d’un sous-agent ne remplace pas celle de la session', () => {
  const { s } = play([
    [0, { e: 'PreToolUse', tool: 'TodoWrite', todos: [{ c: 'A', s: 'in_progress' }] }],
    [1, { e: 'PreToolUse', tool: 'TodoWrite', agentId: 'x', todos: [{ c: 'Z', s: 'completed' }] }],
  ]);
  assert.equal(progress(s).current, 'A');
});

test('activité fermée à la main : pas relancée avant le prochain prompt', () => {
  let { s } = play([
    [0, { e: 'UserPromptSubmit' }],
    [31, { e: 'PreToolUse', tool: 'Edit' }],
  ]);
  s.la.started = false;
  s.la.dismissed = true; // ce que fait lib/live.js sur un jeton mort
  ({ s } = play([[60, { e: 'PreToolUse', tool: 'Bash' }], [70, { e: 'Stop', bg: [] }]], s));
  const { actions } = play([[100, { e: 'UserPromptSubmit' }], [140, { e: 'PreToolUse', tool: 'Bash' }]], s);
  assert.deepEqual(actions.map((a) => a.kind), ['start']);
});

test('StopFailure termine avec une erreur', () => {
  const { actions } = play([
    [0, { e: 'UserPromptSubmit' }],
    [40, { e: 'PreToolUse', tool: 'Edit' }],
    [50, { e: 'StopFailure', error: 'rate_limit' }],
  ]);
  assert.equal(actions[1].kind, 'end');
  assert.equal(actions[1].alert.body, 'Erreur : rate_limit');
});

test('contentState contient exactement les clés attendues par Swift', () => {
  const { s } = play([[0, { e: 'UserPromptSubmit' }]]);
  const cs = contentState(s, { fiveHour: { pct: 42.6, resetsAt: 0 } }, sec(90));
  assert.deepEqual(Object.keys(cs).sort(), [
    'activity', 'agents', 'contextPct', 'costUsd', 'currentStep', 'duration', 'fiveHourPct',
    'status', 'stepsDone', 'stepsTotal', 'workflow',
  ]);
  assert.equal(cs.fiveHourPct, 43);
  assert.equal(cs.duration, '2 min');
});

test('formatDuration', () => {
  assert.equal(formatDuration(10_000), "moins d'1 min");
  assert.equal(formatDuration(5 * 60_000), '5 min');
  assert.equal(formatDuration(65 * 60_000), '1 h 05');
  assert.equal(formatDuration(120 * 60_000), '2 h');
});

test('les notifications sont traduites', () => {
  const { s } = play([[0, { e: 'Notification', ntype: 'permission_prompt', message: 'Claude needs your permission to use Bash' }]]);
  assert.equal(s.activity, 'Veut utiliser Bash : à valider');
  const { s: s2 } = play([[0, { e: 'Notification', ntype: 'elicitation_dialog', message: 'MCP server needs input' }]]);
  assert.equal(s2.activity, 'Attend ta réponse');
});
