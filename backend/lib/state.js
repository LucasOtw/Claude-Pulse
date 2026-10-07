// État d'une session Claude Code, reconstruit à partir des événements des hooks.
// Fonctions pures : aucune I/O ici, tout est testé dans test/state.test.js.

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

/** Sans nouvelles pendant ce temps, une session « en cours » est considérée comme arrêtée (Échap ne déclenche pas Stop). */
export const SILENT_AFTER_MS = 20 * 60 * 1000;

const ACTIVE = new Set(['running', 'waiting', 'background']);
const NEEDS_INPUT = new Set(['permission_prompt', 'elicitation_dialog', 'elicitation_url_dialog', 'agent_needs_input']);

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
    workflow: null, // { name, phases: [] }
    error: null,
    usage: { costUsd: 0, contextPct: 0, model: null },
  };
}

/** Applique un événement de hook à l'état d'une session et renvoie le nouvel état. */
export function applyEvent(prev, ev, now) {
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
      if (!ACTIVE.has(before)) s.turnStartedAt = now;
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
      if (ev.agentId) delete s.agents[ev.agentId];
      break;

    case 'Notification':
      if (NEEDS_INPUT.has(ev.ntype)) {
        s.status = 'waiting';
        s.activity = translateNotification(ev);
      }
      break;

    case 'Stop': {
      const bg = (ev.bg || []).filter((t) => !['completed', 'failed', 'killed'].includes(t.status));
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
      s.updatedAt = prev?.updatedAt ?? now;
  }
  return s;
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

/** Progression : la liste TodoWrite si elle existe, sinon les tâches TaskCreated/TaskCompleted. */
export function progress(s) {
  if (s.todos && s.todos.total > 0) return s.todos;
  const tasks = Object.values(s.tasks ?? {});
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

/** Résumé compact stocké à chaque événement (hash Redis « live »), sans l'usage ni la durée. */
export function snapshot(s) {
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
    agents: Object.keys(s.agents ?? {}).length,
    workflow: s.workflow?.name ?? '',
    startedAt: Math.floor(s.turnStartedAt / 1000),
    updatedAt: Math.floor(s.updatedAt / 1000),
  };
}

/**
 * Session telle que la lisent l'app et le widget (⚠️ clés = PulseState.Session côté Swift).
 * @param snap  résultat de snapshot()
 * @param usage { costUsd, contextPct, model, title } écrit par la status line, ou null
 */
export function publicSession(snap, usage, now) {
  let { status, activity } = snap;
  if (status === 'running' && now - snap.updatedAt * 1000 > SILENT_AFTER_MS) {
    status = 'idle';
    activity = 'Plus de nouvelles (interrompu ?)';
  }
  const end = ACTIVE.has(status) ? now : snap.updatedAt * 1000;
  return {
    ...snap,
    title: snap.title || usage?.title || null,
    status,
    activity,
    costUsd: round2(usage?.costUsd ?? 0),
    contextPct: Math.round(usage?.contextPct ?? 0),
    model: usage?.model ?? null,
    duration: formatDuration(end - snap.startedAt * 1000),
  };
}

const round2 = (n) => Math.round(n * 100) / 100;
