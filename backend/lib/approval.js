// Validation à distance : garde-fous.

/** Commandes qu'on refuse de valider depuis le téléphone, quoi qu'il arrive. */
const DANGEROUS = [
  /\brm\s+(-[a-z]*[rf][a-z]*\s+)+/i,
  /\bsudo\b/i,
  /\bgit\s+push\b.*(--force|-f\b)/i,
  /\bgit\s+(reset\s+--hard|clean\s+-[a-z]*f)/i,
  /\b(mkfs|dd\s+if=|shutdown|reboot)\b/i,
  /\b(curl|wget)\b[^|]*\|\s*(ba|z)?sh\b/i,
  /\bchmod\s+(-R\s+)?777\b/i,
  /\bDROP\s+(TABLE|DATABASE)\b/i,
  />\s*\/dev\/(sd|disk)/i,
  /\bnpm\s+publish\b|\bvercel\s+--prod\b|\bterraform\s+(apply|destroy)\b/i,
];

export function isDangerous(tool, text) {
  if (tool === 'Bash') return DANGEROUS.some((r) => r.test(text || ''));
  return false;
}

/** Ce qu'on montre sur le téléphone pour décider. */
export function describe(tool, input) {
  const i = input && typeof input === 'object' ? input : {};
  const cut = (v, n = 500) => String(v ?? '').slice(0, n);
  switch (tool) {
    case 'Bash':
      return { text: cut(i.command), note: cut(i.description, 120) };
    case 'Edit':
    case 'MultiEdit':
    case 'Write':
    case 'NotebookEdit':
      return { text: cut(i.file_path ?? i.notebook_path), note: tool === 'Write' ? 'Écrire ce fichier' : 'Modifier ce fichier' };
    case 'WebFetch':
      return { text: cut(i.url), note: 'Lire cette page' };
    default:
      return { text: cut(JSON.stringify(i), 300), note: '' };
  }
}

export const APPROVAL_TTL = 15 * 60; // secondes
export const REMOTE_TTL = 12 * 3600; // la validation à distance s'éteint seule au bout de 12 h
