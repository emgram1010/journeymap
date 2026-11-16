/**
 * COP-6 - the connections library on the screen. The server checks everything again; these only
 * keep the owner's typing and say the same thing first (CLAUDE.md: the UI helps, the server decides).
 */
export type ConnectionRow = {
  id: number;
  key: string;
  name: string;
  description: string;
  status: 'available' | 'retired' | '';
  is_on: boolean;
  has_login: boolean;
  last_ok_at: number;
  failing_since: number;
  last_error_code: string;
};

const ENTRY_MESSAGE =
  'A connection needs a short key (lower-case letters, digits and dashes, 2 to 40), a name (up to 80 characters) and a description of up to 300. (E-COP-064)';

/** Mirror of POST copilot/connection's rule. null = fine. */
export function connectionEntryProblem(key: string, name: string, description: string): string | null {
  const k = key.trim();
  const n = name.trim();
  if (!/^[a-z0-9-]{2,40}$/.test(k)) return ENTRY_MESSAGE;
  if (n.length < 1 || n.length > 80) return ENTRY_MESSAGE;
  if (description.trim().length > 300) return ENTRY_MESSAGE;
  return null;
}

const LOGIN_MESSAGE = "A login can't be empty, and can be up to 4000 characters. (E-COP-068)";

/** Mirror of POST copilot/connection_login's rule. null = fine. The login itself is never trimmed or changed. */
export function loginProblem(login: string): string | null {
  if (login.trim().length < 1 || login.length > 4000) return LOGIN_MESSAGE;
  return null;
}

export function connectionStateLabel(r: Pick<ConnectionRow, 'is_on' | 'has_login' | 'failing_since' | 'last_ok_at'>): string {
  if (!r.is_on) return r.has_login ? 'Off' : 'Off - needs a login first';
  if (r.failing_since && r.failing_since > 0) return 'On - failing';
  return 'On';
}
