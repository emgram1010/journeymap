// OBS-1 (US-OBS-1-05, convention: "no sensitive data in events — log ids
// and field NAMES, never values") — Run on any payload before it leaves
// the browser as a client event or a diagnostic bundle attachment, so an
// attribute value, a note, an email, a token or a password can never
// reach the server through this path even if a caller forgot the
// convention.
//
// Strategy: keep primitives that look like ids (numbers, short id-shaped
// strings, booleans). For anything else — long strings, nested objects,
// arrays, emails, anything matching a sensitive key name — keep only the
// key name and replace the value with a marker. This is deliberately
// conservative: it is fine to over-redact a diagnostic payload, never to
// under-redact one.
const SENSITIVE_KEY_PATTERN = /password|token|secret|authorization|email|ssn|credit.?card/i;

const ID_LIKE_STRING_PATTERN = /^[a-zA-Z0-9_-]{1,40}$/;

function looksLikeId(value: unknown): boolean {
  if (typeof value === 'number' || typeof value === 'boolean') return true;
  if (typeof value === 'string') return ID_LIKE_STRING_PATTERN.test(value) && value.length <= 40;
  return false;
}

/**
 * Redacts a payload (typically event `metadata`) in place-safe fashion
 * (returns a new object/array, never mutates the input). Keeps keys
 * always; replaces values that are not id-like, or whose key name looks
 * sensitive, with the marker "[redacted]".
 */
export function redact(payload: unknown): unknown {
  return redactValue(payload, null);
}

function redactValue(value: unknown, keyName: string | null): unknown {
  if (value === null || value === undefined) return value;

  if (keyName && SENSITIVE_KEY_PATTERN.test(keyName)) {
    return '[redacted]';
  }

  if (Array.isArray(value)) {
    return value.map((item) => redactValue(item, keyName));
  }

  if (typeof value === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
      result[key] = redactValue(nested, key);
    }
    return result;
  }

  if (looksLikeId(value)) return value;

  return '[redacted]';
}
