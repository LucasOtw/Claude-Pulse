// Envoi de push Apple (APNs) en HTTP/2 avec un jeton JWT ES256, sans dépendance.
import http2 from 'node:http2';
import crypto from 'node:crypto';

const TEAM_ID = process.env.APNS_TEAM_ID;
const KEY_ID = process.env.APNS_KEY_ID;
const BUNDLE_ID = process.env.APNS_BUNDLE_ID || 'com.lucasotw.claudepulse';
const HOST = process.env.APNS_HOST || (process.env.APNS_ENV === 'production' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com');

let cached = { token: null, at: 0 };

const b64url = (buf) => Buffer.from(buf).toString('base64url');

function providerToken() {
  // Apple accepte un même JWT entre 20 et 60 min : on le renouvelle toutes les 40 min.
  if (cached.token && Date.now() - cached.at < 40 * 60 * 1000) return cached.token;
  const raw = process.env.APNS_KEY;
  if (!TEAM_ID || !KEY_ID || !raw) throw new Error('APNs non configuré (APNS_TEAM_ID / APNS_KEY_ID / APNS_KEY)');
  const key = crypto.createPrivateKey(raw.includes('\\n') ? raw.replace(/\\n/g, '\n') : raw);
  const iat = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: 'ES256', kid: KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: TEAM_ID, iat }));
  const sig = crypto.sign('sha256', Buffer.from(`${head}.${claims}`), { key, dsaEncoding: 'ieee-p1363' });
  cached = { token: `${head}.${claims}.${b64url(sig)}`, at: Date.now() };
  return cached.token;
}

/**
 * Envoie une push Live Activity.
 * @returns {Promise<{status: number, reason?: string}>}
 */
export function sendLiveActivity(deviceToken, payload, { priority = 10 } = {}) {
  return new Promise((resolve, reject) => {
    let jwt;
    try {
      jwt = providerToken();
    } catch (e) {
      return reject(e);
    }
    const client = http2.connect(HOST);
    client.on('error', reject);
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization: `bearer ${jwt}`,
      'apns-push-type': 'liveactivity',
      'apns-topic': `${BUNDLE_ID}.push-type.liveactivity`,
      'apns-priority': String(priority),
      'apns-expiration': String(Math.floor(Date.now() / 1000) + 600),
      'content-type': 'application/json',
    });
    let status = 0;
    let body = '';
    req.setEncoding('utf8');
    req.on('response', (h) => (status = h[':status']));
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      client.close();
      let reason;
      try {
        reason = body ? JSON.parse(body).reason : undefined;
      } catch {}
      resolve({ status, reason });
    });
    req.on('error', (e) => {
      client.close();
      reject(e);
    });
    req.end(JSON.stringify(payload));
  });
}

/** Le jeton est mort (app désinstallée, activité terminée…) : on peut l'oublier. */
export const isDeadToken = (r) => r.status === 410 || r.reason === 'BadDeviceToken' || r.reason === 'Unregistered';
