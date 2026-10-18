// PLAN-3 (US-PLAN-3-04) — Minimal template builder, completing PLAN-1's
// own never-built UI (US-PLAN-1-05) and adding the agent roster on top
// of it. "New plan from a template" (CreateWorkspaceModal) stays the
// instantiation flow; this is where a template itself gets built.
import {useEffect, useState} from 'react';
import {X, FileStack, ChevronDown, ChevronRight, Plus} from 'lucide-react';
import {
  listTemplates,
  createTemplate,
  updateTemplate,
  searchJourneyMaps,
  listAgentProfiles,
  type TemplateListEntry,
  type JourneyMapSearchResult,
  type AgentProfileListEntry,
} from '../plannerApi';

interface TemplatesModalProps {
  isOpen: boolean;
  onClose: () => void;
  /** So a newly-built template shows up immediately in "New plan from a template" without a second fetch. */
  onTemplatesChanged?: () => void;
}

export function TemplatesModal({isOpen, onClose, onTemplatesChanged}: TemplatesModalProps) {
  const [templates, setTemplates] = useState<TemplateListEntry[]>([]);
  const [candidateMaps, setCandidateMaps] = useState<JourneyMapSearchResult[]>([]);
  const [candidateAgents, setCandidateAgents] = useState<AgentProfileListEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<number | null>(null);

  const [newName, setNewName] = useState('');
  const [newWindowDays, setNewWindowDays] = useState(7);
  const [newStartTime, setNewStartTime] = useState('08:00');
  const [creating, setCreating] = useState(false);

  const [pickedMapByTemplate, setPickedMapByTemplate] = useState<Record<number, number | null>>({});
  const [pickedAgentByTemplate, setPickedAgentByTemplate] = useState<Record<number, number | null>>({});
  const [busyTemplateId, setBusyTemplateId] = useState<number | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const [templateData, mapData, agentData] = await Promise.all([
        listTemplates(),
        searchJourneyMaps(),
        listAgentProfiles(),
      ]);
      setTemplates(templateData.templates);
      setCandidateMaps(mapData.results);
      setCandidateAgents(agentData.profiles);
    } catch {
      setError("Couldn't load templates. Try again.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isOpen) void load();
  }, [isOpen]);

  if (!isOpen) return null;

  const handleCreate = async () => {
    if (!newName.trim()) {
      setError('Give the template a name.');
      return;
    }
    setCreating(true);
    setError(null);
    try {
      const {template} = await createTemplate({name: newName.trim(), window_days: newWindowDays, default_start_time: newStartTime});
      setNewName('');
      setNewWindowDays(7);
      setNewStartTime('08:00');
      await load();
      onTemplatesChanged?.();
      setExpandedId(template.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't create that template.");
    } finally {
      setCreating(false);
    }
  };

  const handleAddMap = async (templateId: number) => {
    const mapId = pickedMapByTemplate[templateId];
    if (!mapId) return;
    setBusyTemplateId(templateId);
    setError(null);
    try {
      await updateTemplate(templateId, {add_map_ids: [mapId]});
      setPickedMapByTemplate((p) => ({...p, [templateId]: null}));
      await load();
      onTemplatesChanged?.();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't add that map.");
    } finally {
      setBusyTemplateId(null);
    }
  };

  const handleAddAgent = async (templateId: number) => {
    const profileId = pickedAgentByTemplate[templateId];
    if (!profileId) return;
    setBusyTemplateId(templateId);
    setError(null);
    try {
      await updateTemplate(templateId, {add_agent_profile_ids: [profileId]});
      setPickedAgentByTemplate((p) => ({...p, [templateId]: null}));
      await load();
      onTemplatesChanged?.();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't add that agent.");
    } finally {
      setBusyTemplateId(null);
    }
  };

  const handleToggleActive = async (templateId: number, nextActive: boolean) => {
    setError(null);
    try {
      await updateTemplate(templateId, {is_active: nextActive});
      await load();
      onTemplatesChanged?.();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't update that template.");
    }
  };

  return (
    <div
      id="templates-modal-overlay"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        id="templates-modal"
        className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-2xl flex flex-col max-h-[85vh] overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="h-14 px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
          <div className="flex items-center gap-2">
            <FileStack className="w-4 h-4 text-neutral-700" />
            <h2 className="text-sm font-bold text-neutral-900">Plan templates</h2>
          </div>
          <button type="button" onClick={onClose} className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50" aria-label="Close">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-6 overflow-y-auto flex flex-col gap-5 text-sm">
          <p className="text-[11px] text-neutral-500">
            A template is a reusable shape — window length, start time, which maps and which agents a new plan starts with. It names no specific job; those are added once a plan is created from it.
          </p>

          {error && <p className="text-xs text-red-600">{error}</p>}

          <section className="border border-neutral-200 rounded-md p-3">
            <h3 className="text-xs font-semibold text-neutral-900 mb-2">New template</h3>
            <div className="grid grid-cols-[1fr_90px_90px_auto] gap-2 items-end">
              <label className="flex flex-col gap-1">
                <span className="text-[10px] text-neutral-500">Name</span>
                <input
                  type="text"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  placeholder="e.g. Weekly Ops"
                  className="text-xs px-2 py-1.5 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900"
                />
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-[10px] text-neutral-500">Window (days)</span>
                <input
                  type="number"
                  min={1}
                  max={366}
                  value={newWindowDays}
                  onChange={(e) => setNewWindowDays(Number(e.target.value) || 1)}
                  className="text-xs px-2 py-1.5 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono"
                />
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-[10px] text-neutral-500">Start time</span>
                <input
                  type="text"
                  value={newStartTime}
                  onChange={(e) => setNewStartTime(e.target.value)}
                  placeholder="08:00"
                  className="text-xs px-2 py-1.5 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono"
                />
              </label>
              <button
                type="button"
                disabled={creating || !newName.trim()}
                onClick={() => void handleCreate()}
                className="px-3 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800 disabled:opacity-50"
              >
                {creating ? 'Creating…' : 'Create'}
              </button>
            </div>
          </section>

          <section>
            <h3 className="text-xs font-semibold text-neutral-900 mb-2">Existing templates</h3>
            {loading && templates.length === 0 ? (
              <p className="text-xs text-neutral-400">Loading…</p>
            ) : templates.length === 0 ? (
              <p className="text-xs text-neutral-400">No templates yet — create one above.</p>
            ) : (
              <ul className="divide-y divide-neutral-100 border border-neutral-200 rounded-md">
                {templates.map(({template, maps, agents}) => {
                  const isExpanded = expandedId === template.id;
                  const addableMaps = candidateMaps.filter((m) => !maps.some((cm) => cm.map_id === m.map_id));
                  const addableAgents = candidateAgents.filter((a) => !agents.some((ca) => ca.profile_id === a.profile.id));
                  return (
                    <li key={template.id} className="px-3 py-2">
                      <button
                        type="button"
                        onClick={() => setExpandedId(isExpanded ? null : template.id)}
                        className="w-full flex items-center justify-between text-left"
                      >
                        <span className="flex items-center gap-1.5 text-xs font-medium text-neutral-900">
                          {isExpanded ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                          {template.name}
                          {!template.is_active && <span className="text-[10px] text-neutral-400">(archived)</span>}
                        </span>
                        <span className="text-[10px] text-neutral-400">
                          {template.window_days}d · {template.default_start_time} · {maps.length} map{maps.length === 1 ? '' : 's'} · {agents.length} agent{agents.length === 1 ? '' : 's'}
                        </span>
                      </button>

                      {isExpanded && (
                        <div className="mt-2 pl-5 flex flex-col gap-3">
                          <div>
                            <p className="text-[10px] font-semibold text-neutral-500 uppercase tracking-wide mb-1">Maps</p>
                            {maps.length > 0 && (
                              <ul className="text-[11px] text-neutral-700 mb-1.5 list-disc list-inside">
                                {maps.map((m) => (
                                  <li key={m.map_id}>{m.title ?? `Map #${m.map_id}`}</li>
                                ))}
                              </ul>
                            )}
                            {addableMaps.length > 0 && (
                              <div className="flex items-center gap-2">
                                <select
                                  value={pickedMapByTemplate[template.id] ?? ''}
                                  onChange={(e) => setPickedMapByTemplate((p) => ({...p, [template.id]: Number(e.target.value) || null}))}
                                  className="flex-1 text-[11px] px-2 py-1 border border-neutral-200 rounded-md bg-white"
                                >
                                  <option value="">Add a map…</option>
                                  {/* GAP-FIX W7 — same rule as the plan's own map
                                      picker: a map with no published version is
                                      shown so it can be found, and disabled so it
                                      can't be chosen and then refused. */}
                                  {addableMaps.map((m) => (
                                    <option key={m.map_id} value={m.map_id} disabled={m.publishedVersionNo === null}>
                                      {m.title}
                                      {m.publishedVersionNo === null ? ' — publish it first' : ` (v${m.publishedVersionNo})`}
                                    </option>
                                  ))}
                                </select>
                                <button
                                  type="button"
                                  disabled={!pickedMapByTemplate[template.id] || busyTemplateId === template.id}
                                  onClick={() => void handleAddMap(template.id)}
                                  className="p-1.5 text-neutral-600 hover:text-neutral-900 hover:bg-neutral-100 rounded disabled:opacity-50"
                                  title="Add map"
                                >
                                  <Plus className="w-3.5 h-3.5" />
                                </button>
                              </div>
                            )}
                          </div>

                          <div>
                            <p className="text-[10px] font-semibold text-neutral-500 uppercase tracking-wide mb-1">Agent roster</p>
                            {agents.length > 0 && (
                              <ul className="text-[11px] text-neutral-700 mb-1.5 list-disc list-inside">
                                {agents.map((a) => (
                                  <li key={a.profile_id}>{a.name ?? `Agent #${a.profile_id}`}</li>
                                ))}
                              </ul>
                            )}
                            {addableAgents.length > 0 ? (
                              <div className="flex items-center gap-2">
                                <select
                                  value={pickedAgentByTemplate[template.id] ?? ''}
                                  onChange={(e) => setPickedAgentByTemplate((p) => ({...p, [template.id]: Number(e.target.value) || null}))}
                                  className="flex-1 text-[11px] px-2 py-1 border border-neutral-200 rounded-md bg-white"
                                >
                                  <option value="">Add an agent…</option>
                                  {addableAgents.map((a) => (
                                    <option key={a.profile.id} value={a.profile.id}>
                                      {a.display_name}
                                    </option>
                                  ))}
                                </select>
                                <button
                                  type="button"
                                  disabled={!pickedAgentByTemplate[template.id] || busyTemplateId === template.id}
                                  onClick={() => void handleAddAgent(template.id)}
                                  className="p-1.5 text-neutral-600 hover:text-neutral-900 hover:bg-neutral-100 rounded disabled:opacity-50"
                                  title="Add agent"
                                >
                                  <Plus className="w-3.5 h-3.5" />
                                </button>
                              </div>
                            ) : (
                              <p className="text-[10px] text-neutral-400">
                                No eligible agents to add — tag someone in the Agents screen first.
                              </p>
                            )}
                          </div>

                          <label className="flex items-center gap-1.5 text-[11px] text-neutral-600">
                            <input type="checkbox" checked={template.is_active} onChange={(e) => void handleToggleActive(template.id, e.target.checked)} />
                            Active (visible when starting a new plan)
                          </label>
                        </div>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        </div>
      </div>
    </div>
  );
}
