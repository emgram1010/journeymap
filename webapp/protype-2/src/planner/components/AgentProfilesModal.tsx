// PLAN-2 (US-PLAN-2-03) — Minimal UI: tag a teammate as an agent, or
// add an AI agent with no login. Account-scoped (no workspace id
// anywhere here) — same shell styling as SettingsModal for consistency.
//
// GAP-FIX W9 (2026-10-17) — this screen now knows who is signed in.
// D-2's rule (gap-fix Part 1 #2) is enforced server-side: anyone may
// manage their OWN profile, only an admin may manage someone else's
// or an AI agent. Until now the screen offered every action to
// everyone and let the server refuse, so a member's only way to learn
// the rule was to be told no. The role comes from the same `/auth/me`
// the session already holds — no new request, and the server still
// re-checks every call regardless of what this component renders.
import {useEffect, useState} from 'react';
import {X, Users, Plus, Lock} from 'lucide-react';
import {useAuth} from '../../AuthContext';
import {
  listAgentProfiles,
  createAgentProfile,
  updateAgentProfile,
  listTeamMembers,
  type AgentProfileListEntry,
  type TeamMember,
} from '../plannerApi';

interface AgentProfilesModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function AgentProfilesModal({isOpen, onClose}: AgentProfilesModalProps) {
  const {user} = useAuth();
  const isAdmin = user?.role === 'admin';
  const myUserId = user?.id ?? 0;
  const [profiles, setProfiles] = useState<AgentProfileListEntry[]>([]);
  const [teamMembers, setTeamMembers] = useState<TeamMember[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [newAiName, setNewAiName] = useState('');
  const [busyUserId, setBusyUserId] = useState<number | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const [profileData, teamData] = await Promise.all([listAgentProfiles(true), listTeamMembers()]);
      setProfiles(profileData.profiles);
      setTeamMembers(teamData);
    } catch {
      setError("Couldn't load agents. Try again.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isOpen) void load();
  }, [isOpen]);

  if (!isOpen) return null;

  const profiledUserIds = new Set(profiles.map((p) => p.profile.user_id).filter((id) => id !== 0));
  // A member may only ever tag themselves (D-2). Showing them the whole
  // team and refusing the click is how this screen behaved before W9.
  const candidateMembers = teamMembers
    .filter((m) => !profiledUserIds.has(m.id))
    .filter((m) => isAdmin || m.id === myUserId);

  /** Own profile, or admin — mirrors the server's own check in 575. */
  const canManage = (profileUserId: number, kind: 'person' | 'ai') =>
    isAdmin || (kind === 'person' && profileUserId === myUserId && profileUserId !== 0);

  const handleTagMember = async (userId: number) => {
    setBusyUserId(userId);
    setError(null);
    try {
      await createAgentProfile({user_id: userId});
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't tag that person as an agent.");
    } finally {
      setBusyUserId(null);
    }
  };

  const handleAddAi = async () => {
    const name = newAiName.trim();
    if (!name) return;
    setBusyUserId(0);
    setError(null);
    try {
      await createAgentProfile({name});
      setNewAiName('');
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't add that AI agent.");
    } finally {
      setBusyUserId(null);
    }
  };

  const handleToggleEligible = async (profileId: number, nextEligible: boolean) => {
    setError(null);
    try {
      await updateAgentProfile(profileId, {is_eligible: nextEligible});
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't update that agent.");
    }
  };

  return (
    <div
      id="agent-profiles-modal-overlay"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        id="agent-profiles-modal"
        className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-lg flex flex-col max-h-[85vh] overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="h-14 px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
          <div className="flex items-center gap-2">
            <Users className="w-4 h-4 text-neutral-700" />
            <h2 className="text-sm font-bold text-neutral-900">Agents</h2>
          </div>
          <button type="button" onClick={onClose} className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50" aria-label="Close">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-6 overflow-y-auto flex flex-col gap-5 text-sm">
          <p className="text-[11px] text-neutral-500">
            Tagging someone here makes them available to pick for a plan template's agent roster — it doesn't add them to any plan by itself.
          </p>

          {error && <p className="text-xs text-red-600">{error}</p>}
          {loading && profiles.length === 0 ? (
            <p className="text-xs text-neutral-400">Loading…</p>
          ) : (
            <section>
              <h3 className="text-xs font-semibold text-neutral-900 mb-2">Current agents</h3>
              {profiles.length === 0 ? (
                <p className="text-xs text-neutral-400">No one is tagged as an agent yet.</p>
              ) : (
                <ul className="divide-y divide-neutral-100 border border-neutral-200 rounded-md">
                  {profiles.map(({profile, display_name: displayName}) => (
                    <li key={profile.id} className="flex items-center justify-between px-3 py-2">
                      <div className="min-w-0">
                        <p className="text-xs font-medium text-neutral-900 truncate">{displayName || '(unnamed)'}</p>
                        <p className="text-[10px] text-neutral-400">{profile.kind === 'ai' ? 'AI agent' : 'Person'}</p>
                      </div>
                      <label
                        className={`flex items-center gap-1.5 text-[11px] shrink-0 ${
                          canManage(profile.user_id, profile.kind) ? 'text-neutral-600' : 'text-neutral-300'
                        }`}
                        title={canManage(profile.user_id, profile.kind) ? undefined : 'Only an admin can change this agent.'}
                      >
                        <input
                          type="checkbox"
                          checked={profile.is_eligible}
                          disabled={!canManage(profile.user_id, profile.kind)}
                          onChange={(e) => void handleToggleEligible(profile.id, e.target.checked)}
                        />
                        Eligible
                      </label>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          )}

          <section>
            <h3 className="text-xs font-semibold text-neutral-900 mb-2">{isAdmin ? 'Tag a teammate' : 'Tag yourself'}</h3>
            {!isAdmin && (
              <p className="text-[11px] text-neutral-500 mb-2 flex items-start gap-1">
                <Lock className="w-3 h-3 mt-0.5 shrink-0 text-neutral-400" />
                You can tag yourself. Only an admin can tag someone else or add an AI agent.
              </p>
            )}
            {candidateMembers.length === 0 ? (
              <p className="text-xs text-neutral-400">
                {isAdmin ? 'Everyone on this account is already tagged.' : 'You are already tagged as an agent.'}
              </p>
            ) : (
              <ul className="divide-y divide-neutral-100 border border-neutral-200 rounded-md">
                {candidateMembers.map((m) => (
                  <li key={m.id} className="flex items-center justify-between px-3 py-2">
                    <span className="text-xs text-neutral-800 truncate">{m.name}</span>
                    <button
                      type="button"
                      disabled={busyUserId === m.id}
                      onClick={() => void handleTagMember(m.id)}
                      className="flex items-center gap-1 px-2 py-1 text-[11px] font-medium text-neutral-600 hover:text-neutral-900 hover:bg-neutral-100 rounded disabled:opacity-50"
                    >
                      <Plus className="w-3 h-3" />
                      Tag as agent
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </section>

          {isAdmin && (
          <section>
            <h3 className="text-xs font-semibold text-neutral-900 mb-2">Add an AI agent</h3>
            <div className="flex items-center gap-2">
              <input
                type="text"
                value={newAiName}
                onChange={(e) => setNewAiName(e.target.value)}
                placeholder="e.g. Route Optimizer Bot"
                className="flex-1 text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900"
              />
              <button
                type="button"
                disabled={!newAiName.trim() || busyUserId === 0}
                onClick={() => void handleAddAi()}
                className="px-3 py-2 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800 disabled:opacity-50"
              >
                Add
              </button>
            </div>
          </section>
          )}
        </div>
      </div>
    </div>
  );
}
