/** COP-3 — pure helpers for the copilot chat panel. */

export type StorageLike = Pick<Storage, 'getItem' | 'setItem'>;

/** Plain text of a message whose content is an array of {type, text} parts (or already a string). */
export function messageText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .filter((p): p is {type: string; text: string} => !!p && typeof p === 'object' && (p as {type?: unknown}).type === 'text' && typeof (p as {text?: unknown}).text === 'string')
    .map((p) => p.text)
    .filter((t) => t !== '')
    .join('\n');
}

/** What the person is looking at, in plain words, for the server's screen_context. */
export function screenContextSummary(pathname: string, search: string): string {
  const params = new URLSearchParams(search);
  const seg = pathname.replace(/\/+$/, '').split('/').filter(Boolean);
  const first = seg[0] ?? '';
  const id = seg[1] ?? '';
  switch (first) {
    case 'planner': {
      const job = params.get('job');
      return job ? `Planner, job ${job}` : 'Planner';
    }
    case 'maps':
      return id ? `Journey map ${id}` : 'Journey maps';
    case 'architectures':
      return id ? `Business ${id}` : 'Businesses';
    case 'approvals':
      return 'Approvals';
    case 'perform':
      return 'Perform';
    case 'dashboard':
      return 'Dashboard';
    case 'team':
      return 'Manage users';
    case 'health':
      return 'Health';
    case 'account':
      return 'Account settings';
    case 'reports':
      return id ? `Reports, ${id.replace(/-/g, ' ')}` : 'Reports';
    default:
      return pathname || '/';
  }
}

export interface ConversationLike {
  id: number;
  last_message_at?: number | string | null;
  created_at?: number | string | null;
}

const when = (v: number | string | null | undefined): number => {
  if (v == null || v === '') return 0;
  const n = typeof v === 'number' ? v : Number(v);
  if (Number.isFinite(n)) return n;
  const t = new Date(v).getTime();
  return Number.isNaN(t) ? 0 : t;
};

/** The conversation to reopen: the most recently active one, or null for "start fresh". */
export function pickConversation(list: ConversationLike[] | null | undefined): number | null {
  if (!list || list.length === 0) return null;
  let best: ConversationLike | null = null;
  let bestAt = -1;
  for (const c of list) {
    const at = Math.max(when(c.last_message_at), when(c.created_at));
    if (at > bestAt) {
      best = c;
      bestAt = at;
    }
  }
  return best ? best.id : null;
}

const key = (userId: number) => `emgram.copilot.business.${userId}`;

export function readLastBusiness(storage: StorageLike | undefined, userId: number): number | null {
  try {
    const v = storage?.getItem(key(userId));
    const n = v == null ? NaN : Number(v);
    return Number.isInteger(n) && n > 0 ? n : null;
  } catch {
    return null;
  }
}

export function writeLastBusiness(storage: StorageLike | undefined, userId: number, businessId: number): void {
  try {
    storage?.setItem(key(userId), String(businessId));
  } catch {
    /* storage unavailable: the choice just isn't remembered */
  }
}
