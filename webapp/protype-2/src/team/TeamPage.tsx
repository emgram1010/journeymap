import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {AlertCircle, Check, Loader2, Plus, ShieldCheck, Trash2, Users, X} from 'lucide-react';
import {useAuth} from '../AuthContext';
import {
  createUser,
  deleteUser,
  listTeamMembers,
  listUserModuleAccess,
  listUserStatuses,
  setUserActive,
  setUserModuleAccess,
  setUserRole,
  updateUserInfo,
  XanoHttpError,
} from '../xano';
import {getCatalogEntry} from '../ops/errorCatalog';
import {
  canManageTeam,
  createBlockedBy,
  deleteBlockedBy,
  grantChangeBlockedBy,
  mergeTeam,
  profileUpdateBlockedBy,
  roleChangeBlockedBy,
  statusChangeBlockedBy,
  MODULES,
  MODULE_LABELS,
  type ModuleKey,
  type NewPersonDraft,
  type Role,
  type TeamMember,
} from './teamModel';

/**
 * USR-1 — Manage users.
 *
 * Two fetches, merged. `GET account/my_team_members` returns the people;
 * `GET user_status` returns the side table. They are deliberately NOT joined
 * on the server: a field that really lives in a side table is invisible to
 * the original table's list endpoint, which is the AUTH-1 trap — the write
 * path looks perfect and the value reads `undefined` forever.
 *
 * Every control here is greyed out by the same rules the server enforces
 * (`teamModel.ts`), and every save still goes through the server, which
 * refuses again. If the two ever disagree, the server wins and its message is
 * what the user sees.
 *
 * ADMIN-ONLY SINCE 2026-10-22. The route itself turns a member away, at the
 * founder's instruction — "the only difference is that admins can have access
 * to the user management module". The read-only rendering below is kept
 * anyway: hiding a page is not a permission, the endpoints are what actually
 * refuse, and a page that renders nothing dangerous when its guard is
 * bypassed is one less thing to get wrong.
 */

const EMPTY_DRAFT: NewPersonDraft = {name: '', email: '', password: '', role: 'member'};

export default function TeamPage() {
  const {user} = useAuth();
  const [team, setTeam] = useState<TeamMember[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [savingId, setSavingId] = useState<number | null>(null);
  const [savedId, setSavedId] = useState<number | null>(null);

  // Adding someone
  const [isAdding, setIsAdding] = useState(false);
  const [draft, setDraft] = useState<NewPersonDraft>(EMPTY_DRAFT);
  const [isCreating, setIsCreating] = useState(false);

  // Correcting someone, one row at a time
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editDraft, setEditDraft] = useState({name: '', email: ''});

  // Removing someone. Two presses, never one — this is the only irreversible
  // control on the page.
  const [confirmRemoveId, setConfirmRemoveId] = useState<number | null>(null);

  const isAdmin = canManageTeam(user);

  const load = useCallback(async () => {
    setError(null);
    try {
      // Three fetches now, and all three for the same reason: `user_status`
      // and `user_module_access` are side tables, and a side table is
      // invisible to the original table's list endpoint (the AUTH-1 trap).
      const [members, statuses, grants] = await Promise.all([
        listTeamMembers(),
        listUserStatuses(),
        listUserModuleAccess(),
      ]);
      setTeam(mergeTeam(members, statuses, grants));
    } catch {
      setError('Unable to load your team right now.');
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const activeAdmins = useMemo(() => team.filter((m) => m.role === 'admin' && m.is_active).length, [team]);

  /**
   * One shared save path for every change on this page.
   *
   * `predictedBlock` is the client-side rule check. It exists to explain a
   * refusal before the round trip, not to authorise anything — a null from it
   * is not permission, it only means "nothing we know of stops this".
   */
  const apply = useCallback(
    async (rowId: number | null, predictedBlock: string | null, action: () => Promise<unknown>, done?: string) => {
      if (predictedBlock) {
        setError(getCatalogEntry(predictedBlock)?.user_message ?? 'That change is not allowed.');
        return false;
      }
      setSavingId(rowId);
      setError(null);
      setNotice(null);
      setSavedId(null);
      try {
        await action();
        await load();
        if (rowId != null) {
          setSavedId(rowId);
          setTimeout(() => setSavedId(null), 2500);
        }
        if (done) setNotice(done);
        return true;
      } catch (err) {
        // The server's own sentence, when it sent one — it is the authority,
        // and it may be refusing for a reason the client could not see
        // (E-USR-013 and an email taken in another account are both exactly
        // that).
        const serverMessage = err instanceof XanoHttpError ? err.serverMessage : null;
        setError(serverMessage ?? 'That change could not be saved. Please try again.');
        return false;
      } finally {
        setSavingId(null);
      }
    },
    [load],
  );

  const changeRole = (member: TeamMember, nextRole: Role) =>
    apply(member.id, roleChangeBlockedBy(user, member.id, nextRole, team), () => setUserRole(member.id, nextRole));

  const changeActive = (member: TeamMember, nextActive: boolean) =>
    apply(member.id, statusChangeBlockedBy(user, member.id, nextActive, team), () =>
      setUserActive(member.id, nextActive),
    );

  /**
   * USR-2 — one checkbox, one request.
   *
   * The server takes one module per call, so there is nothing to batch and no
   * half-applied state to worry about. A refusal leaves the box exactly as it
   * was, because the box is drawn from `team`, which is only replaced by a
   * successful reload.
   */
  const changeModule = (member: TeamMember, module: ModuleKey, next: boolean) =>
    apply(member.id, grantChangeBlockedBy(user, member.id, [{module, granted: next}], team), () =>
      setUserModuleAccess(member.id, module, next),
    );

  const addPerson = async () => {
    setIsCreating(true);
    const ok = await apply(
      null,
      createBlockedBy(user, draft, team),
      () =>
        createUser({
          name: draft.name.trim(),
          email: draft.email.trim(),
          password: draft.password,
          role: draft.role as Role,
        }),
      `${draft.name.trim()} can sign in with the email and password you set. Tell them, and ask them to change it.`,
    );
    setIsCreating(false);
    if (ok) {
      // Cleared on success and ONLY on success: a rejected save keeps the
      // admin's typing, which is the house rule for every form in this app.
      setDraft(EMPTY_DRAFT);
      setIsAdding(false);
    }
  };

  const startEditing = (member: TeamMember) => {
    setEditingId(member.id);
    setEditDraft({name: member.name, email: member.email});
    setError(null);
  };

  const saveEdit = async (member: TeamMember) => {
    const ok = await apply(member.id, profileUpdateBlockedBy(user, member.id, editDraft, team), () =>
      updateUserInfo(member.id, {name: editDraft.name.trim(), email: editDraft.email.trim()}),
    );
    if (ok) setEditingId(null);
  };

  const removePerson = async (member: TeamMember) => {
    const ok = await apply(
      member.id,
      deleteBlockedBy(user, member.id, team),
      () => deleteUser(member.id),
      `${member.name || member.email} has been removed.`,
    );
    if (ok) setConfirmRemoveId(null);
  };

  if (isLoading) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Loader2 className="w-5 h-5 animate-spin text-zinc-400" />
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto bg-zinc-50">
      <div className="max-w-4xl mx-auto px-6 py-8">
        <header className="mb-6 flex items-start justify-between gap-4">
          <div>
            <h1 className="text-xl font-semibold text-zinc-900 flex items-center gap-2">
              <Users className="w-5 h-5 text-zinc-500" />
              Manage users
            </h1>
            <p className="text-sm text-zinc-500 mt-1">
              {isAdmin
                ? 'Add someone, correct their details, change who is an admin, or switch them off without losing their work.'
                : 'Everyone in your account. Only an admin can make changes here.'}
            </p>
          </div>
          {isAdmin && !isAdding && (
            <button
              type="button"
              onClick={() => {
                setIsAdding(true);
                setError(null);
                setNotice(null);
              }}
              className="shrink-0 inline-flex items-center gap-1.5 rounded-md bg-zinc-900 px-3 py-2 text-sm font-medium text-white hover:bg-zinc-800"
            >
              <Plus className="w-4 h-4" />
              Add someone
            </button>
          )}
        </header>

        {error && (
          <div
            role="alert"
            className="mb-4 flex items-start gap-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900"
          >
            <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {notice && (
          <div
            role="status"
            className="mb-4 flex items-start gap-2 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-900"
          >
            <Check className="w-4 h-4 mt-0.5 shrink-0" />
            <span>{notice}</span>
          </div>
        )}

        {/* ── Add someone ──────────────────────────────────────────────────── */}
        {isAdmin && isAdding && (
          <form
            id="add-person-form"
            className="mb-5 rounded-lg border border-zinc-200 bg-white p-4"
            onSubmit={(e) => {
              e.preventDefault();
              void addPerson();
            }}
          >
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-sm font-semibold text-zinc-900">Add someone to your account</h2>
              <button
                type="button"
                aria-label="Cancel"
                onClick={() => {
                  setIsAdding(false);
                  setDraft(EMPTY_DRAFT);
                }}
                className="text-zinc-400 hover:text-zinc-700"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="grid gap-3 sm:grid-cols-2">
              <label className="block">
                <span className="block text-xs font-medium text-zinc-600 mb-1">Name</span>
                <input
                  id="new-person-name"
                  type="text"
                  value={draft.name}
                  onChange={(e) => setDraft({...draft, name: e.target.value})}
                  className="w-full rounded border border-zinc-300 px-2 py-1.5 text-sm"
                  autoComplete="off"
                />
              </label>

              <label className="block">
                <span className="block text-xs font-medium text-zinc-600 mb-1">Email</span>
                <input
                  id="new-person-email"
                  type="email"
                  value={draft.email}
                  onChange={(e) => setDraft({...draft, email: e.target.value})}
                  className="w-full rounded border border-zinc-300 px-2 py-1.5 text-sm"
                  autoComplete="off"
                />
              </label>

              <label className="block">
                <span className="block text-xs font-medium text-zinc-600 mb-1">First password</span>
                <input
                  id="new-person-password"
                  type="text"
                  value={draft.password}
                  onChange={(e) => setDraft({...draft, password: e.target.value})}
                  className="w-full rounded border border-zinc-300 px-2 py-1.5 text-sm font-mono"
                  autoComplete="new-password"
                />
                <span className="block text-[11px] text-zinc-500 mt-1">
                  At least 8 characters, with a letter and a number. Shown as you type so you can pass it on.
                </span>
              </label>

              <label className="block">
                <span className="block text-xs font-medium text-zinc-600 mb-1">Role</span>
                <select
                  id="new-person-role"
                  value={draft.role}
                  onChange={(e) => setDraft({...draft, role: e.target.value})}
                  className="w-full rounded border border-zinc-300 bg-white px-2 py-1.5 text-sm"
                >
                  <option value="member">Member</option>
                  <option value="admin">Admin</option>
                </select>
                <span className="block text-[11px] text-zinc-500 mt-1">
                  Only an admin can reach this page and manage people.
                </span>
              </label>
            </div>

            <div className="mt-4 flex items-center gap-2">
              <button
                type="submit"
                disabled={isCreating}
                className="rounded-md bg-zinc-900 px-3 py-2 text-sm font-medium text-white hover:bg-zinc-800 disabled:opacity-60"
              >
                {isCreating ? 'Adding…' : 'Add to my account'}
              </button>
              <span className="text-[11px] text-zinc-500">
                You will know their password until they change it. That is expected for now and is on the list to
                tighten before go-live.
              </span>
            </div>
          </form>
        )}

        <div className="rounded-lg border border-zinc-200 bg-white overflow-hidden">
          <table className="w-full text-sm" id="team-table">
            <thead className="bg-zinc-50 text-left text-xs uppercase tracking-wide text-zinc-500">
              <tr>
                <th className="px-4 py-2 font-medium">Person</th>
                <th className="px-4 py-2 font-medium">Role</th>
                <th className="px-4 py-2 font-medium">Can reach</th>
                <th className="px-4 py-2 font-medium">Status</th>
                {isAdmin && <th className="px-4 py-2 font-medium sr-only">Actions</th>}
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-100">
              {team.map((member) => {
                const isSelf = user?.id === member.id;
                const busy = savingId === member.id;
                const isEditing = editingId === member.id;
                return (
                  <tr key={member.id} data-user-id={member.id} className={member.is_active ? '' : 'bg-zinc-50/60'}>
                    <td className="px-4 py-3">
                      {isEditing ? (
                        <div className="flex flex-col gap-1.5 max-w-xs">
                          <input
                            type="text"
                            aria-label={`Name for ${member.name || member.email}`}
                            value={editDraft.name}
                            onChange={(e) => setEditDraft({...editDraft, name: e.target.value})}
                            className="rounded border border-zinc-300 px-2 py-1 text-sm"
                          />
                          <input
                            type="email"
                            aria-label={`Email for ${member.name || member.email}`}
                            value={editDraft.email}
                            onChange={(e) => setEditDraft({...editDraft, email: e.target.value})}
                            className="rounded border border-zinc-300 px-2 py-1 text-xs"
                          />
                        </div>
                      ) : (
                        <>
                          <div className="font-medium text-zinc-900 flex items-center gap-2">
                            {member.name || '—'}
                            {isSelf && (
                              <span className="rounded bg-zinc-100 px-1.5 py-0.5 text-[11px] font-normal text-zinc-500">
                                you
                              </span>
                            )}
                          </div>
                          <div className="text-xs text-zinc-500">{member.email}</div>
                        </>
                      )}
                    </td>

                    <td className="px-4 py-3">
                      {isAdmin && !isSelf ? (
                        <select
                          aria-label={`Role for ${member.name || member.email}`}
                          className="rounded border border-zinc-300 bg-white px-2 py-1 text-sm disabled:opacity-50"
                          value={member.role}
                          disabled={busy}
                          onChange={(e) => void changeRole(member, e.target.value as Role)}
                        >
                          <option value="member">Member</option>
                          <option value="admin">Admin</option>
                        </select>
                      ) : (
                        <span className="inline-flex items-center gap-1 text-zinc-700">
                          {member.role === 'admin' && <ShieldCheck className="w-3.5 h-3.5 text-zinc-400" />}
                          {member.role === 'admin' ? 'Admin' : 'Member'}
                        </span>
                      )}
                    </td>

                    {/* ── USR-2: the three modules ───────────────────────────
                        A tick is a grant. An unticked box is "not granted",
                        which is also what a missing row means — the two are
                        deliberately the same answer on screen, because to
                        somebody asking "can they get in?" they are.

                        Nobody edits their own access, in either direction
                        (E-USR-020), so an admin's own row is read-only here.
                        The lockout that prevents is specific: the only admin
                        revoking their own Intelligent Layer, after which
                        nobody can reach the maps and nobody can grant it
                        back. */}
                    <td className="px-4 py-3">
                      <div className="flex flex-col gap-1">
                        {MODULES.map((key) => (
                          <label key={key} className="inline-flex items-center gap-1.5 text-xs text-zinc-700">
                            <input
                              type="checkbox"
                              aria-label={`${MODULE_LABELS[key]} for ${member.name || member.email}`}
                              checked={member.modules[key]}
                              disabled={!isAdmin || isSelf || busy}
                              onChange={(e) => void changeModule(member, key, e.target.checked)}
                              className="h-3.5 w-3.5 rounded border-zinc-300 disabled:opacity-40"
                            />
                            {MODULE_LABELS[key]}
                          </label>
                        ))}
                      </div>
                    </td>

                    <td className="px-4 py-3">
                      <span
                        className={
                          member.is_active
                            ? 'inline-block rounded-full bg-emerald-50 px-2 py-0.5 text-xs text-emerald-700'
                            : 'inline-block rounded-full bg-zinc-200 px-2 py-0.5 text-xs text-zinc-600'
                        }
                      >
                        {member.is_active ? 'Active' : 'Switched off'}
                      </span>
                    </td>

                    {isAdmin && (
                      <td className="px-4 py-3">
                        <div className="flex items-center justify-end gap-1.5">
                          {savedId === member.id && (
                            <Check className="w-4 h-4 text-emerald-600 mr-1" aria-label="Saved" />
                          )}

                          {isEditing ? (
                            <>
                              <button
                                type="button"
                                className="rounded bg-zinc-900 px-2 py-1 text-xs text-white hover:bg-zinc-800 disabled:opacity-50"
                                disabled={busy}
                                onClick={() => void saveEdit(member)}
                              >
                                {busy ? 'Saving…' : 'Save'}
                              </button>
                              <button
                                type="button"
                                className="rounded border border-zinc-300 px-2 py-1 text-xs text-zinc-700 hover:bg-zinc-50"
                                onClick={() => setEditingId(null)}
                              >
                                Cancel
                              </button>
                            </>
                          ) : (
                            <button
                              type="button"
                              className="rounded border border-zinc-300 px-2 py-1 text-xs text-zinc-700 hover:bg-zinc-50 disabled:opacity-50"
                              disabled={busy}
                              onClick={() => startEditing(member)}
                            >
                              Edit
                            </button>
                          )}

                          {!isSelf && !isEditing && (
                            <button
                              type="button"
                              className="rounded border border-zinc-300 px-2 py-1 text-xs text-zinc-700 hover:bg-zinc-50 disabled:opacity-50"
                              disabled={busy}
                              onClick={() => void changeActive(member, !member.is_active)}
                            >
                              {member.is_active ? 'Switch off' : 'Switch on'}
                            </button>
                          )}

                          {/* The only irreversible control on the page, so it
                              asks twice and says what it will do. The server
                              refuses anyone who has work in the system
                              (E-USR-013) — which the client cannot predict,
                              so this button is offered and the refusal is
                              shown honestly. */}
                          {!isSelf && !isEditing && (
                            <>
                              {confirmRemoveId === member.id ? (
                                <>
                                  <button
                                    type="button"
                                    className="rounded bg-red-600 px-2 py-1 text-xs font-medium text-white hover:bg-red-700 disabled:opacity-50"
                                    disabled={busy}
                                    onClick={() => void removePerson(member)}
                                  >
                                    {busy ? 'Removing…' : 'Remove for good'}
                                  </button>
                                  <button
                                    type="button"
                                    className="rounded border border-zinc-300 px-2 py-1 text-xs text-zinc-700 hover:bg-zinc-50"
                                    onClick={() => setConfirmRemoveId(null)}
                                  >
                                    Keep
                                  </button>
                                </>
                              ) : (
                                <button
                                  type="button"
                                  aria-label={`Remove ${member.name || member.email}`}
                                  className="rounded border border-zinc-300 p-1 text-zinc-500 hover:bg-red-50 hover:text-red-700 disabled:opacity-50"
                                  disabled={busy}
                                  onClick={() => {
                                    setConfirmRemoveId(member.id);
                                    setError(null);
                                  }}
                                >
                                  <Trash2 className="w-3.5 h-3.5" />
                                </button>
                              )}
                            </>
                          )}
                        </div>
                      </td>
                    )}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <p className="mt-3 text-xs text-zinc-500">
          {activeAdmins === 1
            ? 'Your account has one active admin, so that admin cannot be stepped down, switched off or removed. Promote someone else first.'
            : `Your account has ${activeAdmins} active admins.`}
        </p>
        <p className="mt-1 text-xs text-zinc-500">
          Switching someone off keeps all of their work and can be undone. Removing them is permanent, and is refused
          for anyone who already owns or has performed anything.
        </p>
        <p className="mt-1 text-xs text-zinc-500">
          A new person starts with all three unticked and sees nothing until you tick something. Nobody can change their
          own access — ask another admin.
        </p>
      </div>
    </div>
  );
}
