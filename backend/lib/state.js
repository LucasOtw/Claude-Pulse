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

export function toolLabel(tool, detail) {
  const d = typeof detail === 'string' ? detail.trim() : '';
  switch (tool) {
    case 'Edit':
    case 'MultiEdit':
    case 'NotebookEdit':
      if (d) return `Modifie ${d}`;
      break;
    case 'Write':
      if (d) return `Écrit ${d}`;
      break;
    case 'Read':
      if (d) return `Lit ${d}`;
      break;
    case 'Bash':
      // Description courte rédigée par Claude pour la commande (« Run backend tests »).
      if (d) return d.charAt(0).toUpperCase() + d.slice(1);
      break;
    case 'Agent':
    case 'Task':
      if (d) return `Sous-agent : ${d}`;
      break;
    case 'WebFetch':
      if (d) return `Lit ${d}`;
      break;
    case 'Skill':
      if (d) return `Compétence ${d}`;
      break;
  }
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
    progressStartedAt: null, // apparition de la liste de tâches du tour, pour estimer le temps restant
    error: null,
    usage: { costUsd: 0, contextPct: 0, model: null },
  };
}

const MAX_LOG = 15;
const MAX_DONE_AGENTS = 6;

/** Ajoute une ligne au journal d'activité (sans répéter la précédente). */
function log(s, now, text) {
  if (!text) return;
  s.log = s.log ?? [];
  if (s.log.at(-1)?.text === text) return;
  s.log.push({ t: Math.floor(now / 1000), text });
  if (s.log.length > MAX_LOG) s.log.splice(0, s.log.length - MAX_LOG);
}

/** Les anciennes sessions stockaient seulement le type de l'agent. */
function agentOf(s, id, type, now) {
  const a = s.agents[id];
  if (a && typeof a === 'object') return a;
  s.agents[id] = { type: (typeof a === 'string' ? a : type) || 'agent', description: '', activity: '', startedAt: now };
  return s.agents[id];
}

function finishAgents(s, now) {
  for (const [id, a] of Object.entries(s.agents ?? {})) {
    const agent = typeof a === 'object' ? a : { type: a, description: '', startedAt: now };
    s.agentsDone = [{ id, type: agent.type, description: agent.description, startedAt: agent.startedAt, endedAt: now }, ...(s.agentsDone ?? [])]
      .slice(0, MAX_DONE_AGENTS);
  }
  s.agents = {};
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
      if (!ACTIVE.has(before)) {
        s.turnStartedAt = now;
        s.progressStartedAt = null;
        s.agentsDone = [];
        // Une liste entièrement terminée appartient au tour précédent.
        if (s.todos && s.todos.done >= s.todos.total) s.todos = null;
        if (Object.values(s.tasks ?? {}).every((t) => t.done)) s.tasks = {};
      }
      s.summary = null;
      s.recap = null;
      log(s, now, 'Nouvelle demande');
      break;

    case 'PreToolUse':
    case 'PostToolUse': {
      const label = toolLabel(ev.tool, ev.detail);
      s.status = 'running';
      s.activity = label;
      if (ev.agentId) {
        // Outil appelé par un sous-agent : on note ce qu'il fait.
        const a = agentOf(s, ev.agentId, ev.agentType, now);
        a.activity = label;
      } else {
        if (ev.todos) {
          s.todos = summarizeTodos(ev.todos);
          if (!s.progressStartedAt && s.todos.total > 0) s.progressStartedAt = now;
        }
        // La description donnée au sous-agent arrive avant son démarrage : on la garde de côté.
        if ((ev.tool === 'Agent' || ev.tool === 'Task') && ev.detail) {
          s.pendingAgents = [...(s.pendingAgents ?? []), ev.detail].slice(-10);
        }
        log(s, now, label);
      }
      if (ev.workflow) s.workflow = ev.workflow;
      break;
    }

    case 'TaskCreated':
      if (ev.taskId) s.tasks[ev.taskId] = { subject: ev.taskSubject || '', done: false };
      if (!s.progressStartedAt) s.progressStartedAt = now;
      break;

    case 'TaskCompleted':
      if (ev.taskId) s.tasks[ev.taskId] = { subject: ev.taskSubject || s.tasks[ev.taskId]?.subject || '', done: true };
      log(s, now, ev.taskSubject ? `Étape terminée : ${ev.taskSubject}` : 'Étape terminée');
      break;

    case 'SubagentStart':
      if (ev.agentId) {
        const a = agentOf(s, ev.agentId, ev.agentType, now);
        a.type = ev.agentType || a.type;
        a.startedAt = now;
        a.description = a.description || (s.pendingAgents ?? []).shift() || '';
        a.activity = a.activity || 'Démarre…';
        log(s, now, `Sous-agent ${a.type}${a.description ? ` : ${a.description}` : ''}`);
      }
      if (s.status !== 'waiting') s.status = 'running';
      break;

    case 'SubagentStop':
      if (ev.agentId && s.agents[ev.agentId]) {
        const a = agentOf(s, ev.agentId, ev.agentType, now);
        s.agentsDone = [{ id: ev.agentId, type: a.type, description: a.description, startedAt: a.startedAt, endedAt: now }, ...(s.agentsDone ?? [])]
          .slice(0, MAX_DONE_AGENTS);
        delete s.agents[ev.agentId];
        log(s, now, `Sous-agent ${a.type} terminé`);
      }
      break;

    case 'Notification':
      if (NEEDS_INPUT.has(ev.ntype)) {
        s.status = 'waiting';
        s.activity = translateNotification(ev);
        log(s, now, s.activity);
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
        finishAgents(s, now);
      }
      if (ev.summary) s.summary = String(ev.summary).slice(0, 200);
      if (ev.recap) s.recap = cleanRecap(ev.recap);
      log(s, now, s.activity);
      break;
    }

    case 'StopFailure':
      s.status = 'error';
      s.error = ev.error || 'erreur API';
      s.activity = `Erreur : ${s.error}`;
      log(s, now, s.activity);
      break;

    case 'SessionEnd':
      s.status = 'done';
      s.activity = 'Session fermée';
      finishAgents(s, now);
      log(s, now, s.activity);
      break;

    default:
      s.updatedAt = prev?.updatedAt ?? now;
  }
  return s;
}

/** Ce que Claude a fait pendant le tour (calculé sur le Mac à partir du transcript). */
function cleanRecap(r) {
  const n = (v) => (Number.isFinite(v) && v > 0 ? Math.floor(v) : 0);
  const files = Array.isArray(r.files) ? r.files.filter((f) => typeof f === 'string' && f).slice(0, 8).map((f) => f.slice(0, 60)) : [];
  return { files, fileCount: Math.max(n(r.fileCount), files.length), commands: n(r.commands), agents: n(r.agents) };
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
  const items = todos.slice(0, 30).map((t) => ({ text: t.c ?? '', status: t.s ?? 'pending' }));
  return { done, total, current, items };
}

/** Progression : la liste TodoWrite si elle existe, sinon les tâches TaskCreated/TaskCompleted. */
export function progress(s) {
  if (s.todos && s.todos.total > 0) return { done: s.todos.done, total: s.todos.total, current: s.todos.current };
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
    summary: s.status === 'done' ? (s.summary ?? null) : null,
    startedAt: Math.floor(s.turnStartedAt / 1000),
    progressStartedAt: s.progressStartedAt ? Math.floor(s.progressStartedAt / 1000) : null,
    updatedAt: Math.floor(s.updatedAt / 1000),
  };
}

/**
 * Temps restant estimé (secondes) : durée moyenne des étapes déjà faites × étapes restantes.
 * -1 tant qu'aucune étape n'est terminée ou que la tâche n'est pas en cours.
 */
export function estimateRemaining(snap, status, now) {
  const { stepsDone: done, stepsTotal: total } = snap;
  if (!ACTIVE.has(status) || !(done > 0) || done >= total) return -1;
  const since = (snap.progressStartedAt ?? snap.startedAt) * 1000;
  const perStep = (now - since) / done;
  return Math.max(0, Math.round((perStep * (total - done)) / 1000));
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
  const { progressStartedAt, ...rest } = snap;
  return {
    ...rest,
    title: snap.title || usage?.title || null,
    status,
    activity,
    costUsd: round2(usage?.costUsd ?? 0),
    contextPct: Math.round(usage?.contextPct ?? 0),
    model: usage?.model ?? null,
    duration: formatDuration(end - snap.startedAt * 1000),
    etaSeconds: estimateRemaining(snap, status, now),
  };
}

const round2 = (n) => Math.round(n * 100) / 100;

/** Toutes les étapes, pour la vue détaillée d'une session. */
export function steps(s) {
  if (s.todos?.items?.length) return s.todos.items;
  const tasks = Object.values(s.tasks ?? {});
  const firstOpen = tasks.findIndex((t) => !t.done);
  return tasks.map((t, i) => ({ text: t.subject, status: t.done ? 'completed' : i === firstOpen ? 'in_progress' : 'pending' }));
}

/** Vue détaillée d'une session (⚠️ clés = SessionDetail côté Swift). */
export function sessionDetail(s, tokens, now) {
  const base = publicSession(snapshot(s), s.usage, now);
  const sec = (ms) => Math.floor(ms / 1000);
  const running = Object.entries(s.agents ?? {}).map(([id, a]) => {
    const agent = typeof a === 'object' ? a : { type: a, description: '', activity: '', startedAt: s.turnStartedAt };
    return {
      id,
      type: agent.type || 'agent',
      description: agent.description || '',
      activity: agent.activity || '',
      status: 'running',
      startedAt: sec(agent.startedAt ?? now),
      endedAt: null,
    };
  });
  const done = (s.agentsDone ?? []).map((a) => ({
    id: a.id,
    type: a.type || 'agent',
    description: a.description || '',
    activity: '',
    status: 'done',
    startedAt: sec(a.startedAt ?? now),
    endedAt: sec(a.endedAt ?? now),
  }));
  return {
    session: base,
    steps: steps(s),
    agents: [...running, ...done],
    workflow: s.workflow ? { name: s.workflow.name ?? '', phases: s.workflow.phases ?? [] } : null,
    log: [...(s.log ?? [])].reverse().map((l) => ({ at: l.t, text: l.text })),
    tokens,
  };
}
