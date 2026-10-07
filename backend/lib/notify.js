// Notifications via ntfy (application gratuite) : arrivent sur l'iPhone et l'Apple Watch
// même quand Claude Pulse est fermé. Activées seulement si NTFY_TOPIC est défini.
const URL_ = process.env.NTFY_URL || 'https://ntfy.sh';
const TOPIC = process.env.NTFY_TOPIC;
const TOKEN = process.env.NTFY_TOKEN;

export const ntfyEnabled = () => Boolean(TOPIC);

/**
 * @param {{ title: string, message: string, priority?: 1|2|3|4|5, delay?: number }} n
 *   delay : secondes Unix de livraison (ntfy accepte jusqu'à 3 jours d'avance)
 */
export async function notify(n) {
  if (!TOPIC) return false;
  // Toucher la notification ouvre Claude Pulse (schéma d'URL déclaré dans l'app iOS).
  const body = { topic: TOPIC, title: n.title, message: n.message, priority: n.priority ?? 3, click: 'claudepulse://' };
  if (n.delay) body.delay = String(Math.floor(n.delay));
  try {
    const res = await fetch(URL_, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {}) },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(4000),
    });
    return res.ok;
  } catch (e) {
    console.error('ntfy', e.message);
    return false;
  }
}
