import crypto from 'node:crypto';

function authorized(req) {
  const expected = process.env.PULSE_TOKEN;
  if (!expected) return false;
  const got = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const a = Buffer.from(got);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** Enrobe un handler Vercel : méthode, authentification par jeton, erreurs JSON. */
export function route(method, fn) {
  const methods = Array.isArray(method) ? method : [method];
  return async (req, res) => {
    if (!methods.includes(req.method)) return res.status(405).json({ error: 'method not allowed' });
    if (!authorized(req)) return res.status(401).json({ error: 'unauthorized' });
    try {
      let body = req.body;
      if (typeof body === 'string') body = body ? JSON.parse(body) : {};
      await fn(body ?? {}, req, res);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: e.message });
    }
  };
}
