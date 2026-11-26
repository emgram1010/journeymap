// REQ-1 (US-REQ-1-03) — the people on THIS plan, and whether each is tied to a lasting profile. What a
// person holds (and, later, when they work) lives on the profile, so a person with no profile holds
// nothing as far as the system can tell. Shown in Workspace Settings. Everyone in the account can
// read it; only an admin person can link, make a profile, or clear a link (the server re-checks, and
// refuses an AI). Nothing is ever linked by name on its own: a name match is only OFFERED, and an
// admin clicks each one. The account-wide "check everyone" reports first and only writes on a second
// click.
import {useCallback, useEffect, useState} from 'react';
import {AlertCircle, Loader2} from 'lucide-react';
import {
  listPersonLinks,
  linkPerson,
  unlinkPerson,
  createProfileForPerson,
  fillPersonLinks,
  listAgentProfiles,
  type PersonLinkRow,
  type FillAnswer,
  type AgentProfileListEntry,
} from '../planner/plannerApi';
import {personLinkLabel} from './requirementModel';

const friendly = (err: unknown, fallback: string): string =>
  (err as {serverMessage?: string | null} | null)?.serverMessage || (err instanceof Error ? err.message : fallback);

export default function PlanPeopleProfiles({workspaceId, isAdmin}: {workspaceId: number; isAdmin: boolean}) {
  const [people, setPeople] = useState<PersonLinkRow[] | null>(null);
  const [profiles, setProfiles] = useState<AgentProfileListEntry[]>([]);
  const [busyId, setBusyId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [picked, setPicked] = useState<Record<number, number>>({});
  const [fill, setFill] = useState<FillAnswer | null>(null);
  const [fillBusy, setFillBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const [p, pr] = await Promise.all([listPersonLinks(workspaceId), isAdmin ? listAgentProfiles(true) : Promise.resolve({profiles: [] as AgentProfileListEntry[]})]);
      setPeople(p.people);
      setProfiles(pr.profiles);
    } catch (err) {
      setError(friendly(err, 'Could not load the people on this plan.'));
    }
  }, [workspaceId, isAdmin]);

  useEffect(() => { setPeople(null); setError(null); setFill(null); void load(); }, [load]);

  const act = async (agentId: number, fn: () => Promise<unknown>, fallback: string) => {
    setBusyId(agentId);
    setError(null);
    try {
      await fn();
      await load();
    } catch (err) {
      setError(friendly(err, fallback));
    } finally {
      setBusyId(null);
    }
  };

  const runFill = async (apply: boolean) => {
    setFillBusy(true);
    setError(null);
    try {
      const res = await fillPersonLinks(apply);
      setFill(res);
      if (apply) await load();
    } catch (err) {
      setError(friendly(err, 'Could not check the plans. Try again.'));
    } finally {
      setFillBusy(false);
    }
  };

  const unlinked = (people ?? []).filter(p => !p.profile_id).length;

  return (
    <section className="border-t border-neutral-100 pt-4 flex flex-col gap-2" data-testid="plan-people-profiles">
      <h3 className="text-xs font-semibold text-neutral-900">People and their profiles</h3>
      <p className="text-[11px] text-neutral-500">
        What a person holds is recorded on their profile. Someone with no profile holds nothing as far as the system can tell.
        {people && unlinked > 0 ? ` ${unlinked} of ${people.length} on this plan ${unlinked === 1 ? 'has' : 'have'} no profile.` : ''}
      </p>
      {error && <p className="text-xs text-red-700 flex items-start gap-1.5" role="alert"><AlertCircle className="w-3.5 h-3.5 mt-0.5 shrink-0" />{error}</p>}
      {people === null ? (
        <p className="text-xs text-neutral-400 flex items-center gap-1.5"><Loader2 className="w-3.5 h-3.5 animate-spin" /> Loading…</p>
      ) : people.length === 0 ? (
        <p className="text-xs text-neutral-400">No one is on this plan yet.</p>
      ) : (
        <ul className="divide-y divide-neutral-100 border border-neutral-200 rounded-md">
          {people.map(p => {
            const linked = p.profile_id !== 0;
            const busy = busyId === p.planner_agent_id;
            return (
              <li key={p.planner_agent_id} className="px-3 py-2 flex flex-col gap-1.5" data-testid={`person-link-${p.planner_agent_id}`}>
                <div className="flex items-center gap-2">
                  <span className="text-xs font-medium text-neutral-900 flex-1 min-w-0 truncate">{p.name}</span>
                  <span className={`text-[11px] shrink-0 ${linked ? 'text-neutral-600' : 'text-amber-700'}`}>{personLinkLabel(p)}</span>
                  {isAdmin && linked && (
                    <button type="button" disabled={busy} onClick={() => void act(p.planner_agent_id, () => unlinkPerson(workspaceId, p.planner_agent_id), 'Could not clear that link.')} className="text-[11px] text-neutral-500 underline decoration-dotted hover:text-neutral-800">
                      Clear
                    </button>
                  )}
                </div>
                {isAdmin && !linked && (
                  <div className="flex flex-wrap items-center gap-1.5">
                    {p.login_profile_id !== 0 && (
                      <button type="button" disabled={busy} onClick={() => void act(p.planner_agent_id, () => linkPerson(workspaceId, p.planner_agent_id, p.login_profile_id), 'Could not link them.')} className="px-2 py-1 text-[11px] font-semibold text-white bg-neutral-900 rounded disabled:opacity-50">
                        Link to their profile
                      </button>
                    )}
                    {p.login_profile_id === 0 && p.name_match_profile_id !== 0 && (
                      <button type="button" disabled={busy} onClick={() => void act(p.planner_agent_id, () => linkPerson(workspaceId, p.planner_agent_id, p.name_match_profile_id), 'Could not link them.')} className="px-2 py-1 text-[11px] border border-neutral-300 rounded text-neutral-800 hover:bg-neutral-100 disabled:opacity-50" title="A profile with exactly this name">
                        Link to the profile named "{p.name}"
                      </button>
                    )}
                    {p.login_profile_id === 0 && p.name_match_count > 1 && (
                      <span className="text-[11px] text-neutral-500">{p.name_match_count} profiles share this name: choose one.</span>
                    )}
                    {p.login_profile_id === 0 && p.name_match_profile_id === 0 && (
                      <button type="button" disabled={busy} onClick={() => void act(p.planner_agent_id, () => createProfileForPerson(workspaceId, p.planner_agent_id), 'Could not make a profile.')} className="px-2 py-1 text-[11px] font-semibold text-white bg-neutral-900 rounded disabled:opacity-50">
                        {busy ? 'Making…' : 'Create profile'}
                      </button>
                    )}
                    <select value={picked[p.planner_agent_id] ?? 0} onChange={e => setPicked({...picked, [p.planner_agent_id]: Number(e.target.value)})} className="border border-neutral-300 rounded px-1.5 py-1 text-[11px]" aria-label={`Choose a profile for ${p.name}`}>
                      <option value={0}>Choose a profile…</option>
                      {profiles.map(({profile, display_name}) => <option key={profile.id} value={profile.id}>{display_name || `Profile ${profile.id}`}</option>)}
                    </select>
                    <button type="button" disabled={busy || !(picked[p.planner_agent_id] ?? 0)} onClick={() => void act(p.planner_agent_id, () => linkPerson(workspaceId, p.planner_agent_id, picked[p.planner_agent_id]), 'Could not link them.')} className="px-2 py-1 text-[11px] border border-neutral-300 rounded text-neutral-800 hover:bg-neutral-100 disabled:opacity-40">
                      Link
                    </button>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      )}
      {isAdmin && (
        <div className="mt-1 flex flex-col gap-1.5">
          <div className="flex items-center gap-2">
            <p className="text-[11px] text-neutral-500 flex-1">Check everyone on every plan: link each person to the profile of their login when there is exactly one. Nothing is written until you confirm.</p>
            <button type="button" disabled={fillBusy} onClick={() => void runFill(false)} className="px-2.5 py-1 text-[11px] border border-neutral-300 rounded text-neutral-800 hover:bg-neutral-100 disabled:opacity-50">
              {fillBusy ? 'Checking…' : 'Check all plans'}
            </button>
          </div>
          {fill && (
            <div className="border border-neutral-200 rounded p-2 text-[11px] text-neutral-800 flex flex-col gap-1" data-testid="fill-report">
              <p>
                {fill.people_checked} people checked: {fill.applied ? `${fill.linked} linked now, ` : `${fill.would_link} can be linked by login, `}
                {fill.already_linked} already linked, {fill.no_login.length} with no login, {fill.no_profile_yet.length} whose login has no profile yet, {fill.several_profiles.length} whose login has several profiles.
              </p>
              {!fill.applied && fill.would_link > 0 && (
                <button type="button" disabled={fillBusy} onClick={() => void runFill(true)} className="self-start px-2.5 py-1 font-semibold text-white bg-neutral-900 rounded disabled:opacity-50">
                  Link {fill.would_link} {fill.would_link === 1 ? 'person' : 'people'} now
                </button>
              )}
              {fill.no_profile_yet.length > 0 && <p className="text-neutral-500">People with a login but no profile are made one with "Create profile" on their plan.</p>}
            </div>
          )}
        </div>
      )}
    </section>
  );
}
