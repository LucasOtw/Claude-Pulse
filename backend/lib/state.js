// Machine à états d'une session Claude Code.
// Fonctions pures : aucune I/O ici, tout est testé dans test/state.test.js.

export const DEFAULTS = {
  // Une Live Activity ne démarre que si la tâche dure plus que ça (évite le spam sur les questions rapides).
  minTaskSeconds: 30,
  // Intervalle minimum entre deux push de mise à jour sans changement de statut.
  minPushSeconds: 5,
};

const TOOL_LABELS = {
  Edit: 'Modifie des fichiers',
  MultiEdit: 'Modifie des fichiers',
  Write: 'Écrit des fichiers',
  NotebookEdit: 'Modifie un notebook',
  Read: 'Lit le code',
  Grep: 'Explore le code',
  Glob: 'Explore le code',
  LS: 'Explore le code',
  Bash: 'Exécute des commandes',
  WebFetch: 'Lit une page web',
  WebSearch: 'Cherche sur le web',
  Agent: 'Lance un sous-agent',
  Task: 'Lance un sous-agent',
  Workflow: 'Lance un workflow',
  TodoWrite: 'Planifie',
  TaskCreate: 'Planifie',
  TaskUpdate: 'Avance dans le plan',
  Skill: 'Utilise une compétence',
};

export function toolLabel(tool) {
  if (!tool) return 'Travaille…';
  if (TOOL_LABELS[tool]) return TOOL_LABELS[tool];
  if (tool.startsWith('mcp__')) return `Utilise ${tool.split('__')[1] ?? 'un outil'}`;
  return `Utilise ${tool}`;
}

export function newSession(ev, now) {
  return {
    sid: ev.sid,
    project: ev.project || 'Claude Code',
    title: ev.title || null,
    status: 'idle',
    activity: '',
    turnStartedAt: now,
    updatedAt: now,
    todos: null, // { done, total, current } issu de TodoWrite
    tasks: {}, // id -> { subject, done } issu de TaskCreated / TaskCompleted
    agents: {}, // agentId -> type, sous-agents en cours
    agentsDone: 0,
    workflow: null, // { name, phases: [] }
    background: 0,
    error: null,
    usage: { costUsd: 0, contextPct: 0, model: null },
    la: { started: false, dismissed: false, pendingEnd: false, startedAt: 0, lastPushAt: 0, lastTs: 0, lastKey: '' },
  };
}

const ACTIVE = new Set(['running', 'waiting', 'background']);
const NEEDS_INPUT = new Set(['permission_prompt', 'elicitation_dialog', 'elicitation_url_dialog', 'agent_needs_input']);

/**
 * Applique un événement de hook à l'état d'une session.
 * @returns {{ state: object, action: null | { kind: 'start'|'update'|'end', alert?: {title: string, body: string}, priority: 5|10 } }}
 */
export function applyEvent(prev, ev, now, cfg = DEFAULTS) {
  const s = structuredClone(prev ?? newSession(ev, now));
  const before = s.status;
  s.updatedAt = now;
  if (ev.project) s.project = ev.project;
  if (ev.title) s.title = ev.title;

  switch (ev.e) {
    case 'UserPromptSubmit':
      s.status = 'running';
      s.activity = 'Réfléchit…';
      s.error = null;
      if (!ACTIVE.has(before)) {
        s.turnStartedAt = now;
        s.agentsDone = 0;
        s.la.dismissed = false;
      }
      break;

    case 'PreToolUse':
    case 'PostToolUse':
      s.status = 'running';
      s.activity = toolLabel(ev.tool);
      if (ev.todos && !ev.agentId) s.todos = summarizeTodos(ev.todos);
      if (ev.workflow) s.workflow = ev.workflow;
      break;

    case 'TaskCreated':
      if (ev.taskId) s.tasks[ev.taskId] = { subject: ev.taskSubject || '', done: false };
      break;

    case 'TaskCompleted':
      if (ev.taskId) s.tasks[ev.taskId] = { subject: ev.taskSubject || s.tasks[ev.taskId]?.subject || '', done: true };
      break;

    case 'SubagentStart':
      if (ev.agentId) s.agents[ev.agentId] = ev.agentType || 'agent';
      if (s.status !== 'waiting') s.status = 'running';
      break;

    case 'SubagentStop':
      if (ev.agentId && s.agents[ev.agentId]) {
        delete s.agents[ev.agentId];
        s.agentsDone += 1;
      }
      break;

    case 'Notification':
      if (NEEDS_INPUT.has(ev.ntype)) {
        s.status = 'waiting';
        s.activity = translateNotification(ev);
      }
      break;

    case 'Stop': {
      const bg = (ev.bg || []).filter((t) => t.status !== 'completed' && t.status !== 'failed' && t.status !== 'killed');
      s.background = bg.length;
      if (bg.length > 0) {
        s.status = 'background';
        const wf = bg.find((t) => t.type === 'workflow');
        s.activity = wf
          ? `Workflow « ${wf.name || 'sans nom'} » en arrière-plan`
          : `${bg.length} tâche${bg.length > 1 ? 's' : ''} en arrière-plan`;
      } else {
        s.status = 'done';
        s.activity = 'Terminé';
        s.agents = {};
      }
      break;
    }

    case 'StopFailure':
      s.status = 'error';
      s.error = ev.error || 'erreur API';
      s.activity = `Erreur : ${s.error}`;
      break;

    case 'SessionEnd':
      s.status = 'done';
      s.activity = 'Session fermée';
      s.agents = {};
      break;

    default:
      return { state: s, action: null };
  }

  return { state: s, action: decide(s, before, now, cfg) };
}

function decide(s, before, now, cfg) {
  const changed = s.status !== before;
  const la = s.la;

  if (!la.started) {
    if (!ACTIVE.has(s.status) || la.dismissed) return null;
    const longEnough = now - s.turnStartedAt >= cfg.minTaskSeconds * 1000;
    if (!longEnough && s.status !== 'waiting') return null;
    return { kind: 'start', priority: 10, alert: alertFor(s, true, now) };
  }

  if (s.status === 'done' || s.status === 'error') {
    return { kind: 'end', priority: 10, alert: alertFor(s, false, now) };
  }

  const key = contentKey(s);
  if (!changed && key === la.lastKey) return null;
  if (!changed && now - la.lastPushAt < cfg.minPushSeconds * 1000) return null;
  const alert = changed && s.status === 'waiting' ? alertFor(s, false, now) : undefined;
  return { kind: 'update', priority: changed ? 10 : 5, alert };
}

function alertFor(s, starting, now) {
  const p = s.project;
  if (s.status === 'waiting') return { title: `${p} · attend ta validation`, body: s.activity };
  if (s.status === 'done') return { title: `${p} · terminé ✅`, body: `En ${formatDuration(now - s.turnStartedAt)}` };
  if (s.status === 'error') return { title: `${p} · erreur`, body: s.activity };
  if (starting) return { title: `${p} · Claude travaille`, body: s.activity || 'Tâche en cours' };
  return { title: p, body: s.activity };
}

export function translateNotification(ev) {
  const m = /permission to use (.+)$/i.exec(ev.message || '');
  if (m) return `Veut utiliser ${m[1]} : à valider`;
  if (ev.ntype === 'permission_prompt') return 'Attend ta validation';
  return 'Attend ta réponse';
}

export function summarizeTodos(todos) {
  const total = todos.length;
  const done = todos.filter((t) => t.s === 'completed').length;
  const current = todos.find((t) => t.s === 'in_progress')?.c ?? '';
  return { done, total, current };
}

/** Progression : la liste TodoWrite si elle existe, sinon les tâches TaskCreate/TaskCompleted. */
export function progress(s) {
  if (s.todos && s.todos.total > 0) return s.todos;
  const tasks = Object.values(s.tasks);
  if (tasks.length === 0) return { done: 0, total: 0, current: '' };
  const done = tasks.filter((t) => t.done).length;
  const current = tasks.find((t) => !t.done)?.subject ?? '';
  return { done, total: tasks.length, current };
}

export function formatDuration(ms) {
  const min = Math.max(0, Math.round(ms / 60000));
  if (min < 1) return "moins d'1 min";
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m ? `${h} h ${String(m).padStart(2, '0')}` : `${h} h`;
}

/**
 * ContentState envoyé à la Live Activity.
 * ⚠️ Les clés doivent correspondre exactement à PulseAttributes.ContentState côté Swift.
 */
export function contentState(s, limits, now) {
  const p = progress(s);
  return {
    status: s.status,
    activity: s.activity || '',
    currentStep: p.current || '',
    stepsDone: p.done,
    stepsTotal: p.total,
    agents: Object.keys(s.agents).length,
    workflow: s.workflow?.name ?? '',
    costUsd: round2(s.usage?.costUsd ?? 0),
    contextPct: Math.round(s.usage?.contextPct ?? 0),
    fiveHourPct: limits?.fiveHour ? Math.round(limits.fiveHour.pct) : -1,
    duration: formatDuration(now - s.turnStartedAt),
  };
}

/** Attributs statiques de la Live Activity (PulseAttributes côté Swift). */
export function attributes(s) {
  return { sessionId: s.sid, project: s.project, startedAt: Math.floor(s.turnStartedAt / 1000) };
}

function contentKey(s) {
  const p = progress(s);
  return [s.status, s.activity, p.done, p.total, p.current, Object.keys(s.agents).length, s.workflow?.name ?? ''].join('|');
}

export function markPushed(s, now, ts) {
  s.la.lastPushAt = now;
  s.la.lastTs = ts;
  s.la.lastKey = contentKey(s);
}

/** Résumé d'une session pour l'app et le widget. */
export function publicSession(s, now) {
  const p = progress(s);
  return {
    sid: s.sid,
    project: s.project,
    title: s.title,
    status: s.status,
    activity: s.activity,
    currentStep: p.current,
    stepsDone: p.done,
    stepsTotal: p.total,
    agents: Object.keys(s.agents).length,
    workflow: s.workflow?.name ?? '',
    costUsd: round2(s.usage?.costUsd ?? 0),
    contextPct: Math.round(s.usage?.contextPct ?? 0),
    model: s.usage?.model ?? null,
    duration: formatDuration(now - s.turnStartedAt),
    updatedAt: Math.floor(s.updatedAt / 1000),
  };
}

const round2 = (n) => Math.round(n * 100) / 100;
