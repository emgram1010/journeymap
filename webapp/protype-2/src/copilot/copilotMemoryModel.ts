/** COP-4 — pure helpers for "what the copilot knows" and map labels. */

export const NOTE_MAX = 500;

export interface MapSource {
  title: string;
  url: string;
}

export interface MapProfile {
  journey_map_id: number;
  kind: string;
  made_by: string;
  sources?: MapSource[] | null;
  research_note?: string | null;
  tested_since: number;
}

export interface MemoryGoal {
  id: number;
  goal_text?: string;
  target?: string;
  target_date?: string;
  status: string;
}

export interface MemoryNote {
  id: number;
  note: string;
}

export interface LabelChip {
  text: string;
  tone: 'kind' | 'tested' | 'warn';
}

export const testedSinceText = (ts: number): string => {
  if (!ts) return '';
  const d = new Date(ts);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleDateString();
};

/** No profile = no label and no warning (maps made by people default sensibly). */
export const mapLabelChips = (p: MapProfile | null | undefined): LabelChip[] => {
  if (!p) return [];
  const chips: LabelChip[] = [];
  if (p.kind === 'insight') chips.push({text: 'Insight', tone: 'kind'});
  else if (p.kind === 'runnable') chips.push({text: 'Runnable', tone: 'kind'});
  if (p.tested_since) {
    const d = testedSinceText(p.tested_since);
    chips.push({text: d ? `Tested since ${d}` : 'Tested', tone: 'tested'});
  } else if ((p.made_by ?? '').startsWith('copilot_')) {
    chips.push({text: 'Researched, not tested', tone: 'warn'});
  }
  return chips;
};

export const profileByMap = (list: MapProfile[] | null | undefined): Map<number, MapProfile> => {
  const m = new Map<number, MapProfile>();
  for (const p of list ?? []) if (p && typeof p.journey_map_id === 'number') m.set(p.journey_map_id, p);
  return m;
};

const GOAL_LABELS: Record<string, string> = {
  proposed: 'Proposed by the copilot',
  confirmed: 'Confirmed',
  done: 'Done',
  dropped: 'Dropped',
};
export const goalStatusLabel = (s: string): string => GOAL_LABELS[s] ?? s;

export const noteProblem = (text: string): string | null => {
  const t = text.trim();
  if (t === '') return 'Write something first.';
  if (t.length > NOTE_MAX) return `A note is one short line (up to ${NOTE_MAX} characters).`;
  return null;
};

export const isSafeUrl = (u: string): boolean => {
  try {
    const p = new URL(u);
    return p.protocol === 'http:' || p.protocol === 'https:';
  } catch {
    return false;
  }
};

export const safeSources = (s: MapSource[] | null | undefined): (MapSource & {safe: boolean})[] =>
  (Array.isArray(s) ? s : [])
    .filter((x) => x && typeof x === 'object')
    .map((x) => ({title: String(x.title ?? '') || String(x.url ?? ''), url: String(x.url ?? ''), safe: isSafeUrl(String(x.url ?? ''))}));
