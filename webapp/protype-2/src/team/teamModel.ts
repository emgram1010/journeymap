/**
 * USR-1 — the Team page's pure logic.
 *
 * Everything here is a COURTESY. The server re-checks every one of these rules
 * and is the only authority; this module exists so a control can be greyed out
 * before the user clicks it, and so a refusal can be explained in a sentence.
 *
 * Two constraints from CLAUDE.md are baked into the merge, and both have cost
 * this project real time before:
 *
 *  - An untouched `bool` column reads back as `false`, and an untouched `enum`
 *    reads back as `""` — not `null`. So `??` does not fall through for either,
 *    and `value == null` is true for `0`/`""`/`false`/`[]` in the Xano engine.
 *    "Was this ever set?" is therefore answered by the PRESENCE OF A ROW, never
 *    by the falsiness of a field.
 *  - A side table is invisible to the original table's list endpoint. The
 *    statuses arrive from their own fetch and are merged here, explicitly.
 */

export type Role = 'admin' | 'member';

/** As returned by `GET account/my_team_members`. */
export interface RawMember {
  id: number;
  name: string;
  email: string;
  account_id?: number | null;
  role?: string | null;
}

/** As returned by `GET user_status` — the side table, one row per user AT MOST. */
export interface RawStatus {
  user_id: number;
  account_id?: number | null;
  is_active: boolean;
  deactivated_at?: number | string | null;
  deactivated_by_user_id?: number | null;
}

export interface TeamMember {
  id: number;
  name: string;
  email: string;
  account_id: number | null;
  role: Role;
  is_active: boolean;
  deactivated_at: number | string | null;
  /**
   * USR-2. Always present and always complete — all three keys, defaulting to
   * `false`. A person with no grant rows is a person with nothing, not a person
   * whose access is unknown, and giving callers an `undefined` to handle would
   * invite exactly the `??` mistakes this file keeps warning about.
   */
  modules: ModuleGrants;
}

/** The only two roles there are. A value outside this list is never written. */
export const ROLES: readonly Role[] = ['admin', 'member'] as const;

export function isValidRole(value: unknown): value is Role {
  return value === 'admin' || value === 'member';
}

/**
 * Anything that is not exactly "admin" is a member.
 *
 * Deliberately not `role ?? 'member'`: an untouched enum column arrives as `""`,
 * which sails straight through `??` and would then fail an `=== 'admin'` test
 * anyway — but would also fail a `=== 'member'` test, leaving a third state
 * nothing handles. Collapsing to two states here means the rest of the file
 * only ever sees two.
 */
function normalizeRole(role: unknown): Role {
  return role === 'admin' ? 'admin' : 'member';
}

/**
 * Join the people to their status rows.
 *
 * A member with NO status row is active — that is what absence means, and it
 * is why no backfill is needed. A row that exists but whose `is_active` is not
 * exactly `true` is inactive; a null or missing value there means the row was
 * written wrong, and the safe reading of a broken status row is "switched off",
 * not "let them in".
 */
export function mergeTeam(
  members: RawMember[],
  statuses: RawStatus[],
  grants: RawGrant[] = [],
): TeamMember[] {
  const byUserId = new Map<number, RawStatus>();
  for (const status of statuses) {
    byUserId.set(status.user_id, status);
  }
  // USR-2. A third side table, merged the same way and for the same reason:
  // the people endpoint queries `user`'s own columns and will never join this.
  const grantsByUserId = mergeGrants(grants);

  return members.map((member) => {
    const status = byUserId.get(member.id);
    return {
      id: member.id,
      name: member.name,
      email: member.email,
      account_id: member.account_id ?? null,
      role: normalizeRole(member.role),
      is_active: status ? status.is_active === true : true,
      deactivated_at: status?.deactivated_at ?? null,
      modules: grantsByUserId.get(member.id) ?? noModules(),
    };
  });
}

/** Admins who could actually sign in and administer something right now. */
export function activeAdminCount(team: TeamMember[]): number {
  return team.filter((m) => m.role === 'admin' && m.is_active).length;
}

export function canManageTeam(viewer: {role?: string | null} | null | undefined): boolean {
  return normalizeRole(viewer?.role) === 'admin' && viewer != null;
}

/**
 * Codes are the catalog's, so the UI and the server say the same thing when
 * they refuse the same action. `null` means "nothing stops this".
 */
export type BlockCode =
  | 'E-USR-001'
  | 'E-USR-002'
  | 'E-USR-003'
  | 'E-USR-004'
  | 'E-USR-007'
  | 'E-USR-008'
  | 'E-USR-009'
  | 'E-USR-011'
  | 'E-USR-012'
  | 'E-USR-014'
  | 'E-USR-015'
  | 'E-USR-020';

interface Actor {
  id: number;
  account_id?: number | null;
  role?: string | null;
}

/**
 * Shared preamble for both kinds of change.
 *
 * Order matters and is the same on the server: not-an-admin, then
 * not-in-your-account. The account check returns a not-found-shaped code on
 * purpose — a refusal should not confirm that a user id exists elsewhere.
 */
function blockedByCommon(actor: Actor | null | undefined, targetId: number, team: TeamMember[]): BlockCode | null {
  if (!canManageTeam(actor)) return 'E-USR-001';
  const target = team.find((m) => m.id === targetId);
  if (!target) return 'E-USR-002';
  if (actor!.account_id != null && target.account_id !== actor!.account_id) return 'E-USR-002';
  return null;
}

/**
 * Would this change leave the account with nobody able to administer it?
 *
 * `lostAdminId` is the admin who would stop counting — demoted, or switched
 * off. Promotions and reactivations never reduce the count, so they pass.
 */
function wouldStrandAccount(team: TeamMember[], lostAdminId: number | null): boolean {
  if (lostAdminId == null) return false;
  const remaining = team.filter((m) => m.role === 'admin' && m.is_active && m.id !== lostAdminId);
  return remaining.length === 0;
}

export function roleChangeBlockedBy(
  actor: Actor | null | undefined,
  targetId: number,
  newRole: string,
  team: TeamMember[],
): BlockCode | null {
  const common = blockedByCommon(actor, targetId, team);
  if (common) return common;
  if (!isValidRole(newRole)) return 'E-USR-009';

  const target = team.find((m) => m.id === targetId)!;
  const demoting = target.role === 'admin' && newRole === 'member' && target.is_active;

  // Checked BEFORE the self-change rule: when the sole admin demotes
  // themselves both apply, and "that would leave nobody in charge" is the
  // reason worth showing.
  if (wouldStrandAccount(team, demoting ? target.id : null)) return 'E-USR-003';
  if (actor!.id === targetId) return 'E-USR-004';
  return null;
}

export function statusChangeBlockedBy(
  actor: Actor | null | undefined,
  targetId: number,
  nextActive: boolean,
  team: TeamMember[],
): BlockCode | null {
  const common = blockedByCommon(actor, targetId, team);
  if (common) return common;

  const target = team.find((m) => m.id === targetId)!;
  const switchingOffAnAdmin = !nextActive && target.role === 'admin' && target.is_active;

  if (wouldStrandAccount(team, switchingOffAnAdmin ? target.id : null)) return 'E-USR-003';
  if (actor!.id === targetId) return 'E-USR-004';
  return null;
}

/* ────────────────────────────────────────────────────────────────────────────
 * Full CRUD — added 2026-10-22 at the founder's request.
 *
 * The three rules below are MIRRORS of server rules, and mirrors are the thing
 * LOG-1 warned about: a copy of a rule eventually disagrees with the original
 * and sounds just as confident. They are kept because a form that only learns
 * "that password is too short" after a round trip is a worse form — but every
 * one of them is also enforced in the endpoint, the endpoint is the authority,
 * and the shapes here are deliberately the simplest possible restatement so
 * drift is obvious rather than subtle.
 *
 * What is NOT mirrored, on purpose:
 *   - `E-USR-013` (the person has work, so they cannot be deleted). The client
 *     cannot see the architectures, planner agents, agent profiles and
 *     performed steps that decide it, and guessing would be worse than
 *     waiting: a cheerful "Remove" that the server then refuses is honest,
 *     and a greyed-out button the client guessed wrong about is not.
 *   - `E-USR-008` for an address that belongs to someone in ANOTHER account.
 *     Emails are unique product-wide, but this client can only see its own
 *     account's people, so a clash it cannot see comes back from the server.
 * ──────────────────────────────────────────────────────────────────────────── */

/**
 * Deliberately loose: something@something.something.
 *
 * The server's regex is the same shape. The point is to catch a typo before it
 * becomes a person who can never sign in, not to adjudicate RFC 5322 — and an
 * over-strict check here would reject real addresses the server would accept,
 * which is the worse failure of the two.
 */
export function emailLooksRight(email: string): boolean {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim());
}

/**
 * The same three rules the `user.password` column's own validators enforce
 * (`min:8|minAlpha:1|minDigit:1`), so the admin is told before the round trip
 * rather than by a database error.
 */
export function passwordMeetsRules(password: string): boolean {
  return password.length >= 8 && /[A-Za-z]/.test(password) && /[0-9]/.test(password);
}

/** What the Add form collects. */
export interface NewPersonDraft {
  name: string;
  email: string;
  password: string;
  role: string;
}

/** What the inline Edit row collects. Either field may be left as it was. */
export interface ProfileDraft {
  name: string;
  email: string;
}

/**
 * Can this admin add this person?
 *
 * Validation order matches the endpoint's: the missing-field check first, then
 * the shape of the email, then the password, then the role. Same order means
 * the same code comes back from both sides for the same bad form, which is
 * what makes a disagreement between them visible instead of confusing.
 */
export function createBlockedBy(
  actor: Actor | null | undefined,
  draft: NewPersonDraft,
  team: TeamMember[],
): BlockCode | null {
  if (!canManageTeam(actor)) return 'E-USR-001';

  const name = draft.name.trim();
  const email = draft.email.trim().toLowerCase();
  if (name === '' || email === '') return 'E-USR-011';
  if (!emailLooksRight(email)) return 'E-USR-014';
  if (!passwordMeetsRules(draft.password)) return 'E-USR-012';
  if (!isValidRole(draft.role)) return 'E-USR-009';

  // Only the clashes this client can actually see. A clash with somebody in
  // another account is invisible here and comes back from the server.
  if (team.some((m) => m.email.trim().toLowerCase() === email)) return 'E-USR-008';
  return null;
}

/**
 * Can this admin correct this person's name or email?
 *
 * SELF-EDITING IS ALLOWED, unlike role and status: `E-USR-004` exists to stop
 * the sole admin stepping down or switching themselves off, and fixing your
 * own surname cannot strand an account. The endpoint agrees — it has no
 * self-check at all.
 */
export function profileUpdateBlockedBy(
  actor: Actor | null | undefined,
  targetId: number,
  draft: ProfileDraft,
  team: TeamMember[],
): BlockCode | null {
  const common = blockedByCommon(actor, targetId, team);
  if (common) return common;

  const name = draft.name.trim();
  const email = draft.email.trim().toLowerCase();
  if (name === '' && email === '') return 'E-USR-011';
  // An email that is being SET has to look like one. An empty email means
  // "leave it", which is not an error — the endpoint reads "" the same way,
  // because an omitted optional text input arrives as "" and never as null.
  if (email !== '' && !emailLooksRight(email)) return 'E-USR-014';

  if (email !== '' && team.some((m) => m.id !== targetId && m.email.trim().toLowerCase() === email)) {
    return 'E-USR-008';
  }
  return null;
}

/**
 * Can this admin remove this person outright?
 *
 * Everything the client can know, and nothing it cannot. The last-admin rule
 * applies because deleting an admin reduces the admin count exactly as
 * demoting one does; `E-USR-013` is the server's to raise.
 */
export function deleteBlockedBy(
  actor: Actor | null | undefined,
  targetId: number,
  team: TeamMember[],
): BlockCode | null {
  const common = blockedByCommon(actor, targetId, team);
  if (common) return common;

  const target = team.find((m) => m.id === targetId)!;

  // An ACTIVE admin is the only kind that counts, so removing an already
  // switched-off admin cannot strand the account — `wouldStrandAccount`
  // reaches the same answer, and this passes the target only when they are
  // currently counted.
  if (wouldStrandAccount(team, target.role === 'admin' && target.is_active ? target.id : null)) {
    return 'E-USR-003';
  }
  // E-USR-015, not E-USR-004: removal is a different action from a role
  // change or a deactivation, and one code means one thing (GUARD-1-01).
  if (actor!.id === targetId) return 'E-USR-015';
  return null;
}

/* ────────────────────────────────────────────────────────────────────────────
 * USR-2 — module access.
 *
 * A grant says WHICH ROOMS you may enter. Tenancy says whose things you may
 * touch once inside. Both still run, in that order, on every request, and
 * nothing here replaces `assert_same_account` or `visible_map_ids`.
 *
 * Same standing caveat as the CRUD rules above: every rule in this section is
 * also enforced on the server, which is the only authority. These exist so a
 * toggle can be disabled before it is clicked and a refusal can be explained
 * in a sentence.
 *
 * The load-bearing reading rule, and it is the whole reason grants arrive from
 * their own fetch and are merged explicitly:
 *
 *   ABSENCE OF A ROW MEANS NOT GRANTED, and so does `granted: false`.
 *
 * Those two are deliberately collapsed to the same answer here. On the server
 * they are different rows and only one of them records who revoked it and
 * when — but to a caller asking "may they enter?", "never granted" and
 * "granted then revoked" are the same no, and treating them differently in the
 * UI would mean inventing a third state nothing renders.
 * ──────────────────────────────────────────────────────────────────────────── */

export type ModuleKey = 'intelligence' | 'planning' | 'execution';

/**
 * The allow-list, and the only one on this side. The server's twin lives in
 * `functions/usr/module_keys.xs`; a fourth module is a change to both, which is
 * the point of a key rather than an enum column — config, not a migration.
 */
export const MODULES: readonly ModuleKey[] = ['intelligence', 'planning', 'execution'] as const;

/** What the founder calls them. The sidebar already uses these three words. */
export const MODULE_LABELS: Record<ModuleKey, string> = {
  intelligence: 'Intelligent Layer',
  planning: 'Planner',
  execution: 'Execution',
};

export type ModuleGrants = Record<ModuleKey, boolean>;

export function isValidModule(value: unknown): value is ModuleKey {
  return value === 'intelligence' || value === 'planning' || value === 'execution';
}

/** A new person has nothing until an admin ticks a box — the founder's call. */
export function noModules(): ModuleGrants {
  return {intelligence: false, planning: false, execution: false};
}

/** As returned by `GET user_module_access` — one row per (user, module) AT MOST. */
export interface RawGrant {
  user_id: number;
  module?: string | null;
  granted?: boolean | null;
  account_id?: number | null;
}

/**
 * Fold grant rows into one all-three answer per user.
 *
 * `granted === true` is tested explicitly, never `!= null` and never `??`: a
 * bool column that was never written reads back as `false`, and `false == null`
 * is TRUE in the Xano engine (CLAUDE.md, VAR-1). A row whose `granted` is null,
 * missing or anything other than exactly `true` is NOT a grant — the safe
 * reading of a broken permission row is "locked", not "open".
 *
 * A row naming a module outside the allow-list is ignored rather than crashing
 * the page. It cannot be clicked, so it cannot be fixed from here either, and a
 * blank Team page would hide the nine rows that are fine.
 */
export function mergeGrants(grants: RawGrant[]): Map<number, ModuleGrants> {
  const byUserId = new Map<number, ModuleGrants>();
  for (const grant of grants) {
    if (!isValidModule(grant.module)) continue;
    const current = byUserId.get(grant.user_id) ?? noModules();
    current[grant.module] = grant.granted === true;
    byUserId.set(grant.user_id, current);
  }
  return byUserId;
}

/** Does this viewer hold this module? The one test the nav and the routes share. */
export function hasModule(
  viewer: {modules?: Partial<ModuleGrants> | null} | null | undefined,
  module: ModuleKey,
): boolean {
  return viewer?.modules?.[module] === true;
}

/**
 * Can this person reach anything at all?
 *
 * Needed for its own sake: a user with no grants must land on a page that
 * explains itself, and every other landing target is itself gated. Without
 * this test the redirect chain has no terminal state and loops.
 */
export function hasAnyModule(viewer: {modules?: Partial<ModuleGrants> | null} | null | undefined): boolean {
  return MODULES.some((module) => hasModule(viewer, module));
}

/** One change the admin has asked for. `granted: false` is a revoke. */
export interface GrantChange {
  module: string;
  granted: boolean;
}

/**
 * Can this admin change this person's module access?
 *
 * Order matches the endpoint's: admin, then same-account, then the module keys,
 * then the self rule. `E-USR-020` rather than `E-USR-004`, because one code
 * means one thing (GUARD-1-01) and `E-USR-004` already says "your own role or
 * switch yourself off" — a different sentence to a different reader.
 *
 * An EMPTY list of changes is not an error. It is a no-op, the server treats it
 * as one, and refusing it would make an unchanged form impossible to submit.
 */
export function grantChangeBlockedBy(
  actor: Actor | null | undefined,
  targetId: number,
  changes: GrantChange[],
  team: TeamMember[],
): BlockCode | null {
  const common = blockedByCommon(actor, targetId, team);
  if (common) return common;

  for (const change of changes) {
    if (!isValidModule(change.module)) return 'E-USR-007';
  }

  // Nobody edits their own access, in either direction. The sole admin
  // revoking their own Intelligent Layer is the lockout this prevents, and
  // allowing the grant direction while refusing the revoke would mean a rule
  // that reads differently depending on which way the switch moved.
  if (actor!.id === targetId) return 'E-USR-020';
  return null;
}
