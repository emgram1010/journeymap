// REQ-1 — requirements (what a person can hold and a step can need), holdings and needs, as the
// screens show them. The server decides and re-checks all of it (functions/req/*); this is the
// TypeScript twin of the name rule and the date rule, plus the sentences. Pure functions only.

export const REQUIREMENTS_PER_ACCOUNT_LIMIT = 200;
export const NEEDS_PER_STEP_LIMIT = 10;
export const NAME_MAX = 60;
export const ENDS_SOON_DAYS = 30;

export type Strength = 'hard' | 'soft';

/** What is shown: spaces tidied (trim, inner runs collapsed to one), case kept. */
export const cleanName = (raw: string): string => (raw ?? '').replace(/\s+/g, ' ').trim();

/** The key two names are compared by: tidied, then lower case. Same rule as req/normalize_name. */
export const nameKey = (raw: string): string => cleanName(raw).toLowerCase();

export type NameCheck = {ok: true} | {ok: false; code: string; message: string};

/** The name rules. The server checks the same ones again; this keeps the user's typing and says why. */
export function validateName(raw: string): NameCheck {
  const name = cleanName(raw);
  if (name === '') return {ok: false, code: 'E-REQ-001', message: 'Give the requirement a name. (E-REQ-001)'};
  if (name.length > NAME_MAX) return {ok: false, code: 'E-REQ-008', message: `A name can be at most ${NAME_MAX} characters. (E-REQ-008)`};
  if (/<[a-zA-Z][^>]*>/.test(name)) return {ok: false, code: 'E-REQ-002', message: 'A name cannot contain HTML tags. (E-REQ-002)'};
  return {ok: true};
}

/** A recorded holding. held_until is "YYYY-MM-DD", or empty for no end. */
export interface Holding {
  requirement_id: number;
  held_until?: string | null;
}

export interface HoldingState {
  held: boolean;
  endsSoon: boolean;
  /** The end date, or "" when there is none. */
  until: string;
  daysLeft: number | null;
}

const DAY_MS = 86_400_000;
const isoDay = (d: string): number => Date.UTC(Number(d.slice(0, 4)), Number(d.slice(5, 7)) - 1, Number(d.slice(8, 10)));

/**
 * Is it held on the DATE OF THE WORK? An empty end date (any empty form) means no end. The last day
 * counts: held until 2027-03-31 means held on 2027-03-31, not on 2027-04-01. Never compared to a clock.
 */
export function holdingState(holding: Holding, onDate: string): HoldingState {
  const until = typeof holding.held_until === 'string' ? holding.held_until.trim() : '';
  if (!/^\d{4}-\d{2}-\d{2}$/.test(until)) return {held: true, endsSoon: false, until: '', daysLeft: null};
  const daysLeft = Math.round((isoDay(until) - isoDay(onDate)) / DAY_MS);
  const held = daysLeft >= 0;
  return {held, endsSoon: held && daysLeft <= ENDS_SOON_DAYS, until, daysLeft};
}

export function endsSoonLabel(state: HoldingState): string {
  if (!state.endsSoon || state.daysLeft === null) return '';
  if (state.daysLeft === 0) return 'Ends today';
  return `Ends in ${state.daysLeft} day${state.daysLeft === 1 ? '' : 's'}`;
}

/** The plan's people list: does each person have a lasting profile? */
export function personLinkLabel(p: {profile_id?: number | null; profile_name?: string | null}): string {
  return p.profile_id ? `Profile: ${p.profile_name ?? ''}`.trim() : 'No profile';
}

export const strengthLabel = (s: Strength): string => (s === 'hard' ? 'Must have' : 'Preferred');
export const nextStrength = (s: Strength): Strength => (s === 'hard' ? 'soft' : 'hard');

export function needsLine(needs: {name: string; strength: Strength}[]): string {
  if (needs.length === 0) return 'No needs';
  return `Needs: ${needs.map(n => `${n.name} (${n.strength === 'hard' ? 'must' : 'preferred'})`).join(', ')}`;
}

export type AddNeedCheck = {ok: true} | {ok: false; message: string};

/** May this need be added to the step? Changing hard/soft on an existing need is not an add. */
export function addNeedAllowed(a: {currentCount: number; alreadyOnStep: boolean; archived: boolean}): AddNeedCheck {
  if (a.alreadyOnStep) return {ok: true};
  if (a.archived) return {ok: false, message: 'That requirement is archived, so it cannot be added to a step. (E-REQ-030)'};
  if (a.currentCount >= NEEDS_PER_STEP_LIMIT) return {ok: false, message: `A step can have at most ${NEEDS_PER_STEP_LIMIT} needs. (E-REQ-032)`};
  return {ok: true};
}

// ── REQ-1 story 05: frozen needs and their tamper-evidence hash ──────────────────────────────────
export interface FrozenNeed {
  stage_key: string;
  lens_key: string;
  requirement_id: number;
  strength: Strength;
}

/** The sha256 of the empty string: the pinned "no needs" hash. A version with no needs stores no hash row. */
export const NO_NEEDS_HASH = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

const padId = (id: number): string => `0000000000${id}`.slice(-10);
const sortKey = (n: FrozenNeed): string => `${n.stage_key} ${n.lens_key} ${padId(n.requirement_id)}`;

/**
 * The canonical string the needs hash is made from. Same rule as req/needs_hash on the server: sorted by
 * stage key, then row key, then requirement id (padded to 10 digits so text order is numeric order), each
 * need written as stage_key::lens_key::requirement_id::strength; and nothing else. Built by explicit
 * concatenation, never through a JSON encoder (encoders disagree on key order, spaces and escaping).
 * Hash it with sha256 (the test does, with node's crypto).
 */
export function needsCanonicalString(needs: FrozenNeed[]): string {
  const sorted = [...needs].sort((a, b) => {
    const ka = sortKey(a);
    const kb = sortKey(b);
    return ka < kb ? -1 : ka > kb ? 1 : 0;
  });
  return sorted.map(n => `${n.stage_key}::${n.lens_key}::${n.requirement_id}::${n.strength};`).join('');
}
