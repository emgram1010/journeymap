import React, {useCallback, useEffect, useRef, useState} from 'react';
import {Link, useLocation} from 'react-router-dom';
import {Loader2, Plus, X} from 'lucide-react';
import {
  createCopilotHome,
  createDraftJourneyMap,
  getCopilotConversationMessages,
  getCopilotHome,
  getCopilotMemory,
  getCopilotRuns,
  getCopilotSkillMeta,
  getCopilotSkills,
  saveCopilotLibrarySettings,
  setCopilotSkillLock,
  getCopilotSkillVersions,
  switchCopilotSkill,
  undoCopilotSkill,
  type XanoCopilotRuns,
  type XanoCopilotSkill,
  type XanoCopilotSkillMeta,
  type XanoCopilotSkills,
  type XanoCopilotSkillVersion,
  removeCopilotNote,
  saveCopilotNote,
  setCopilotGoalStatus,
  type XanoCopilotMemory,
  listCopilotConversations,
  listJourneyArchitectures,
  sendCopilotChat,
  XanoHttpError,
  type XanoCopilotHome,
  type XanoJourneyArchitecture,
} from '../xano';
import {
  messageText,
  pickConversation,
  readLastBusiness,
  screenContextSummary,
  writeLastBusiness,
} from './copilotChatModel';
import {NOTE_MAX, goalStatusLabel, noteProblem} from './copilotMemoryModel';
import {runCountsLine, runStatusLabel, runTone, runWhen, runsHeadline} from './copilotRunModel';
import {
  WORK_KINDS,
  changedFields,
  filterSkills,
  isOffFor,
  itemCounter,
  kindLabel,
  lastUsedLabel,
  limitsProblem,
  lockLabel,
  scopeLabel,
  skillInfo,
  splitByStatus,
  statusLabel,
  undoTarget,
  versionLine,
  workKindLabel,
} from './skillsModel';

/**
 * COP-3 — the copilot's chat panel. Opens beside the current page; one business at a time.
 * The server decides and refuses again; its own sentence is shown and the typed text is kept.
 */

interface Props {
  open: boolean;
  onClose: () => void;
  userId: number;
  isAdmin: boolean;
}

interface ChatLine {
  key: string;
  role: 'user' | 'assistant';
  text: string;
}

const STARTER_MAPS = ['How I research', 'How I build maps', 'How I learn', 'How I ask for approval'];

const store = (): Storage | undefined => {
  try {
    return typeof localStorage === 'undefined' ? undefined : localStorage;
  } catch {
    return undefined;
  }
};

const serverText = (e: unknown, fallback: string): string => {
  if (e instanceof XanoHttpError) return e.serverMessage || fallback;
  if (e instanceof DOMException && (e.name === 'TimeoutError' || e.name === 'AbortError')) {
    return 'The copilot took too long to answer. Your message is still here; try again.';
  }
  return fallback;
};

function MemorySection({businessId, isAdmin}: {businessId: number; isAdmin: boolean}) {
  const [mem, setMem] = useState<XanoCopilotMemory | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [newNote, setNewNote] = useState('');
  const [editId, setEditId] = useState(0);
  const [editText, setEditText] = useState('');
  const [removeId, setRemoveId] = useState(0);
  const seq = useRef(0);

  const load = useCallback(async () => {
    const my = ++seq.current;
    try {
      const m = await getCopilotMemory(businessId);
      if (my === seq.current) {
        setMem(m);
        setErr(null);
      }
    } catch (e) {
      if (my === seq.current) setErr(serverText(e, 'Unable to load what the copilot knows.'));
    }
  }, [businessId]);

  useEffect(() => {
    setMem(null);
    setEditId(0);
    setRemoveId(0);
    void load();
  }, [load]);

  const run = async (fn: () => Promise<unknown>, after?: () => void) => {
    setBusy(true);
    setErr(null);
    try {
      await fn();
      after?.();
      await load();
    } catch (e) {
      setErr(serverText(e, 'That did not save. Your text is still here.'));
    } finally {
      setBusy(false);
    }
  };

  const addNote = () => {
    const p = noteProblem(newNote);
    if (p) return setErr(p);
    void run(() => saveCopilotNote({journey_architecture_id: businessId, note_id: 0, note: newNote.trim()}), () => setNewNote(''));
  };
  const saveEdit = () => {
    const p = noteProblem(editText);
    if (p) return setErr(p);
    void run(() => saveCopilotNote({journey_architecture_id: businessId, note_id: editId, note: editText.trim()}), () => setEditId(0));
  };

  const labelled = (mem?.map_profiles ?? []).filter((p) => p.kind === 'insight' || p.kind === 'runnable').length;
  const btn = 'rounded border border-zinc-300 px-1.5 py-0.5 text-xs hover:bg-zinc-50 disabled:opacity-50';

  return (
    <div className="px-4 py-2 border-b border-zinc-100 text-sm space-y-2 max-h-64 overflow-y-auto">
      {err && <p role="alert" className="text-red-700">{err}</p>}
      {!mem && !err && <p className="text-zinc-500">Loading…</p>}
      {mem && (
        <>
          <h3 className="font-medium text-zinc-800">Goals</h3>
          {mem.goals.length === 0 && <p className="text-zinc-500">No goals yet.</p>}
          {mem.goals.map((g) => (
            <div key={g.id} className="space-y-1">
              <p className="text-zinc-900">
                {g.goal_text}
                {g.target ? ` — ${g.target}` : ''}
                {g.target_date ? ` by ${g.target_date}` : ''}
              </p>
              <p className="text-xs text-zinc-500">{goalStatusLabel(g.status)}</p>
              {isAdmin && (
                <div className="flex gap-1">
                  {g.status === 'proposed' && (
                    <button type="button" className={btn} disabled={busy} onClick={() => void run(() => setCopilotGoalStatus(g.id, 'confirmed'))}>Confirm</button>
                  )}
                  {g.status !== 'done' && (
                    <button type="button" className={btn} disabled={busy} onClick={() => void run(() => setCopilotGoalStatus(g.id, 'done'))}>Done</button>
                  )}
                  {g.status !== 'dropped' && (
                    <button type="button" className={btn} disabled={busy} onClick={() => void run(() => setCopilotGoalStatus(g.id, 'dropped'))}>Drop</button>
                  )}
                </div>
              )}
            </div>
          ))}

          <h3 className="font-medium text-zinc-800 pt-1">Notes</h3>
          {mem.notes.length === 0 && <p className="text-zinc-500">No notes yet.</p>}
          {mem.notes.map((n) => (
            <div key={n.id} className="space-y-1">
              {editId === n.id ? (
                <div className="flex gap-1">
                  <input
                    value={editText}
                    onChange={(e) => setEditText(e.target.value)}
                    aria-label="Edit note"
                    className="flex-1 min-w-0 rounded border border-zinc-300 px-1.5 py-0.5"
                  />
                  <button type="button" className={btn} disabled={busy} onClick={saveEdit}>Save</button>
                  <button type="button" className={btn} onClick={() => setEditId(0)}>Cancel</button>
                </div>
              ) : (
                <p className="text-zinc-900 break-words">{n.note}</p>
              )}
              {isAdmin && editId !== n.id && removeId !== n.id && (
                <div className="flex gap-1">
                  <button type="button" className={btn} onClick={() => {setEditId(n.id); setEditText(n.note); setRemoveId(0);}}>Edit</button>
                  <button type="button" className={btn} onClick={() => setRemoveId(n.id)}>Remove</button>
                </div>
              )}
              {isAdmin && removeId === n.id && (
                <div className="flex items-center gap-1 text-xs">
                  <span>Remove this note?</span>
                  <button type="button" className={btn} disabled={busy} onClick={() => void run(() => removeCopilotNote(n.id), () => setRemoveId(0))}>Yes, remove</button>
                  <button type="button" className={btn} onClick={() => setRemoveId(0)}>Keep</button>
                </div>
              )}
            </div>
          ))}
          {isAdmin && (
            <div className="flex gap-1">
              <input
                value={newNote}
                onChange={(e) => setNewNote(e.target.value)}
                maxLength={NOTE_MAX + 50}
                aria-label="Add a note"
                placeholder="Add a note for the copilot"
                className="flex-1 min-w-0 rounded border border-zinc-300 px-1.5 py-0.5"
              />
              <button type="button" className={btn} disabled={busy || newNote.trim() === ''} onClick={addNote}>Add</button>
            </div>
          )}
          <p className="text-xs text-zinc-500">
            {labelled === 0 ? 'No labelled maps yet.' : `${labelled} labelled ${labelled === 1 ? 'map' : 'maps'}.`}
          </p>
        </>
      )}
    </div>
  );
}

/**
 * COP-9 stories 01/04 — "How I work": the copilot's own skills, exceptions, lessons and links.
 * Each item shows its history (newest first) with Undo on every change; an admin can switch an
 * item off for the business being looked at. The server decides and refuses again; its own
 * sentence is shown.
 * COP-11 story 05 — each item also shows its lock (an admin can lock or unlock), its kind of work
 * and when it was last used; the header counts "23 of 50 items"; the list filters by kind of work
 * and by "not used"; an admin can change the three limits. The side table has its own read
 * (getCopilotSkillMeta); if that read fails the list still shows, just without these extras.
 */
function SkillsSection({businessId, businessName, isAdmin}: {businessId: number; businessName: (id: number) => string | undefined; isAdmin: boolean}) {
  const [data, setData] = useState<XanoCopilotSkills | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [openId, setOpenId] = useState(0);
  const [history, setHistory] = useState<XanoCopilotSkillVersion[]>([]);
  const [showRetired, setShowRetired] = useState(false);
  const [meta, setMeta] = useState<XanoCopilotSkillMeta | null>(null);
  const [kindFilter, setKindFilter] = useState('all');
  const [staleOnly, setStaleOnly] = useState(false);
  const [showLimits, setShowLimits] = useState(false);
  const [limits, setLimits] = useState({items: '', words: '', days: ''});
  const seq = useRef(0);

  const load = useCallback(async () => {
    const my = ++seq.current;
    try {
      const d = await getCopilotSkills();
      if (my === seq.current) {
        setData(d);
        setErr(null);
      }
    } catch (e) {
      if (my === seq.current) setErr(serverText(e, 'Unable to load how the copilot works.'));
      return;
    }
    try {
      const m = await getCopilotSkillMeta();
      if (my === seq.current) setMeta(m);
    } catch (e) {
      if (my === seq.current) setErr(serverText(e, 'Unable to load locks and limits. The list below is still right.'));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const openHistory = async (id: number) => {
    if (openId === id) return setOpenId(0);
    setOpenId(id);
    setHistory([]);
    try {
      const h = await getCopilotSkillVersions(id);
      setHistory(h.versions ?? []);
    } catch (e) {
      setErr(serverText(e, 'Unable to load the history.'));
    }
  };

  const act = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setErr(null);
    try {
      await fn();
      await load();
      if (openId) {
        const h = await getCopilotSkillVersions(openId);
        setHistory(h.versions ?? []);
      }
    } catch (e) {
      setErr(serverText(e, 'That did not save. Nothing was changed.'));
    } finally {
      setBusy(false);
    }
  };

  const openLimits = () => {
    if (!showLimits && meta) setLimits({items: String(meta.max_active_items), words: String(meta.max_load_words), days: String(meta.stale_after_days)});
    setShowLimits((v) => !v);
  };

  const saveLimits = async () => {
    const next = {max_active_items: Number(limits.items), max_load_words: Number(limits.words), stale_after_days: Number(limits.days)};
    const problem = limitsProblem(next);
    // Refused on the screen first; the typing stays. The server checks again.
    if (problem) return setErr(problem);
    await act(() => saveCopilotLibrarySettings(next));
  };

  const btn = 'rounded border border-zinc-300 px-1.5 py-0.5 text-xs hover:bg-zinc-50 disabled:opacity-50';
  const split = splitByStatus(data?.items ?? []);
  const live = filterSkills(split.live, meta, {kind: kindFilter, staleOnly});
  const retired = split.retired;
  const now = Date.now();

  const row = (s: XanoCopilotSkill) => {
    const off = isOffFor(data?.off ?? [], s.id, businessId);
    const info = skillInfo(meta, s.id);
    return (
      <li key={s.id} className="rounded border border-zinc-200 px-2 py-1 space-y-1" data-testid={`skill-${s.id}`}>
        <div className="flex flex-wrap items-center gap-2">
          <span className="rounded-full bg-zinc-100 text-zinc-700 text-xs px-2 py-0.5">{kindLabel(s.kind)} #{s.id}</span>
          <span className={`rounded-full text-xs px-2 py-0.5 ${s.status === 'trial' ? 'bg-amber-100 text-amber-800' : s.status === 'retired' ? 'bg-zinc-100 text-zinc-500' : 'bg-emerald-100 text-emerald-800'}`}>
            {statusLabel(s.status)}
          </span>
          {off && <span className="rounded-full bg-red-100 text-red-800 text-xs px-2 py-0.5">Off for this business</span>}
          {meta && (
            <>
              <span className={`rounded-full text-xs px-2 py-0.5 ${info.locked ? 'bg-indigo-100 text-indigo-800' : 'bg-zinc-100 text-zinc-600'}`}>{lockLabel(info.locked)}</span>
              <span className="rounded-full bg-zinc-100 text-zinc-700 text-xs px-2 py-0.5">{workKindLabel(info.workKind)}</span>
              {info.stale && s.status !== 'retired' && (
                <span className="rounded-full bg-amber-100 text-amber-800 text-xs px-2 py-0.5">Not used in {meta.stale_after_days} days</span>
              )}
            </>
          )}
        </div>
        <p className="font-medium text-zinc-900 break-words">{s.title}</p>
        {s.kind === 'exception' && <p className="text-zinc-700 break-words">When: {s.condition_text}</p>}
        <p className="text-zinc-700 whitespace-pre-wrap break-words">{s.body}</p>
        <p className="text-xs text-zinc-500">
          {scopeLabel(s, businessName)} · v{s.version_no}
          {meta ? ` · ${lastUsedLabel(info.lastUsedAt, now)}` : ''}
        </p>
        <div className="flex flex-wrap gap-1">
          <button type="button" className={btn} aria-expanded={openId === s.id} onClick={() => void openHistory(s.id)}>
            {openId === s.id ? 'Hide history' : 'History'}
          </button>
          {isAdmin && s.status !== 'retired' && (
            <button
              type="button"
              className={btn}
              disabled={busy}
              onClick={() => void act(() => switchCopilotSkill({skill_id: s.id, journey_architecture_id: businessId, is_off: !off}))}
            >
              {off ? 'Switch on for this business' : 'Switch off for this business'}
            </button>
          )}
          {isAdmin && meta && s.status !== 'retired' && (
            <button
              type="button"
              className={btn}
              disabled={busy}
              title={info.locked ? 'Let the copilot change this item again' : 'The copilot will follow this item but can only suggest changes'}
              onClick={() => void act(() => setCopilotSkillLock(s.id, !info.locked))}
            >
              {info.locked ? 'Unlock' : 'Lock'}
            </button>
          )}
        </div>
        {openId === s.id && (
          <ul className="space-y-1 border-t border-zinc-100 pt-1" aria-label="History">
            {history.length === 0 && <li className="text-xs text-zinc-500">Loading…</li>}
            {history.map((v, i) => {
              const before = history[i + 1]?.content;
              const changed = changedFields(before, v.content);
              const target = undoTarget(v);
              return (
                <li key={v.id} className="text-xs text-zinc-700">
                  <span>{versionLine(v)}</span>
                  {changed.length > 0 && <span className="text-zinc-500"> ({changed.join(', ')})</span>}
                  {isAdmin && target > 0 && (
                    <button
                      type="button"
                      className={`${btn} ml-2`}
                      disabled={busy}
                      onClick={() => void act(() => undoCopilotSkill({skill_id: s.id, restore_version_no: target}))}
                    >
                      Undo
                    </button>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </li>
    );
  };

  return (
    <div className="px-4 py-2 border-b border-zinc-100 text-sm space-y-2 max-h-80 overflow-y-auto" data-testid="copilot-skills">
      {err && <p role="alert" className="text-red-700">{err}</p>}
      {!data && !err && <p className="text-zinc-500">Loading…</p>}
      {data && (
        <>
          <p className="text-zinc-600">
            {split.live.length === 0
              ? 'The copilot hasn’t saved any skills yet. It writes them as it learns; you can undo any change.'
              : 'The copilot follows these in every chat and scheduled run. New ones start on trial; you can undo any change.'}
          </p>
          {meta && (
            <div className="flex flex-wrap items-center gap-2 text-xs text-zinc-700">
              <span className="font-medium" data-testid="skills-counter">
                {itemCounter(meta.active_count, meta.max_active_items)}
              </span>
              <label className="flex items-center gap-1">
                Kind of work
                <select className="rounded border border-zinc-300 px-1 py-0.5" value={kindFilter} onChange={(e) => setKindFilter(e.target.value)}>
                  <option value="all">All</option>
                  {WORK_KINDS.map((k) => (
                    <option key={k} value={k}>
                      {workKindLabel(k)}
                    </option>
                  ))}
                </select>
              </label>
              <label className="flex items-center gap-1">
                <input type="checkbox" checked={staleOnly} onChange={(e) => setStaleOnly(e.target.checked)} />
                Not used in {meta.stale_after_days} days
              </label>
              {isAdmin && (
                <button type="button" className={btn} aria-expanded={showLimits} onClick={openLimits}>
                  {showLimits ? 'Hide limits' : 'Limits'}
                </button>
              )}
            </div>
          )}
          {meta && showLimits && isAdmin && (
            <div className="flex flex-wrap items-end gap-2 rounded border border-zinc-200 px-2 py-1 text-xs text-zinc-700">
              <label className="flex flex-col">
                Most items
                <input className="w-20 rounded border border-zinc-300 px-1 py-0.5" inputMode="numeric" value={limits.items} onChange={(e) => setLimits((l) => ({...l, items: e.target.value}))} />
              </label>
              <label className="flex flex-col">
                Most words per run
                <input className="w-24 rounded border border-zinc-300 px-1 py-0.5" inputMode="numeric" value={limits.words} onChange={(e) => setLimits((l) => ({...l, words: e.target.value}))} />
              </label>
              <label className="flex flex-col">
                Flag unused after (days)
                <input className="w-20 rounded border border-zinc-300 px-1 py-0.5" inputMode="numeric" value={limits.days} onChange={(e) => setLimits((l) => ({...l, days: e.target.value}))} />
              </label>
              <button type="button" className={btn} disabled={busy} onClick={() => void saveLimits()}>
                Save limits
              </button>
            </div>
          )}
          {meta && live.length === 0 && split.live.length > 0 && <p className="text-zinc-500">Nothing matches these filters.</p>}
          <ul className="space-y-1">{live.map(row)}</ul>
          {retired.length > 0 && (
            <>
              <button type="button" className="text-xs text-indigo-700 hover:underline" aria-expanded={showRetired} onClick={() => setShowRetired((v) => !v)}>
                {showRetired ? 'Hide retired' : `Retired (${retired.length})`}
              </button>
              {showRetired && <ul className="space-y-1">{retired.map(row)}</ul>}
            </>
          )}
        </>
      )}
    </div>
  );
}

/** COP-5 story 05 — what the copilot did on its own, on a schedule: one line per run, report on demand. */
function RunsSection({businessId}: {businessId: number}) {
  const [data, setData] = useState<XanoCopilotRuns | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [openId, setOpenId] = useState(0);

  useEffect(() => {
    let alive = true;
    setData(null);
    setErr(null);
    getCopilotRuns(businessId)
      .then((d) => {
        if (alive) setData(d);
      })
      .catch((e) => {
        if (alive) setErr(e instanceof XanoHttpError ? e.message : "We couldn't load the scheduled runs. Try again.");
      });
    return () => {
      alive = false;
    };
  }, [businessId]);

  const toneClass = (status: string) => {
    const t = runTone(status);
    return t === 'bad' ? 'bg-red-100 text-red-800' : t === 'quiet' ? 'bg-zinc-100 text-zinc-600' : 'bg-emerald-100 text-emerald-800';
  };

  return (
    <div className="px-4 py-2 border-b border-zinc-100 text-sm space-y-2 max-h-64 overflow-y-auto" data-testid="copilot-runs">
      {err && <p role="alert" className="text-red-700">{err}</p>}
      {!data && !err && <p className="text-zinc-500">Loading…</p>}
      {data && (
        <>
          <p className="text-zinc-600">{runsHeadline(data.scheduled_work_on, data.runs.length)}</p>
          <ul className="space-y-1">
            {data.runs.map((r) => {
              const counts = runCountsLine(r);
              const detail = r.report || r.reason || '';
              return (
                <li key={r.id} className="rounded border border-zinc-200 px-2 py-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className={`rounded-full text-xs px-2 py-0.5 ${toneClass(r.status)}`}>{runStatusLabel(r.status)}</span>
                    <span className="text-xs text-zinc-500">{runWhen(r.started_at)}</span>
                    {counts && <span className="text-xs text-zinc-700">{counts}</span>}
                    {detail && (
                      <button
                        type="button"
                        className="text-xs text-indigo-700 hover:underline ml-auto"
                        aria-expanded={openId === r.id}
                        onClick={() => setOpenId((v) => (v === r.id ? 0 : r.id))}
                      >
                        {openId === r.id ? 'Hide' : 'Details'}
                      </button>
                    )}
                  </div>
                  {openId === r.id && detail && <p className="mt-1 whitespace-pre-wrap text-zinc-800">{detail}</p>}
                </li>
              );
            })}
          </ul>
        </>
      )}
    </div>
  );
}

export default function CopilotPanel({open, onClose, userId, isAdmin}: Props) {
  const {pathname, search} = useLocation();
  const [home, setHome] = useState<XanoCopilotHome | null>(null);
  const [archs, setArchs] = useState<XanoJourneyArchitecture[]>([]);
  const [businessId, setBusinessId] = useState<number | null>(null);
  const [conversationId, setConversationId] = useState<number>(0);
  const [lines, setLines] = useState<ChatLine[]>([]);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [loadingConv, setLoadingConv] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [waiting, setWaiting] = useState(0);
  const [settingUp, setSettingUp] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [showKnows, setShowKnows] = useState(false);
  const [showRuns, setShowRuns] = useState(false);
  const [showSkills, setShowSkills] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const switchSeq = useRef(0);

  const loadStart = useCallback(async () => {
    try {
      const [h, list] = await Promise.all([getCopilotHome(), listJourneyArchitectures()]);
      setHome(h);
      setArchs(list);
      setError(null);
    } catch (e) {
      setError(serverText(e, 'Unable to load the copilot right now.'));
    } finally {
      setLoaded(true);
    }
  }, []);

  useEffect(() => {
    if (open && !loaded) void loadStart();
  }, [open, loaded, loadStart]);

  /* Starting business: the last one remembered for this user if still there, else the first. */
  useEffect(() => {
    if (!loaded || businessId != null) return;
    const ids = archs.map((a) => a.id);
    if (home?.has_home && home.journey_architecture_id && !ids.includes(home.journey_architecture_id)) {
      ids.push(home.journey_architecture_id);
    }
    if (ids.length === 0) return;
    const last = readLastBusiness(store(), userId);
    setBusinessId(last != null && ids.includes(last) ? last : ids[0]);
  }, [loaded, archs, home, businessId, userId]);

  /* Switching business loads only that business's latest conversation. Nothing carries over. */
  useEffect(() => {
    if (businessId == null) return;
    const seq = ++switchSeq.current;
    setLines([]);
    setConversationId(0);
    setWaiting(0);
    setLoadingConv(true);
    (async () => {
      try {
        const r = await listCopilotConversations(businessId);
        const id = pickConversation(r.conversations ?? []);
        if (id == null) return;
        const m = await getCopilotConversationMessages(id);
        if (seq !== switchSeq.current) return;
        setConversationId(id);
        setLines(
          (m.messages ?? [])
            .filter((x) => x.role === 'user' || x.role === 'assistant')
            .map((x) => ({key: `m${x.id}`, role: x.role as 'user' | 'assistant', text: messageText(x.content)}))
            .filter((x) => x.text !== ''),
        );
      } catch (e) {
        if (seq === switchSeq.current) setError(serverText(e, 'Unable to load that conversation.'));
      } finally {
        if (seq === switchSeq.current) setLoadingConv(false);
      }
    })();
  }, [businessId]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView?.({block: 'end'});
  }, [lines, sending]);

  /* Esc closes, unless a dialog or an inner confirm is open on top. */
  useEffect(() => {
    if (!open) return;
    const onKey = (ev: KeyboardEvent) => {
      if (ev.key !== 'Escape' || ev.defaultPrevented) return;
      if (document.querySelector('[role="dialog"], [role="alertdialog"], dialog[open]')) return;
      onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  const pickBusiness = (id: number) => {
    if (id === businessId || !Number.isFinite(id)) return;
    setError(null);
    setBusinessId(id);
    writeLastBusiness(store(), userId, id);
  };

  const newConversation = () => {
    switchSeq.current++;
    setConversationId(0);
    setLines([]);
    setWaiting(0);
    setError(null);
    setLoadingConv(false);
  };

  const send = async () => {
    const text = draft.trim();
    if (!text || sending || businessId == null) return;
    setSending(true);
    setError(null);
    const asked = businessId;
    try {
      const r = await sendCopilotChat({
        journey_architecture_id: asked,
        conversation_id: conversationId,
        content: text,
        screen_context: screenContextSummary(pathname, search),
      });
      if (asked !== businessId) return; // switched away while waiting; nothing carries over
      const stamp = Date.now();
      setConversationId(r.conversation_id);
      setLines((l) => [
        ...l,
        {key: `u${stamp}`, role: 'user', text},
        {key: `a${stamp}`, role: 'assistant', text: r.reply},
      ]);
      setWaiting(Number(r.waiting_count) || 0);
      setDraft('');
      if (Number(r.waiting_count) > 0) window.dispatchEvent(new Event('copilot-actions-changed'));
    } catch (e) {
      setError(serverText(e, 'The copilot could not answer right now. Your message is still here.'));
    } finally {
      setSending(false);
    }
  };

  const setUp = async () => {
    setSettingUp(true);
    setError(null);
    try {
      const r = await createCopilotHome();
      let made = 0;
      try {
        for (const title of STARTER_MAPS) {
          await createDraftJourneyMap({title, journey_architecture_id: r.journey_architecture_id});
          made += 1;
        }
      } catch (e) {
        setError(`${serverText(e, 'A starter map could not be created.')} Made ${made} of ${STARTER_MAPS.length} starter maps.`);
      }
      await loadStart();
    } catch (e) {
      setError(serverText(e, 'Unable to set up the copilot’s own business.'));
    } finally {
      setSettingUp(false);
    }
  };

  if (!open) return null;

  const options: {id: number; label: string}[] = archs
    .filter((a) => !(home?.has_home && a.id === home.journey_architecture_id))
    .map((a) => ({id: a.id, label: a.title || `Business ${a.id}`}));
  if (home?.has_home && home.journey_architecture_id) {
    options.push({id: home.journey_architecture_id, label: 'Copilot’s own: how I work'});
  }

  return (
    <aside
      id="copilot-panel"
      aria-label="Copilot"
      className="fixed inset-0 z-40 md:static md:inset-auto md:z-auto w-full md:w-[26rem] shrink-0 flex flex-col bg-white border-l border-zinc-200 shadow-xl md:shadow-none"
    >
      <header className="flex items-center gap-2 px-4 py-3 border-b border-zinc-200">
        <h2 className="font-semibold text-zinc-900 flex-1">{home?.copilot_name || 'Copilot'}</h2>
        <button
          type="button"
          onClick={newConversation}
          disabled={businessId == null || sending}
          className="inline-flex items-center gap-1 rounded-lg border border-zinc-300 px-2 py-1 text-sm text-zinc-700 hover:bg-zinc-50 disabled:opacity-50"
        >
          <Plus className="w-4 h-4" /> New conversation
        </button>
        <button type="button" onClick={onClose} aria-label="Close copilot" className="p-1 rounded hover:bg-zinc-100">
          <X className="w-5 h-5" />
        </button>
      </header>

      {!loaded ? (
        <div className="p-6 text-sm text-zinc-500 flex items-center gap-2">
          <Loader2 className="w-4 h-4 animate-spin" /> Loading…
        </div>
      ) : home && !home.has_copilot ? (
        <div className="p-6 text-sm text-zinc-700 space-y-2">
          <p>Your account doesn&rsquo;t have a copilot yet.</p>
          {isAdmin && (
            <Link to="/team" onClick={onClose} className="text-indigo-600 underline">
              Manage users
            </Link>
          )}
        </div>
      ) : (
        <>
          <div className="px-4 py-2 border-b border-zinc-100 flex items-center gap-2 text-sm">
            <label htmlFor="copilot-business" className="text-zinc-600">Business:</label>
            <select
              id="copilot-business"
              value={businessId ?? ''}
              onChange={(e) => pickBusiness(Number(e.target.value))}
              disabled={sending}
              className="flex-1 min-w-0 rounded-lg border border-zinc-300 px-2 py-1 bg-white"
            >
              {businessId == null && <option value="">No businesses yet</option>}
              {options.map((o) => (
                <option key={o.id} value={o.id}>{o.label}</option>
              ))}
            </select>
          </div>

          {businessId != null && (
            <div className="px-4 py-1 border-b border-zinc-100 text-sm">
              <button
                type="button"
                onClick={() => setShowKnows((v) => !v)}
                aria-expanded={showKnows}
                className="text-indigo-700 hover:underline"
              >
                {showKnows ? 'Hide what the copilot knows' : 'What the copilot knows'}
              </button>
              <button
                type="button"
                onClick={() => setShowRuns((v) => !v)}
                aria-expanded={showRuns}
                className="text-indigo-700 hover:underline ml-4"
              >
                {showRuns ? 'Hide scheduled runs' : 'Scheduled runs'}
              </button>
              {home?.has_home && (
                <button
                  type="button"
                  onClick={() => setShowSkills((v) => !v)}
                  aria-expanded={showSkills}
                  className="text-indigo-700 hover:underline ml-4"
                >
                  {showSkills ? 'Hide how I work' : 'How I work'}
                </button>
              )}
            </div>
          )}
          {showKnows && businessId != null && <MemorySection key={businessId} businessId={businessId} isAdmin={isAdmin} />}
          {showRuns && businessId != null && <RunsSection key={`runs-${businessId}`} businessId={businessId} />}
          {showSkills && businessId != null && (
            <SkillsSection
              key={`skills-${businessId}`}
              businessId={businessId}
              businessName={(id) => options.find((o) => o.id === id)?.label}
              isAdmin={isAdmin}
            />
          )}

          {home && home.has_copilot && !home.has_home && isAdmin && (
            <div className="px-4 py-2 border-b border-zinc-100 text-sm">
              <button
                type="button"
                onClick={() => void setUp()}
                disabled={settingUp}
                className="rounded-lg border border-zinc-300 px-2 py-1 hover:bg-zinc-50 disabled:opacity-50"
              >
                {settingUp ? 'Setting up…' : 'Set up the copilot’s own business'}
              </button>
            </div>
          )}

          <div className="flex-1 min-h-0 overflow-y-auto px-4 py-3 space-y-3" aria-live="polite">
            {loadingConv && (
              <div className="text-sm text-zinc-500 flex items-center gap-2">
                <Loader2 className="w-4 h-4 animate-spin" /> Loading conversation…
              </div>
            )}
            {!loadingConv && lines.length === 0 && !sending && (
              <p className="text-sm text-zinc-500">
                {businessId == null
                  ? 'Create a business first, then talk to the copilot about it.'
                  : 'Ask the copilot anything about this business.'}
              </p>
            )}
            {lines.map((l) => (
              <div key={l.key} className={l.role === 'user' ? 'flex justify-end' : 'flex justify-start'}>
                <div
                  className={`max-w-[85%] whitespace-pre-wrap rounded-2xl px-3 py-2 text-sm ${
                    l.role === 'user' ? 'bg-indigo-600 text-white' : 'bg-zinc-100 text-zinc-900'
                  }`}
                >
                  {l.text}
                </div>
              </div>
            ))}
            {sending && (
              <div className="text-sm text-zinc-500 flex items-center gap-2">
                <Loader2 className="w-4 h-4 animate-spin" /> thinking…
              </div>
            )}
            {waiting > 0 && (
              <Link to="/approvals" onClick={onClose} className="block text-sm text-indigo-700 underline">
                {waiting} {waiting === 1 ? 'item' : 'items'} waiting for you
              </Link>
            )}
            <div ref={bottomRef} />
          </div>

          <div className="border-t border-zinc-200 p-3 space-y-2">
            {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
            <div className="flex gap-2 items-end">
              <textarea
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
                    e.preventDefault();
                    void send();
                  }
                }}
                rows={2}
                aria-label="Message to the copilot"
                placeholder="Message the copilot"
                disabled={businessId == null}
                className="flex-1 resize-none rounded-lg border border-zinc-300 px-2 py-1.5 text-sm"
              />
              <button
                type="button"
                onClick={() => void send()}
                disabled={sending || draft.trim() === '' || businessId == null}
                className="rounded-lg bg-indigo-600 text-white px-3 py-2 text-sm disabled:opacity-50"
              >
                Send
              </button>
            </div>
          </div>
        </>
      )}
    </aside>
  );
}
