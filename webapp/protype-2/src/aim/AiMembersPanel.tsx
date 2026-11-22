import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {AlertCircle, Bot, Check, Copy, KeyRound, Loader2, Plus} from 'lucide-react';
import {friendlyError} from '../xano';
import {createAiToken, getAiMembers, pauseAllAi, revokeAiToken, saveAiMember, switchAiMember} from './aimApi';
import {
  AI_ACTIONS,
  PURPOSE_MAX,
  TOKEN_STATE_LABELS,
  actionLabel,
  actionsSummary,
  candidateLogins,
  managerChoices,
  memberStatus,
  planNames,
  profileProblem,
  todayLine,
  tokenState,
  toMs,
  type AimPerson,
  type AiMember,
  type AiOverview,
  type AiPlan,
  type AiProfileDraft,
  type MemberStatus,
} from './aimModel';

/**
 * AIM-1 — AI members, on the Manage users page (admins only; the page decides who sees this).
 *
 * An AI member is a login that is an AI, not a person. It works through an access token, never
 * through the app, and a person is always its manager.
 *
 * Every check here is a courtesy: the server refuses again and its sentence is what is shown.
 * A refused save keeps what the admin typed. A new access token lives only in this component's
 * state while its amber panel is open — never in localStorage — and is dropped on Done.
 */

interface Props {
  /** The people already loaded by the Manage users page, so this panel does not fetch them again. */
  members: AimPerson[];
  viewerId: number | null | undefined;
  /** Tells the page which logins are AI members, so it can badge them in the people table. */
  onAiUserIds?: (ids: number[]) => void;
}

type Confirm = {kind: 'pause'} | {kind: 'switch'; userId: number} | {kind: 'revoke'; tokenId: number} | null;

interface OnceToken {
  userId: number;
  name: string;
  label: string;
  token: string;
  days: number;
}

const STATUS_STYLES: Record<MemberStatus, string> = {
  Working: 'bg-emerald-50 text-emerald-700',
  'Needs a manager': 'bg-amber-100 text-amber-800',
  'Switched off': 'bg-zinc-200 text-zinc-600',
  'Paused for everyone': 'bg-amber-100 text-amber-800',
};

function showDate(value: number | string | null | undefined, none: string): string {
  const ms = toMs(value);
  if (ms == null) return none;
  return new Date(ms).toLocaleDateString(undefined, {year: 'numeric', month: 'short', day: 'numeric'});
}

function AiBadge() {
  return (
    <span className="inline-flex items-center gap-1 rounded bg-violet-100 px-1.5 py-0.5 text-[11px] font-medium text-violet-700">
      <Bot className="w-3 h-3" />
      AI
    </span>
  );
}

const btnPlain =
  'rounded border border-zinc-300 bg-white px-2 py-1 text-xs text-zinc-700 hover:bg-zinc-50 disabled:opacity-50';
const btnDark = 'rounded bg-zinc-900 px-2 py-1 text-xs font-medium text-white hover:bg-zinc-800 disabled:opacity-50';
const btnAmber = 'rounded bg-amber-600 px-2 py-1 text-xs font-medium text-white hover:bg-amber-700 disabled:opacity-50';

/** The same form for "change its job" and "make a login an AI member". */
function ProfileForm(props: {
  idPrefix: string;
  draft: AiProfileDraft;
  onChange: (next: AiProfileDraft) => void;
  managers: AimPerson[];
  grantable: string[];
  plans: AiPlan[];
  problem: string | null;
  busy: boolean;
  saveLabel: string;
  onSave: () => void;
  onCancel: () => void;
}) {
  const {idPrefix, draft, onChange, managers, grantable, plans, problem, busy, saveLabel, onSave, onCancel} = props;

  const toggleAction = (action: string, on: boolean) =>
    onChange({
      ...draft,
      allowed_actions: on
        ? [...draft.allowed_actions.filter((a) => a !== action), action]
        : draft.allowed_actions.filter((a) => a !== action),
    });

  const togglePlan = (planId: number, on: boolean) =>
    onChange({
      ...draft,
      plan_ids: on ? [...draft.plan_ids.filter((p) => p !== planId), planId] : draft.plan_ids.filter((p) => p !== planId),
    });

  return (
    <form
      className="mt-3 rounded-md border border-zinc-200 bg-zinc-50 p-3"
      onSubmit={(e) => {
        e.preventDefault();
        onSave();
      }}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="block">
          <span className="block text-xs font-medium text-zinc-600 mb-1">Manager (a person)</span>
          <select
            id={`${idPrefix}-manager`}
            value={draft.manager_user_id}
            onChange={(e) => onChange({...draft, manager_user_id: Number(e.target.value)})}
            className="w-full rounded border border-zinc-300 bg-white px-2 py-1.5 text-sm"
          >
            <option value={0}>Pick a person…</option>
            {managers.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name || p.email}
              </option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="block text-xs font-medium text-zinc-600 mb-1">What it is for</span>
          <input
            id={`${idPrefix}-purpose`}
            type="text"
            value={draft.purpose}
            onChange={(e) => onChange({...draft, purpose: e.target.value})}
            className="w-full rounded border border-zinc-300 px-2 py-1.5 text-sm"
            autoComplete="off"
          />
          <span className="block text-[11px] text-zinc-500 mt-1">
            One short sentence, up to {PURPOSE_MAX} characters. {draft.purpose.trim().length}/{PURPOSE_MAX}
          </span>
        </label>
      </div>

      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <fieldset>
          <legend className="text-xs font-medium text-zinc-600 mb-1">What it may do</legend>
          <div className="flex flex-col gap-1">
            {grantable.map((action) => (
              <label key={action} className="inline-flex items-center gap-1.5 text-xs text-zinc-700">
                <input
                  type="checkbox"
                  checked={draft.allowed_actions.includes(action)}
                  onChange={(e) => toggleAction(action, e.target.checked)}
                  className="h-3.5 w-3.5 rounded border-zinc-300"
                />
                {actionLabel(action)}
              </label>
            ))}
          </div>
        </fieldset>

        <fieldset>
          <legend className="text-xs font-medium text-zinc-600 mb-1">Plans it may work in</legend>
          {plans.length === 0 ? (
            <p className="text-xs text-zinc-500">Your account has no plans yet.</p>
          ) : (
            <div className="flex max-h-40 flex-col gap-1 overflow-y-auto">
              {plans.map((plan) => (
                <label key={plan.id} className="inline-flex items-center gap-1.5 text-xs text-zinc-700">
                  <input
                    type="checkbox"
                    checked={draft.plan_ids.includes(plan.id)}
                    onChange={(e) => togglePlan(plan.id, e.target.checked)}
                    className="h-3.5 w-3.5 rounded border-zinc-300"
                  />
                  {plan.name || `Plan ${plan.id}`}
                </label>
              ))}
            </div>
          )}
        </fieldset>
      </div>

      {problem && (
        <p role="alert" className="mt-3 text-xs text-amber-800">
          {problem}
        </p>
      )}

      <div className="mt-3 flex items-center gap-2">
        <button type="submit" disabled={busy} className={btnDark}>
          {busy ? 'Saving…' : saveLabel}
        </button>
        <button type="button" onClick={onCancel} className={btnPlain}>
          Cancel
        </button>
      </div>
    </form>
  );
}

export default function AiMembersPanel({members, viewerId, onAiUserIds}: Props) {
  const [data, setData] = useState<AiOverview | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<Confirm>(null);

  // One form open at a time: an AI member's user id, 'new', or nothing.
  const [formFor, setFormFor] = useState<number | 'new' | null>(null);
  const [draft, setDraft] = useState<AiProfileDraft | null>(null);
  const [formProblem, setFormProblem] = useState<string | null>(null);

  const [tokenFormFor, setTokenFormFor] = useState<number | null>(null);
  const [tokenLabel, setTokenLabel] = useState('');
  // The new token, shown once. Held only here and dropped on Done.
  const [once, setOnce] = useState<OnceToken | null>(null);
  const [copied, setCopied] = useState(false);

  const load = useCallback(async () => {
    try {
      const next = await getAiMembers();
      setData(next);
      setLoadError(null);
      onAiUserIds?.((next.members ?? []).map((m) => m.user_id));
    } catch (err) {
      setLoadError(friendlyError(err, 'Unable to load AI members right now. Please try again.'));
    } finally {
      setIsLoading(false);
    }
  }, [onAiUserIds]);

  useEffect(() => {
    void load();
  }, [load]);

  const aiMembers: AiMember[] = data?.members ?? [];
  const plans: AiPlan[] = data?.plans ?? [];
  const grantable: string[] = data?.grantable && data.grantable.length > 0 ? data.grantable : [...AI_ACTIONS];
  const allPaused = data?.all_paused === true;
  const aiIds = useMemo(() => aiMembers.map((m) => m.user_id), [aiMembers]);
  const candidates = useMemo(() => candidateLogins(members, aiIds, viewerId), [members, aiIds, viewerId]);
  const nowMs = Date.now();

  /** One shared path for every change: run it, reload this panel's data, show the server's sentence on a refusal. */
  const run = async (key: string, action: () => Promise<unknown>, fallback: string, done?: string): Promise<boolean> => {
    setBusy(key);
    setError(null);
    setNotice(null);
    try {
      await action();
      await load();
      if (done) setNotice(done);
      return true;
    } catch (err) {
      setError(friendlyError(err, fallback));
      return false;
    } finally {
      setBusy(null);
    }
  };

  const closeForm = () => {
    setFormFor(null);
    setDraft(null);
    setFormProblem(null);
  };

  const startEdit = (m: AiMember) => {
    setFormFor(m.user_id);
    setDraft({
      user_id: m.user_id,
      manager_user_id: m.manager_user_id || 0,
      purpose: m.purpose ?? '',
      allowed_actions: [...(m.allowed_actions ?? [])],
      plan_ids: [...(m.plan_ids ?? [])],
    });
    setFormProblem(null);
    setError(null);
  };

  const startNew = () => {
    setFormFor('new');
    setDraft({user_id: 0, manager_user_id: 0, purpose: '', allowed_actions: [], plan_ids: []});
    setFormProblem(null);
    setError(null);
  };

  const saveDraft = async (existing: AiMember | null) => {
    if (!draft) return;
    if (!(draft.user_id > 0)) {
      setFormProblem('Pick the login to make an AI member.');
      return;
    }
    const problem = profileProblem(draft);
    if (problem) {
      setFormProblem(problem);
      return;
    }
    setFormProblem(null);
    const ok = await run(
      `save-${draft.user_id}`,
      () =>
        saveAiMember({
          user_id: draft.user_id,
          manager_user_id: draft.manager_user_id,
          purpose: draft.purpose.trim(),
          allowed_actions: draft.allowed_actions,
          plan_ids: draft.plan_ids,
          // Sent back unchanged when editing: leaving them out resets the limits to the standard ones.
          writes_per_hour: existing?.writes_per_hour,
          writes_per_day: existing?.writes_per_day,
        }),
      'That could not be saved. Please try again.',
      existing ? 'Saved.' : 'That login is now an AI member. Create an access token so it can start work.',
    );
    // Closed on success ONLY: a refused save keeps what the admin typed.
    if (ok) closeForm();
  };

  const doSwitch = async (m: AiMember) => {
    const turnOn = m.is_paused === true;
    const ok = await run(
      `switch-${m.user_id}`,
      () => switchAiMember(m.user_id, turnOn),
      'That change could not be saved. Please try again.',
      turnOn
        ? `${m.name || 'The AI member'} is switched on. Create a new access token so it can work.`
        : `${m.name || 'The AI member'} is switched off and its access tokens are cancelled.`,
    );
    if (ok) setConfirm(null);
  };

  const doPauseAll = async () => {
    const next = !allPaused;
    const ok = await run(
      'pause',
      () => pauseAllAi(next),
      'That change could not be saved. Please try again.',
      next ? 'AI is paused for this account.' : 'AI is back on for this account.',
    );
    if (ok) setConfirm(null);
  };

  const doRevoke = async (tokenId: number) => {
    const ok = await run(
      `revoke-${tokenId}`,
      () => revokeAiToken(tokenId),
      'The token could not be cancelled. Please try again.',
      'That access token is cancelled and no longer works.',
    );
    if (ok) setConfirm(null);
  };

  const doCreateToken = async (m: AiMember) => {
    setBusy(`token-${m.user_id}`);
    setError(null);
    setNotice(null);
    setCopied(false);
    try {
      const made = await createAiToken(m.user_id, tokenLabel.trim());
      setOnce({
        userId: m.user_id,
        name: m.name || 'the AI member',
        label: made.label || tokenLabel.trim(),
        token: made.token,
        days: made.expires_in_days,
      });
      setTokenFormFor(null);
      setTokenLabel('');
      await load();
    } catch (err) {
      // The typed label stays: nothing above cleared it.
      setError(friendlyError(err, 'The access token could not be made. Please try again.'));
    } finally {
      setBusy(null);
    }
  };

  const copyOnce = async () => {
    if (!once) return;
    try {
      await navigator.clipboard.writeText(once.token);
      setCopied(true);
    } catch {
      setError('Copy did not work. Select the token and copy it by hand.');
    }
  };

  return (
    <section className="mt-8" aria-labelledby="ai-members-title" id="ai-members">
      <header className="mb-3 flex items-start justify-between gap-4">
        <div>
          <h2 id="ai-members-title" className="text-base font-semibold text-zinc-900 flex items-center gap-2">
            <Bot className="w-4 h-4 text-zinc-500" />
            AI members
          </h2>
          <p className="text-sm text-zinc-500 mt-1">
            An AI member works through its access token, not the app. A person must be its manager.
          </p>
        </div>

        {data && (
          <div className="shrink-0 flex items-center gap-1.5">
            {confirm?.kind === 'pause' ? (
              <>
                <span className="text-xs text-zinc-600">
                  {allPaused ? 'Let AI members work again?' : 'Stop every AI member now?'}
                </span>
                <button
                  type="button"
                  data-testid="ai-pause-all-confirm"
                  className={btnAmber}
                  disabled={busy === 'pause'}
                  onClick={() => void doPauseAll()}
                >
                  {busy === 'pause' ? 'Saving…' : allPaused ? 'Yes, turn AI back on' : 'Yes, pause all AI'}
                </button>
                <button type="button" className={btnPlain} onClick={() => setConfirm(null)}>
                  Keep
                </button>
              </>
            ) : (
              <label className="inline-flex items-center gap-2 text-sm text-zinc-700 cursor-pointer">
                <span>Pause all AI</span>
                <button
                  type="button"
                  role="switch"
                  aria-checked={allPaused}
                  aria-label="Pause all AI"
                  data-testid="ai-pause-all"
                  disabled={busy !== null}
                  onClick={() => {
                    setConfirm({kind: 'pause'});
                    setError(null);
                  }}
                  className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors disabled:opacity-50 ${
                    allPaused ? 'bg-amber-500' : 'bg-zinc-300'
                  }`}
                >
                  <span
                    className={`inline-block h-4 w-4 rounded-full bg-white shadow transition-transform ${
                      allPaused ? 'translate-x-4' : 'translate-x-0.5'
                    }`}
                  />
                </button>
              </label>
            )}
          </div>
        )}
      </header>

      {allPaused && (
        <div
          role="status"
          data-testid="ai-paused-banner"
          className="mb-4 flex items-start gap-2 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-950"
        >
          <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
          <span>AI is paused for this account. No AI member can work until you turn it back on.</span>
        </div>
      )}

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

      {/* The new access token, shown once. */}
      {once && (
        <div
          role="status"
          aria-label="New access token"
          data-testid="ai-token-once"
          className="mb-4 rounded-lg border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950"
        >
          <p className="font-medium">
            Access token for {once.name}
            {once.label ? ` (${once.label})` : ''}
          </p>
          <p className="mt-1 text-xs">
            Copy it now. It will not be shown again.
            {once.days > 0 ? ` It works for ${once.days} days.` : ''} Anyone who has it can act as this AI member, so
            give it only to the AI tool that needs it.
          </p>
          <div className="mt-3 flex flex-wrap items-center gap-2">
            <input
              readOnly
              aria-label="Access token"
              value={once.token}
              onFocus={(e) => e.currentTarget.select()}
              className="min-w-0 flex-1 rounded border border-amber-300 bg-white px-2 py-1 font-mono text-xs"
            />
            <button
              type="button"
              onClick={() => void copyOnce()}
              className="inline-flex items-center gap-1 rounded bg-zinc-900 px-2.5 py-1.5 text-xs font-medium text-white hover:bg-zinc-800"
            >
              <Copy className="w-3.5 h-3.5" />
              {copied ? 'Copied' : 'Copy'}
            </button>
            <button
              type="button"
              onClick={() => {
                setOnce(null);
                setCopied(false);
              }}
              className="rounded border border-zinc-300 bg-white px-2.5 py-1.5 text-xs text-zinc-700 hover:bg-zinc-50"
            >
              Done
            </button>
          </div>
        </div>
      )}

      {isLoading ? (
        <div className="rounded-lg border border-zinc-200 bg-white p-6 flex justify-center">
          <Loader2 className="w-5 h-5 animate-spin text-zinc-400" />
        </div>
      ) : loadError && !data ? (
        <div
          role="alert"
          className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-3 text-sm text-amber-900 flex flex-wrap items-center gap-3"
        >
          <span>{loadError}</span>
          <button
            type="button"
            className={btnPlain}
            onClick={() => {
              setIsLoading(true);
              void load();
            }}
          >
            Try again
          </button>
        </div>
      ) : (
        <>
          {aiMembers.length === 0 ? (
            <div className="rounded-lg border border-zinc-200 bg-white px-4 py-6 text-sm text-zinc-500">
              No AI members yet.
            </div>
          ) : (
            <ul className="space-y-3" id="ai-member-list">
              {aiMembers.map((m) => {
                const status = memberStatus(m, allPaused);
                const tokens = m.tokens ?? [];
                const names = planNames(m.plan_ids, plans);
                const isEditing = formFor === m.user_id && draft != null;
                const label = m.name || 'this AI member';
                return (
                  <li
                    key={m.user_id}
                    data-testid={`ai-member-${m.user_id}`}
                    className="rounded-lg border border-zinc-200 bg-white p-4"
                  >
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div className="min-w-0">
                        <div className="font-medium text-zinc-900 flex flex-wrap items-center gap-2">
                          {m.name || '—'}
                          <AiBadge />
                          <span className={`inline-block rounded-full px-2 py-0.5 text-xs font-normal ${STATUS_STYLES[status]}`}>
                            {status}
                          </span>
                        </div>
                        {m.is_paused && m.paused_reason ? (
                          <p className="mt-1 text-xs text-zinc-500">Why it is off: {m.paused_reason}</p>
                        ) : null}
                      </div>

                      <div className="flex flex-wrap items-center justify-end gap-1.5">
                        {!isEditing && (
                          <button
                            type="button"
                            className={btnPlain}
                            disabled={busy !== null}
                            onClick={() => startEdit(m)}
                            aria-label={`Edit ${label}`}
                          >
                            Edit
                          </button>
                        )}
                        {confirm?.kind === 'switch' && confirm.userId === m.user_id ? (
                          <>
                            <span className="text-xs text-zinc-600">
                              {m.is_paused
                                ? 'Switch it back on? It will need a new access token.'
                                : 'Switching off also cancels its access tokens.'}
                            </span>
                            <button
                              type="button"
                              className={btnAmber}
                              disabled={busy === `switch-${m.user_id}`}
                              onClick={() => void doSwitch(m)}
                            >
                              {busy === `switch-${m.user_id}` ? 'Saving…' : m.is_paused ? 'Yes, switch on' : 'Yes, switch off'}
                            </button>
                            <button type="button" className={btnPlain} onClick={() => setConfirm(null)}>
                              Keep
                            </button>
                          </>
                        ) : (
                          <button
                            type="button"
                            className={btnPlain}
                            disabled={busy !== null}
                            aria-label={`${m.is_paused ? 'Switch on' : 'Switch off'} ${label}`}
                            onClick={() => {
                              setConfirm({kind: 'switch', userId: m.user_id});
                              setError(null);
                            }}
                          >
                            {m.is_paused ? 'Switch on' : 'Switch off'}
                          </button>
                        )}
                      </div>
                    </div>

                    {isEditing && draft ? (
                      <ProfileForm
                        idPrefix={`ai-edit-${m.user_id}`}
                        draft={draft}
                        onChange={setDraft}
                        managers={managerChoices(members, aiIds, m.user_id)}
                        grantable={grantable}
                        plans={plans}
                        problem={formProblem}
                        busy={busy === `save-${m.user_id}`}
                        saveLabel="Save"
                        onSave={() => void saveDraft(m)}
                        onCancel={closeForm}
                      />
                    ) : (
                      <dl className="mt-3 grid gap-x-6 gap-y-1.5 text-xs sm:grid-cols-2">
                        <div>
                          <dt className="inline text-zinc-500">Manager: </dt>
                          <dd className="inline text-zinc-800">
                            {m.needs_manager ? 'None. Pick one with Edit.' : m.manager_name || '—'}
                          </dd>
                        </div>
                        <div>
                          <dt className="inline text-zinc-500">What it is for: </dt>
                          <dd className="inline text-zinc-800">{m.purpose || '—'}</dd>
                        </div>
                        <div>
                          <dt className="inline text-zinc-500">May: </dt>
                          <dd className="inline text-zinc-800">{actionsSummary(m.allowed_actions)}</dd>
                        </div>
                        <div>
                          <dt className="inline text-zinc-500">Plans: </dt>
                          <dd className="inline text-zinc-800">{names.length > 0 ? names.join(', ') : 'None'}</dd>
                        </div>
                        <div className="sm:col-span-2 text-zinc-500">{todayLine(m)}</div>
                      </dl>
                    )}

                    {/* Access tokens */}
                    <div className="mt-4 border-t border-zinc-100 pt-3">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <h3 className="text-xs font-semibold uppercase tracking-wide text-zinc-500">Access tokens</h3>
                        {tokenFormFor !== m.user_id && (
                          <button
                            type="button"
                            className={`${btnPlain} inline-flex items-center gap-1`}
                            disabled={busy !== null}
                            onClick={() => {
                              setTokenFormFor(m.user_id);
                              setTokenLabel('');
                              setError(null);
                            }}
                          >
                            <KeyRound className="w-3.5 h-3.5" />
                            Create access token
                          </button>
                        )}
                      </div>

                      {tokenFormFor === m.user_id && (
                        <form
                          className="mt-2 flex flex-wrap items-end gap-2"
                          onSubmit={(e) => {
                            e.preventDefault();
                            void doCreateToken(m);
                          }}
                        >
                          <label className="block">
                            <span className="block text-xs font-medium text-zinc-600 mb-1">Label (optional)</span>
                            <input
                              type="text"
                              value={tokenLabel}
                              placeholder="Where it will be used"
                              onChange={(e) => setTokenLabel(e.target.value)}
                              className="rounded border border-zinc-300 px-2 py-1 text-sm"
                              autoComplete="off"
                            />
                          </label>
                          <button type="submit" className={btnDark} disabled={busy === `token-${m.user_id}`}>
                            {busy === `token-${m.user_id}` ? 'Making…' : 'Create access token'}
                          </button>
                          <button type="button" className={btnPlain} onClick={() => setTokenFormFor(null)}>
                            Cancel
                          </button>
                        </form>
                      )}

                      {tokens.length === 0 ? (
                        <p className="mt-2 text-xs text-zinc-500">No access tokens yet. It cannot work without one.</p>
                      ) : (
                        <table className="mt-2 w-full text-xs">
                          <thead className="text-left text-zinc-500">
                            <tr>
                              <th className="py-1 pr-3 font-medium">Label</th>
                              <th className="py-1 pr-3 font-medium">Made</th>
                              <th className="py-1 pr-3 font-medium">Last used</th>
                              <th className="py-1 pr-3 font-medium">Expires</th>
                              <th className="py-1 pr-3 font-medium">State</th>
                              <th className="py-1 font-medium sr-only">Actions</th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-zinc-100">
                            {tokens.map((t) => {
                              const state = tokenState(t, nowMs);
                              const confirming = confirm?.kind === 'revoke' && confirm.tokenId === t.token_id;
                              return (
                                <tr key={t.token_id} data-testid={`ai-token-${t.token_id}`}>
                                  <td className="py-1.5 pr-3 text-zinc-800">{t.label || 'No label'}</td>
                                  <td className="py-1.5 pr-3 text-zinc-600">{showDate(t.created_at, '—')}</td>
                                  <td className="py-1.5 pr-3 text-zinc-600">{showDate(t.last_used_at, 'Never')}</td>
                                  <td className="py-1.5 pr-3 text-zinc-600">{showDate(t.expires_at, '—')}</td>
                                  <td className="py-1.5 pr-3">
                                    <span
                                      className={`inline-block rounded-full px-2 py-0.5 ${
                                        state === 'live' ? 'bg-emerald-50 text-emerald-700' : 'bg-zinc-200 text-zinc-600'
                                      }`}
                                    >
                                      {TOKEN_STATE_LABELS[state]}
                                    </span>
                                  </td>
                                  <td className="py-1.5 text-right">
                                    {state !== 'live' ? null : confirming ? (
                                      <span className="inline-flex items-center gap-1.5">
                                        <button
                                          type="button"
                                          className="rounded bg-red-600 px-2 py-1 text-xs font-medium text-white hover:bg-red-700 disabled:opacity-50"
                                          disabled={busy === `revoke-${t.token_id}`}
                                          onClick={() => void doRevoke(t.token_id)}
                                        >
                                          {busy === `revoke-${t.token_id}` ? 'Cancelling…' : 'Yes, revoke'}
                                        </button>
                                        <button type="button" className={btnPlain} onClick={() => setConfirm(null)}>
                                          Keep
                                        </button>
                                      </span>
                                    ) : (
                                      <button
                                        type="button"
                                        className={btnPlain}
                                        disabled={busy !== null}
                                        aria-label={`Revoke token ${t.label || t.token_id}`}
                                        onClick={() => {
                                          setConfirm({kind: 'revoke', tokenId: t.token_id});
                                          setError(null);
                                        }}
                                      >
                                        Revoke
                                      </button>
                                    )}
                                  </td>
                                </tr>
                              );
                            })}
                          </tbody>
                        </table>
                      )}
                    </div>
                  </li>
                );
              })}
            </ul>
          )}

          {/* Make a login an AI member */}
          <div className="mt-4 rounded-lg border border-zinc-200 bg-white p-4" id="ai-member-new">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 className="text-sm font-semibold text-zinc-900">Make a login an AI member</h3>
                <p className="text-xs text-zinc-500 mt-0.5">
                  An AI member works through its access token, not the app. A person must be its manager.
                </p>
              </div>
              {formFor !== 'new' && (
                <button
                  type="button"
                  data-testid="ai-member-new-start"
                  className="shrink-0 inline-flex items-center gap-1.5 rounded-md bg-zinc-900 px-3 py-2 text-sm font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
                  disabled={busy !== null || candidates.length === 0}
                  onClick={startNew}
                >
                  <Plus className="w-4 h-4" />
                  Pick a login
                </button>
              )}
            </div>

            {candidates.length === 0 && formFor !== 'new' && (
              <p className="mt-2 text-xs text-zinc-500">
                No login is free for this. Add someone as a Member first (not an admin), then come back here.
              </p>
            )}

            {formFor === 'new' && draft && (
              <>
                <label className="mt-3 block max-w-sm">
                  <span className="block text-xs font-medium text-zinc-600 mb-1">Login</span>
                  <select
                    id="ai-new-login"
                    value={draft.user_id}
                    onChange={(e) => setDraft({...draft, user_id: Number(e.target.value)})}
                    className="w-full rounded border border-zinc-300 bg-white px-2 py-1.5 text-sm"
                  >
                    <option value={0}>Pick a login…</option>
                    {candidates.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name ? `${p.name} (${p.email})` : p.email}
                      </option>
                    ))}
                  </select>
                </label>
                <ProfileForm
                  idPrefix="ai-new"
                  draft={draft}
                  onChange={setDraft}
                  managers={managerChoices(members, aiIds, draft.user_id)}
                  grantable={grantable}
                  plans={plans}
                  problem={formProblem}
                  busy={busy === `save-${draft.user_id}`}
                  saveLabel="Make it an AI member"
                  onSave={() => void saveDraft(null)}
                  onCancel={closeForm}
                />
              </>
            )}
          </div>
        </>
      )}
    </section>
  );
}
