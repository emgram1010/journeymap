import type {XanoCopilotLevelRow, XanoCopilotSkill, XanoCopilotSkillVersion, XanoCopilotSkills} from '../xano';

/**
 * COP-9 — plain words for the copilot's skill library ("how I work"). Pure functions only; the
 * server decides and refuses again (copilot/skill_write, copilot/skill_undo, copilot/skill_switch).
 */

export const KIND_LABELS: Record<string, string> = {
  skill: 'Skill',
  exception: 'Exception',
  lesson: 'Lesson',
  link: 'Link',
};

export const STATUS_LABELS: Record<string, string> = {
  trial: 'On trial',
  trusted: 'Trusted',
  retired: 'Retired',
};

export const kindLabel = (k: string): string => KIND_LABELS[k] ?? k;
export const statusLabel = (s: string): string => STATUS_LABELS[s] ?? s;

/** Where an item applies, in plain words. `businessName` names a business id when known. */
export function scopeLabel(item: Pick<XanoCopilotSkill, 'scope_type' | 'scope_ref_id' | 'scope_text'>, businessName?: (id: number) => string | undefined): string {
  switch (item.scope_type) {
    case 'business':
      return `Only in ${businessName?.(item.scope_ref_id) ?? `business ${item.scope_ref_id}`}`;
    case 'map':
      return `Only on map ${item.scope_ref_id}`;
    case 'work_kind':
      return `Only for: ${item.scope_text}`;
    default:
      return 'Every business';
  }
}

/** Is this item switched off for this business? */
export const isOffFor = (off: XanoCopilotSkills['off'], skillId: number, businessId: number): boolean =>
  off.some((o) => o.skill_id === skillId && o.journey_architecture_id === businessId);

/** Live items first (by id), retired ones last. */
export function splitByStatus(items: XanoCopilotSkill[]): {live: XanoCopilotSkill[]; retired: XanoCopilotSkill[]} {
  const byId = (a: XanoCopilotSkill, b: XanoCopilotSkill) => a.id - b.id;
  return {
    live: items.filter((i) => i.status !== 'retired').sort(byId),
    retired: items.filter((i) => i.status === 'retired').sort(byId),
  };
}

/** One history line: who did what, and why. */
export function versionLine(v: Pick<XanoCopilotSkillVersion, 'version_no' | 'change' | 'changed_by' | 'reason' | 'undo_of_version_no'>): string {
  const who = v.changed_by === 'owner' ? 'You' : 'The copilot';
  let what: string;
  switch (v.change) {
    case 'create':
      what = `${who} created it`;
      break;
    case 'edit':
      what = `${who} changed it`;
      break;
    case 'retire':
      what = `${who} retired it`;
      break;
    case 'undo':
      what = `${who} put back version ${v.undo_of_version_no}`;
      break;
    default:
      what = `${who} saved it`;
  }
  const why = (v.reason ?? '').trim();
  return `v${v.version_no} · ${what}${why ? ` — ${why}` : ''}`;
}

/**
 * Undo for one change = put back the version before it. Version 1 (the creation) has nothing
 * before it, so it cannot be undone this way (retire it instead). Returns 0 when there is none.
 */
export const undoTarget = (v: Pick<XanoCopilotSkillVersion, 'version_no'>): number => (v.version_no > 1 ? v.version_no - 1 : 0);

/** The words that changed between two versions' text, for the history ("what changed"). */
export function changedFields(before: Partial<XanoCopilotSkill> | null | undefined, after: Partial<XanoCopilotSkill> | null | undefined): string[] {
  if (!before || !after) return [];
  const names: [keyof XanoCopilotSkill, string][] = [
    ['title', 'name'],
    ['body', 'what to do'],
    ['condition_text', 'when'],
    ['scope_type', 'where it applies'],
    ['scope_ref_id', 'where it applies'],
    ['scope_text', 'where it applies'],
    ['status', 'status'],
  ];
  const out: string[] = [];
  for (const [k, label] of names) {
    if ((before[k] ?? '') !== (after[k] ?? '') && !out.includes(label)) out.push(label);
  }
  return out;
}

/**
 * Approval levels: "write its own skills" is set ONCE, on the copilot's own business (the server
 * reads it from there, copilot/action_gate). So it is shown only when that business is picked,
 * and hidden everywhere else, where changing it would do nothing.
 */
export function visibleLevelRows(rows: XanoCopilotLevelRow[], archId: number, homeArchId: number): XanoCopilotLevelRow[] {
  return rows.filter((r) => r.key !== 'skill_write' || (homeArchId !== 0 && archId === homeArchId));
}

// ── COP-11: lock, kind of work, last used, and the size limit, in plain words ──

/** The fixed list of kinds of work (the server refuses anything else, E-COP-090). */
export const WORK_KINDS = ['map_building', 'planning', 'doing_work', 'research', 'general'] as const;

const WORK_KIND_LABELS: Record<string, string> = {
  map_building: 'Map building',
  planning: 'Planning',
  doing_work: 'Doing work',
  research: 'Research',
  general: 'General',
};

/** An unknown or missing kind reads as General (no tag = general). */
export const workKindLabel = (k: string | null | undefined): string => WORK_KIND_LABELS[k ?? ''] ?? 'General';

export const lockLabel = (locked: boolean): string => (locked ? 'Locked' : 'AI may change');

/** "23 of 50 items". */
export const itemCounter = (active: number, max: number): string => `${active} of ${max} items`;

/** "Never used", "Used today", "Used 3 days ago". lastUsedMs 0 = never. */
export function lastUsedLabel(lastUsedMs: number, nowMs: number): string {
  if (!lastUsedMs) return 'Never used';
  const days = Math.floor((nowMs - lastUsedMs) / 86_400_000);
  if (days <= 0) return 'Used today';
  return days === 1 ? 'Used 1 day ago' : `Used ${days} days ago`;
}

type SkillMetaLike = {
  items: {skill_id: number; last_used_at: number; not_used_in_days: boolean}[];
  metas: {skill_id: number; is_locked: boolean; work_kind: string; locked_by_user_id?: number; locked_at?: number}[];
};

export interface SkillInfo {
  locked: boolean;
  workKind: string;
  lastUsedAt: number;
  stale: boolean;
}

/** The side table joined to one item. No row = not locked, general, never used. */
export function skillInfo(meta: SkillMetaLike | null | undefined, skillId: number): SkillInfo {
  const m = meta?.metas.find((x) => x.skill_id === skillId);
  const u = meta?.items.find((x) => x.skill_id === skillId);
  return {
    locked: m?.is_locked === true,
    // an untouched enum is "" (not null), so `||`, never `??`
    workKind: m?.work_kind || 'general',
    lastUsedAt: u?.last_used_at || 0,
    stale: u?.not_used_in_days === true,
  };
}

/** The list after the two filters. kind "all" keeps every kind. */
export function filterSkills<T extends {id: number}>(items: T[], meta: SkillMetaLike | null | undefined, f: {kind: string; staleOnly: boolean}): T[] {
  return items.filter((i) => {
    const info = skillInfo(meta, i.id);
    return (f.kind === 'all' || info.workKind === f.kind) && (!f.staleOnly || info.stale);
  });
}

/** The server's bounds, said before the save (the server checks again). null = fine. */
export function limitsProblem(s: {max_active_items: number; max_load_words: number; stale_after_days: number; trial_min_uses?: number; trial_max_overrides?: number}): string | null {
  const within = (n: number, lo: number, hi: number) => Number.isInteger(n) && n >= lo && n <= hi;
  if (!within(s.max_active_items, 10, 200)) return 'The most items must be between 10 and 200.';
  if (!within(s.max_load_words, 1000, 20000)) return 'The most words loaded per run must be between 1,000 and 20,000.';
  if (!within(s.stale_after_days, 7, 365)) return 'Flag unused items after between 7 and 365 days.';
  if (s.trial_min_uses !== undefined && !within(s.trial_min_uses, 1, 50)) return 'Uses before a skill is trusted must be between 1 and 50.';
  if (s.trial_max_overrides !== undefined && !within(s.trial_max_overrides, 1, 10)) return 'Overrides before a trial skill is switched off must be between 1 and 10.';
  return null;
}

/** COP-9-05: "Trial: 3 of 5 uses" (capped at the target, since the rule promotes overnight). */
export const trialProgress = (uses: number, target: number): string => `Trial: ${Math.min(uses, target)} of ${target} uses`;

// ── COP-9 story 07: the weekly "what I learned" digest ──

export interface DigestVersion {
  id: number;
  created_at: number;
  skill_id: number;
  version_no: number;
  change: string;
  changed_by: string;
  reason: string;
  undo_of_version_no: number;
}
export interface DigestSkill {
  id: number;
  title: string;
  kind: string;
  version_no: number;
  status: string;
}
export interface DigestRefusal {
  created_at: number;
  error_code: string;
  message: string;
  step: string;
}
export type DigestKind = 'new' | 'changed' | 'promoted' | 'switched_off' | 'retired' | 'undone' | 'refused';
export interface DigestLine {
  kind: DigestKind;
  text: string;
  at: number;
  skillId: number;
  versionId: number;
  /** The version Undo would put back; 0 = no Undo for this line. */
  undoTo: number;
}

// The trial rule's own reasons (copilot/skill_trial_review) - matched by their fixed start.
const TRUSTED_PREFIX = 'Trial rule: trusted';
const SWITCHED_PREFIX = 'Trial rule: switched off';

/**
 * Sorts a week of raw history into what needs reading (flagged: a trial switched off, a refusal) and
 * the rest (collapsed). The owner pressing Lock / Unlock is left out: it is not something the copilot
 * learned. Undo is offered only when the item is still at that line's version (otherwise putting back
 * the earlier one would throw away a later change) and an earlier version exists.
 */
export function buildDigest(input: {versions: DigestVersion[]; skills: DigestSkill[]; refusals: DigestRefusal[]}): {
  flagged: DigestLine[];
  other: DigestLine[];
  empty: boolean;
} {
  const byId = new Map(input.skills.map((s) => [s.id, s]));
  const lines: DigestLine[] = [];
  for (const v of input.versions) {
    if (v.reason === 'locked' || v.reason === 'unlocked') continue;
    const s = byId.get(v.skill_id);
    const name = `${kindLabel(s?.kind ?? 'skill')} #${v.skill_id}${s ? ` "${s.title}"` : ''}`;
    let kind: DigestKind;
    let text: string;
    if (v.change === 'create') {
      kind = 'new';
      text = `New: ${name}`;
    } else if ((v.reason ?? '').startsWith(TRUSTED_PREFIX)) {
      kind = 'promoted';
      text = `${name} passed its trial and is now trusted`;
    } else if ((v.reason ?? '').startsWith(SWITCHED_PREFIX)) {
      kind = 'switched_off';
      text = `${name} was switched off: you overrode it during its trial`;
    } else if (v.change === 'retire') {
      kind = 'retired';
      text = `${v.changed_by === 'owner' ? 'You retired' : 'The copilot retired'} ${name}`;
    } else if (v.change === 'undo') {
      kind = 'undone';
      text = `You put back an earlier version of ${name}`;
    } else {
      kind = 'changed';
      text = `${v.changed_by === 'owner' ? 'You changed' : 'The copilot changed'} ${name}${v.reason ? `: ${v.reason}` : ''}`;
    }
    const current = s?.version_no === v.version_no;
    lines.push({kind, text, at: v.created_at, skillId: v.skill_id, versionId: v.id, undoTo: current && v.version_no > 1 ? v.version_no - 1 : 0});
  }
  // The same refusal repeated is one line with a count, so a stubborn loop does not bury everything else.
  const groups = new Map<string, {r: DigestRefusal; n: number; at: number}>();
  for (const r of input.refusals) {
    const key = `${r.error_code}::${r.message}`;
    const g = groups.get(key);
    if (g) {
      g.n += 1;
      g.at = Math.max(g.at, r.created_at);
    } else groups.set(key, {r, n: 1, at: r.created_at});
  }
  for (const {r, n, at} of groups.values()) {
    const times = n > 1 ? ` ${n} times` : '';
    lines.push({kind: 'refused', text: `Refused${times} (${r.error_code || 'no code'}): ${r.message}`, at, skillId: 0, versionId: 0, undoTo: 0});
  }
  lines.sort((a, b) => b.at - a.at);
  const flag = (l: DigestLine) => l.kind === 'switched_off' || l.kind === 'refused';
  return {flagged: lines.filter(flag), other: lines.filter((l) => !flag(l)), empty: lines.length === 0};
}
