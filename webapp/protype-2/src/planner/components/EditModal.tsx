import { useState, useEffect, useRef } from 'react';
import { 
  X, 
  Lock, 
  RotateCcw, 
  AlertCircle, 
  CheckCircle2, 
  Calendar, 
  User, 
  Clock, 
  FileText,
  AlertTriangle,
  Send,
  Sparkles,
  Bot
} from 'lucide-react';
import { Task, Timeline, Agent, AgentKind, TaskPlanningStatus, ModalEntity, AppSettings } from '../types';
export type { ModalEntity } from '../types';
import { isDateOutOfWindow, formatShortDate } from '../utils/dateUtils';
import { formatMinutesToTime, parseTimeToMinutes } from '../utils/planningLogic';
import { AGENT_PALETTE } from '../data/initialData';
import { getNextAgentColor } from '../utils/agentUtils';
import { listTeamMembers, type TeamMember } from '../plannerApi';

interface EditModalProps {
  isOpen: boolean;
  entity: ModalEntity | null;
  onClose: () => void;
  // PLN-9: these now hit the real backend, which can genuinely reject
  // a save (duplicate name, bad duration, a cell someone else took).
  // Returning `false` tells this modal to stay open with the user's
  // typing intact (CLAUDE.md: "keep the user's typing on any rejected
  // save") instead of closing as if it had worked; the message itself
  // surfaces through App.tsx's own toast. A `void` return (or no
  // handler at all) is treated the same as `true` — close as before.
  onSaveTask: (taskId: string, updates: Partial<Task>) => boolean | void | Promise<boolean | void>;
  onSaveTimeline: (timelineId: string, updates: Partial<Timeline>) => boolean | void | Promise<boolean | void>;
  settings: AppSettings;
  onDeleteAgent?: (agentId: string) => void;
  // GAP-FIX W2: `userId` joins the save payload — '' means "no login".
  // It is deliberately NOT optional-by-omission: the planner clearing a
  // link has to be distinguishable from a caller that never asked.
  onSaveAgent?: (agentId: string | null, updates: { name: string; kind: AgentKind; color: string; dailyCapacityHours: number; modelId?: string; userId: string }) => boolean | void | Promise<boolean | void>;
  // PLN-6 (US-PLN-6-05), wired 2026-10-16. Optional for the same
  // reason as onDeleteAgent: when it isn't passed, no delete control
  // renders at all, rather than offering one that can't work.
  onDeleteTimeline?: (timelineId: string) => void;
  onConfirmBulkPublish?: (timelineIdsToPublish: string[]) => void;
  onConfirmPublish?: (timelineId: string) => void;
  onReopenTimeline: (timelineId: string) => void;
}

export function EditModal({
  isOpen,
  entity,
  settings,
  onClose,
  onSaveTask,
  onSaveTimeline,
  onSaveAgent,
  onDeleteAgent,
  onDeleteTimeline,
  onConfirmBulkPublish,
  onConfirmPublish,
  onReopenTimeline,
}: EditModalProps) {
  // Modal states
  const [showDiscardConfirm, setShowDiscardConfirm] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});
  // PLN-9: true while a save is in flight against the real backend.
  // Declared up here with the rest of this component's hooks, NOT next
  // to handleSave below — that function is defined after this
  // component's `if (!isOpen || !entity) return null` early return, so
  // a hook declared down there would be skipped whenever the modal is
  // closed, changing the hook count between renders (confirmed live:
  // "Rendered more hooks than during the previous render" the moment
  // the modal opened).
  const [isSaving, setIsSaving] = useState(false);

  // Task form state
  const [taskTitle, setTaskTitle] = useState('');
  const [taskStart, setTaskStart] = useState('');
  const [taskDuration, setTaskDuration] = useState<string>('30');
  const [taskAssignee, setTaskAssignee] = useState('');
  const [taskStatus, setTaskStatus] = useState<TaskPlanningStatus>('planned');
  const [taskNotes, setTaskNotes] = useState('');
  const [taskNeedsInfoReason, setTaskNeedsInfoReason] = useState('');

  // Timeline form state
  const [tlDate, setTlDate] = useState('');
  const [tlStartTime, setTlStartTime] = useState('08:00');

  // Agent form state
  const [agentName, setAgentName] = useState('');
  const [agentKind, setAgentKind] = useState<AgentKind>('person');
  const [agentColor, setAgentColor] = useState(AGENT_PALETTE[0].hex);
  const [agentCapacity, setAgentCapacity] = useState<number>(8);
  const [agentModelId, setAgentModelId] = useState<string>('');
  // GAP-FIX W2 — "Who does this work?" The team list is loaded by this
  // modal rather than threaded through PlannerApp: nothing else in the
  // planner reads account members, same reasoning as the map picker in
  // WorkspaceSettingsModal.
  const [agentUserId, setAgentUserId] = useState<string>('');
  const [teamMembers, setTeamMembers] = useState<TeamMember[]>([]);
  const [teamError, setTeamError] = useState(false);
  const [confirmRemoveAgent, setConfirmRemoveAgent] = useState(false);
  const [confirmDeleteTimeline, setConfirmDeleteTimeline] = useState(false);

  // Trap focus ref
  const modalRef = useRef<HTMLDivElement>(null);
  const initialFocusRef = useRef<HTMLInputElement>(null);

  // Initialize data when entity changes
  useEffect(() => {
    if (!entity) return;

    setShowDiscardConfirm(false);
    setHasChanges(false);
    setErrors({});
    setConfirmDeleteTimeline(false);

    if (entity.type === 'task') {
      const t = entity.task;
      setTaskTitle(t.title);
      setTaskStart(t.planned_start || '');
      setTaskDuration(t.duration ? t.duration.toString() : '30');
      setTaskAssignee(t.assignee || '');
      setTaskStatus(t.status);
      setTaskNotes(t.notes || '');
      setTaskNeedsInfoReason(t.needsInfoReason || '');
    } else if (entity.type === 'timeline') {
      const tl = entity.timeline;
      setTlDate(tl.plannedDate);
      setTlStartTime(tl.startTime || '08:00');
    } else if (entity.type === 'agent') {
      if (entity.agent) {
        setAgentName(entity.agent.name);
        setAgentKind(entity.agent.kind);
        setAgentColor(entity.agent.color);
        setAgentCapacity(entity.agent.dailyCapacityHours || 8);
        setAgentModelId(entity.agent.modelId || '');
        setAgentUserId(entity.agent.userId || '');
        setConfirmRemoveAgent(false);
      } else {
        setAgentName('');
        setAgentKind('person');
        setAgentColor(AGENT_PALETTE[0].hex);
        setAgentCapacity(8);
        setAgentModelId('');
        setAgentUserId('');
      }
    }
  }, [entity]);

  // GAP-FIX W2 — the account's logins, for the "Who does this work?"
  // picker. A failure here is not fatal: the picker degrades to a
  // plain explanation rather than blocking the whole agent form.
  useEffect(() => {
    if (!isOpen || entity?.type !== 'agent') return;
    let cancelled = false;
    setTeamError(false);
    listTeamMembers()
      .then((members) => { if (!cancelled) setTeamMembers(members); })
      .catch(() => { if (!cancelled) setTeamError(true); });
    return () => { cancelled = true; };
  }, [isOpen, entity?.type]);

  // Focus initial field on open
  useEffect(() => {
    if (isOpen) {
      setTimeout(() => {
        initialFocusRef.current?.focus();
      }, 50);
    }
  }, [isOpen]);

  // Prevent background scroll when open
  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => {
      document.body.style.overflow = '';
    };
  }, [isOpen]);

  // Keyboard navigation & Shortcuts:
  // Esc: dismiss (checks changes)
  // Ctrl/Cmd + Enter: save
  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        handleRequestClose();
      } else if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
        e.preventDefault();
        handleSave();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, hasChanges, entity, taskTitle, taskDuration, taskStart, taskAssignee, taskStatus, taskNotes, taskNeedsInfoReason, tlDate, tlStartTime, agentName, agentKind, agentColor, agentCapacity]);

  if (!isOpen || !entity) return null;

  const isLocked = entity.type === 'task' 
    ? entity.timelineStatus === 'published'
    : entity.type === 'timeline' 
    ? entity.timeline.status === 'published'
    : false;

  const isBacklogTask = entity.type === 'task' && !entity.task.timelineId;

  // Track changes for Agent
  const handleAgentFieldChange = (field: string, value: any) => {
    if (entity.type !== 'agent') return;
    setHasChanges(true);
    setShowDiscardConfirm(false);
    if (field === 'name') setAgentName(value);
    if (field === 'kind') setAgentKind(value);
    if (field === 'color') setAgentColor(value);
    if (field === 'capacity') setAgentCapacity(Number(value) || 8);
    if (field === 'modelId') setAgentModelId(value);
    if (field === 'userId') {
      setAgentUserId(value);
      // Picking the person names the agent. Before this, adding a colleague
      // to a plan meant choosing them from this dropdown AND separately
      // inventing a name for them — two steps for one fact, and the invented
      // name is what the whole plan then showed instead of the person.
      //
      // Only fills a name the admin has not written themselves: an empty box,
      // or one still holding the previously picked person's name. Anything
      // typed by hand ("Tony — nights") survives the switch, because a plan
      // that needs the same person twice needs to tell them apart.
      const picked = teamMembers.find((m) => String(m.id) === String(value));
      const previous = teamMembers.find((m) => String(m.id) === String(agentUserId));
      const nameIsOurs = agentName.trim() === '' || (previous != null && agentName.trim() === previous.name.trim());
      if (picked && nameIsOurs) setAgentName(picked.name);
    }
  };

  // Track changes for Task
  const handleTaskFieldChange = (field: string, value: string) => {
    if (entity.type !== 'task') return;
    const original = entity.task;

    let nextTitle = taskTitle;
    let nextStart = taskStart;
    let nextDuration = taskDuration;
    let nextAssignee = taskAssignee;
    let nextStatus = taskStatus;
    let nextNotes = taskNotes;
    let nextReason = taskNeedsInfoReason;

    if (field === 'title') { nextTitle = value; setTaskTitle(value); }
    if (field === 'start') { nextStart = value; setTaskStart(value); }
    if (field === 'duration') { nextDuration = value; setTaskDuration(value); }
    if (field === 'assignee') { nextAssignee = value; setTaskAssignee(value); }
    if (field === 'status') { nextStatus = value as TaskPlanningStatus; setTaskStatus(nextStatus); }
    if (field === 'notes') { nextNotes = value; setTaskNotes(value); }
    if (field === 'needsInfoReason') { nextReason = value; setTaskNeedsInfoReason(value); }

    const changed = 
      nextTitle !== original.title ||
      nextStart !== (original.planned_start || '') ||
      nextDuration !== (original.duration?.toString() || '30') ||
      nextAssignee !== (original.assignee || '') ||
      nextStatus !== original.status ||
      nextNotes !== (original.notes || '') ||
      nextReason !== (original.needsInfoReason || '');

    setHasChanges(changed);
    setShowDiscardConfirm(false);
  };

  // Track changes for Timeline
  const handleTimelineFieldChange = (field: string, value: string) => {
    if (entity.type !== 'timeline') return;
    const original = entity.timeline;

    let nextDate = tlDate;
    let nextStartTime = tlStartTime;

    if (field === 'date') { nextDate = value; setTlDate(value); }
    if (field === 'startTime') { nextStartTime = value; setTlStartTime(value); }

    const changed = 
      nextDate !== original.plannedDate ||
      nextStartTime !== (original.startTime || '08:00');

    setHasChanges(changed);
    setShowDiscardConfirm(false);
  };

  // Dismiss request (Cancel, Esc, Scrim, ×)
  const handleRequestClose = () => {
    if (isLocked || !hasChanges) {
      onClose();
    } else {
      setShowDiscardConfirm(true);
    }
  };

  const handleConfirmDiscard = () => {
    setShowDiscardConfirm(false);
    onClose();
  };

  // Validate & Save
  const handleSave = async () => {
    if (isLocked) {
      onClose();
      return;
    }

    const newErrors: Record<string, string> = {};

    if (entity.type === 'agent') {
      // A PERSON IS IDENTIFIED BY WHO THEY ARE, NOT BY A NAME SOMEBODY TYPES.
      // Writing "Tony" in a box and then separately choosing Tony from a list
      // is two statements of one fact, and the typed one is what the plan
      // then displays — so a typo silently renames a colleague for everyone.
      // The person picker is the required field now; the name comes from the
      // user record. An AI agent still needs a typed name: there is no user
      // record to take one from.
      const pickedMember = teamMembers.find((m) => String(m.id) === String(agentUserId));
      const resolvedName = agentKind === 'person'
        ? (pickedMember?.name?.trim() || agentName.trim())
        : agentName.trim();

      // 🔴 REQUIRED WHEN CREATING, NOT WHEN EDITING. 13 of the 20
      // person-agents that exist today have no login behind them (counted
      // live, 2026-10-22) and they sit in real plans. Requiring a pick on
      // every save would refuse an ordinary edit to any of them — a rename,
      // a capacity change — until somebody is linked, which is the exact
      // failure USR-3 is written to avoid: enforce on what is being SET, not
      // on the row being touched. A new row has nothing to break.
      const isNewAgent = entity.isNew || !entity.agent?.name;
      if (agentKind === 'person' && !pickedMember && isNewAgent) {
        newErrors.userId = 'Choose who does this work.';
      }
      if (agentKind === 'ai' && !agentName.trim()) {
        newErrors.name = 'Agent name is required.';
      }
      // A person whose user record has a blank name would otherwise save an
      // empty agent name, which the backend requires and which would read as
      // a nameless row on the board.
      if (agentKind === 'person' && pickedMember && resolvedName === '') {
        newErrors.userId = 'That person has no name on their account yet. Fix it on Manage users first.';
      }
      if (Object.keys(newErrors).length > 0) {
        setErrors(newErrors);
        return;
      }
      setIsSaving(true);
      const result = await onSaveAgent?.(entity.agent?.id || null, {
        name: resolvedName,
        kind: agentKind,
        color: agentColor,
        dailyCapacityHours: agentCapacity,
        modelId: agentKind === 'ai' ? (agentModelId || undefined) : undefined,
        // An AI agent has no login to perform as, by definition.
        userId: agentKind === 'person' ? agentUserId : '',
      });
      setIsSaving(false);
      if (result !== false) onClose();
      return;
    }

    if (entity.type === 'task') {
      if (!taskTitle.trim()) {
        newErrors.title = 'Task title is required.';
      }

      const durNum = parseInt(taskDuration, 10);
      if (isNaN(durNum) || durNum <= 0) {
        newErrors.duration = 'Duration must be a positive whole number.';
      }

      if (Object.keys(newErrors).length > 0) {
        setErrors(newErrors);
        return;
      }

      // Commit task
      setIsSaving(true);
      const result = await onSaveTask(entity.task.id, {
        title: taskTitle.trim(),
        planned_start: isBacklogTask ? '' : taskStart.trim(),
        duration: durNum,
        assignee: taskAssignee.trim(),
        status: isBacklogTask ? 'planned' : taskStatus,
        notes: taskNotes.trim(),
        needsInfoReason: taskStatus === 'needs_info' ? (taskNeedsInfoReason.trim() || 'Missing required information') : undefined,
      });
      setIsSaving(false);
      if (result !== false) onClose();
    } else if (entity.type === 'timeline') {
      // Timeline validation
      if (!tlDate) {
        newErrors.date = 'Planned date is required.';
      }
      if (!tlStartTime) {
        newErrors.startTime = 'Start time is required.';
      }

      if (Object.keys(newErrors).length > 0) {
        setErrors(newErrors);
        return;
      }

      setIsSaving(true);
      const result = await onSaveTimeline(entity.timeline.id, {
        plannedDate: tlDate,
        startTime: tlStartTime,
      });
      setIsSaving(false);
      if (result !== false) onClose();
    }
  };

  // ══════════════════════════════════════════════════════════════════════
  // SINGLE-TIMELINE PUBLISH CONFIRMATION (Story G1)
  // Publish triggers real downstream execution, so a one-sentence
  // confirmation naming the destination agent always interposes here.
  // ══════════════════════════════════════════════════════════════════════
  if (entity.type === 'publish_confirm') {
    const handleConfirm = () => {
      onConfirmPublish?.(entity.timeline.id);
      onClose();
    };

    return (
      <div
        id="publish-confirm-modal-overlay"
        className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4 animate-in fade-in duration-100"
        onClick={onClose}
      >
        <div
          id="publish-confirm-modal"
          ref={modalRef}
          className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-sm flex flex-col overflow-hidden animate-in zoom-in-95 duration-100"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="h-14 px-6 border-b border-neutral-200 flex items-center gap-2 bg-neutral-50 shrink-0">
            <Send className="w-4 h-4 text-neutral-900" />
            <h2 className="text-sm font-bold text-neutral-900">Publish Timeline?</h2>
          </div>

          <div className="p-6 flex flex-col gap-3">
            <p className="text-sm text-neutral-800">
              Publishing sends this plan to <strong>{entity.agentName}</strong> for execution.
            </p>
            {!entity.agentHasLogin && (
              <p id="publish-no-login-warning" className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-md px-3 py-2 flex items-start gap-1.5">
                <AlertTriangle className="w-3.5 h-3.5 mt-0.5 shrink-0" />
                <span>
                  <strong>{entity.agentName}</strong> has no login linked, so nobody will see this day in
                  Execution. Link one on the agent first, or publish anyway and link it later.
                </span>
              </p>
            )}
          </div>

          <div className="h-14 px-6 border-t border-neutral-200 flex items-center justify-end gap-3 bg-neutral-50 shrink-0">
            <button
              type="button"
              onClick={onClose}
              className="px-3.5 py-1.5 text-xs text-neutral-600 hover:text-neutral-900 font-medium rounded hover:bg-neutral-200/50"
            >
              Cancel
            </button>
            <button
              id="confirm-publish-btn"
              type="button"
              onClick={handleConfirm}
              className="px-4 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800 transition-colors shadow-xs"
            >
              Publish
            </button>
          </div>
        </div>
      </div>
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // BULK PUBLISH DAY CONFIRMATION (§7)
  // ══════════════════════════════════════════════════════════════════════
  if (entity.type === 'bulk_publish_day') {
    const readyItems = entity.outcomes.filter(o => o.status === 'ready');
    const totalCount = entity.outcomes.length;
    const readyCount = readyItems.length;

    const handleConfirmBulk = () => {
      const readyIds = readyItems.map(i => i.timeline.id);
      onConfirmBulkPublish?.(readyIds);
      onClose();
    };

    return (
      <div 
        id="bulk-publish-modal-overlay" 
        className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4 animate-in fade-in duration-100"
        onClick={onClose}
      >
        <div 
          id="bulk-publish-modal"
          ref={modalRef}
          className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-md flex flex-col overflow-hidden animate-in zoom-in-95 duration-100"
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <div className="h-14 px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
            <div className="flex items-center gap-2">
              <Send className="w-4 h-4 text-neutral-900" />
              <h2 className="text-sm font-bold text-neutral-900">
                Publish Day — {formatShortDate(entity.date)}
              </h2>
            </div>
            <button
              type="button"
              onClick={onClose}
              className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50"
            >
              <X className="w-4 h-4" />
            </button>
          </div>

          {/* Body */}
          <div className="p-6 flex flex-col gap-4">
            <div className="bg-neutral-100/80 p-3 rounded-md border border-neutral-200 text-xs text-neutral-700">
              <p className="font-semibold text-neutral-900 mb-1">
                {readyCount} of {totalCount} timelines will publish.
              </p>
              <p className="text-neutral-500 text-[11px]">
                Blocked timelines are skipped and remain in draft. Published timelines become read-only.
              </p>
            </div>

            {/* List breakdown (§7) */}
            <div className="divide-y divide-neutral-100 border border-neutral-200 rounded-md overflow-hidden max-h-60 overflow-y-auto">
              {entity.outcomes.map(outcome => (
                <div key={outcome.timeline.id} className="p-2.5 flex items-start justify-between gap-3 text-xs bg-white">
                  <div className="flex items-center gap-2 min-w-0">
                    {outcome.agent && (
                      <div 
                        className="w-2.5 h-2.5 rounded-xs shrink-0" 
                        style={{ backgroundColor: outcome.agent.color }} 
                      />
                    )}
                    <span className="font-semibold text-neutral-900 truncate">
                      {outcome.agent?.name || outcome.timeline.name}
                    </span>
                  </div>

                  <div className="shrink-0 text-right">
                    {outcome.status === 'ready' && (
                      <span className="inline-flex items-center gap-1 text-emerald-700 font-medium text-[11px]">
                        <CheckCircle2 className="w-3 h-3 text-emerald-600" />
                        <span>Ready ({outcome.taskCount} tasks)</span>
                      </span>
                    )}
                    {outcome.status === 'blocked' && (
                      <span className="inline-flex items-center gap-1 text-red-700 font-medium text-[11px]" title={outcome.reason}>
                        <AlertCircle className="w-3 h-3 text-red-600" />
                        <span>Blocked: {outcome.reason || 'Needs info'}</span>
                      </span>
                    )}
                    {outcome.status === 'already_published' && (
                      <span className="inline-flex items-center gap-1 text-neutral-500 text-[11px]">
                        <Lock className="w-3 h-3 text-neutral-400" />
                        <span>Already published</span>
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Footer */}
          <div className="h-14 px-6 border-t border-neutral-200 flex items-center justify-end gap-3 bg-neutral-50 shrink-0">
            <button
              type="button"
              onClick={onClose}
              className="px-3.5 py-1.5 text-xs text-neutral-600 hover:text-neutral-900 font-medium rounded hover:bg-neutral-200/50"
            >
              Cancel
            </button>
            <button
              id="confirm-bulk-publish-btn"
              type="button"
              onClick={handleConfirmBulk}
              disabled={readyCount === 0}
              className={`px-4 py-1.5 rounded-md text-xs font-semibold shadow-xs transition-all ${
                readyCount > 0
                  ? 'bg-neutral-900 text-white hover:bg-neutral-800 cursor-pointer'
                  : 'bg-neutral-200 text-neutral-400 cursor-not-allowed border border-neutral-300'
              }`}
            >
              {readyCount > 0 ? `Publish ${readyCount} Timelines` : 'Nothing to publish'}
            </button>
          </div>
        </div>
      </div>
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // AGENT FORM MODAL (§3)
  // ══════════════════════════════════════════════════════════════════════
  if (entity.type === 'agent') {
    return (
      <div 
        id="edit-agent-modal-overlay"
        className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4 animate-in fade-in duration-100"
        onClick={handleRequestClose}
      >
        <div 
          id="edit-agent-modal"
          ref={modalRef}
          className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-md flex flex-col overflow-hidden animate-in zoom-in-95 duration-100"
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <div className="h-14 px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
            <h2 className="text-sm font-bold text-neutral-900">
              {/* `entity.agent?.name` is undefined for a row that does not
                  exist yet, and the header read "Edit Agent — undefined" on
                  screen. Fall back on the name rather than on the flag, so it
                  is right whether or not `isNew` was set. */}
              {entity.isNew || !entity.agent?.name
                ? 'Add Agent to Roster'
                : `Edit Agent — ${entity.agent.name}`}
            </h2>
            <button
              type="button"
              onClick={handleRequestClose}
              className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50"
            >
              <X className="w-4 h-4" />
            </button>
          </div>

          {/* Form */}
          <div className="p-6 flex flex-col gap-4">
            {/* NAME — AI AGENTS ONLY.
                A person's name comes from their user record, because that is
                where it already lives and where Manage users keeps it
                correct. Typing "Tony" and then picking Tony from a list below
                is the same fact twice, and the typed copy is the one the
                board shows — so it can drift from the person it names, with
                nothing to notice. An AI agent has no user record, so it still
                names itself here. */}
            {agentKind === 'ai' && (
            <div>
              <label className="block text-xs font-semibold text-neutral-700 mb-1">
                Agent Name <span className="text-red-500">*</span>
              </label>
              <input
                ref={initialFocusRef}
                type="text"
                value={agentName}
                onChange={(e) => handleAgentFieldChange('name', e.target.value)}
                placeholder="e.g. Jordan Miller or Dispatch Bot"
                className={`w-full text-xs px-3 py-2 border rounded-md focus:outline-none ${
                  errors.name ? 'border-red-500 bg-red-50/20' : 'border-neutral-200 focus:border-neutral-900'
                }`}
              />
              {errors.name && (
                <p className="text-[11px] text-red-600 mt-1">{errors.name}</p>
              )}
            </div>
            )}

            {/* Kind (Person vs AI) */}
            <div>
              <label className="block text-xs font-semibold text-neutral-700 mb-1">
                Agent Kind
              </label>
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => handleAgentFieldChange('kind', 'person')}
                  className={`p-2 rounded-md border text-xs font-medium flex items-center justify-center gap-2 transition-all ${
                    agentKind === 'person'
                      ? 'border-neutral-900 bg-neutral-900 text-white shadow-2xs'
                      : 'border-neutral-200 bg-neutral-50 text-neutral-700 hover:bg-neutral-100'
                  }`}
                >
                  <User className="w-3.5 h-3.5" />
                  <span>Person (User ●)</span>
                </button>
                <button
                  type="button"
                  onClick={() => handleAgentFieldChange('kind', 'ai')}
                  className={`p-2 rounded-md border text-xs font-medium flex items-center justify-center gap-2 transition-all ${
                    agentKind === 'ai'
                      ? 'border-purple-900 bg-purple-900 text-white shadow-2xs'
                      : 'border-neutral-200 bg-neutral-50 text-neutral-700 hover:bg-neutral-100'
                  }`}
                >
                  <span className="text-xs">◆</span>
                  <span>Automated AI Agent</span>
                </button>
              </div>
            </div>

            {/* GAP-FIX W2 — "Who does this work?" Without a login behind
                a person, their published day reaches nobody: the
                performer app finds "my agents" by this exact field.
                The warning is shown rather than the save blocked —
                planning ahead of a hire is legitimate, planning into
                silence without being told is not. */}
            {agentKind === 'person' && (
              <div>
                <label className="block text-xs font-semibold text-neutral-700 mb-1">
                  Who does this work? <span className="text-red-500">*</span>
                </label>
                {teamError ? (
                  <p className="text-[11px] text-amber-700">
                    Couldn't load this account's logins. You can still save; link the login later.
                  </p>
                ) : (
                  <select
                    id="agent-user-select"
                    value={agentUserId}
                    onChange={(e) => handleAgentFieldChange('userId', e.target.value)}
                    className="w-full text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 bg-white"
                  >
                    <option value="">Choose someone…</option>
                    {teamMembers.map((m) => (
                      <option key={m.id} value={String(m.id)}>
                        {m.name} ({m.email})
                      </option>
                    ))}
                  </select>
                )}
                {errors.userId && (
                  <p className="text-[11px] text-red-600 mt-1">{errors.userId}</p>
                )}
                {/* Still a warning and not a blocked save when the list is
                    unreachable — planning ahead of a hire is legitimate.
                    What changed is that an EMPTY pick is now an error rather
                    than a shrug: a person-agent with nobody behind it reaches
                    nobody in Execution, which is the failure this whole
                    screen exists to prevent. */}
                {!teamError && agentUserId === '' && !errors.userId && (
                  <p id="agent-no-login-warning" className="text-[11px] text-amber-700 mt-1 flex items-start gap-1">
                    <AlertTriangle className="w-3 h-3 mt-0.5 shrink-0" />
                    Their name and their day in Execution both come from this.
                  </p>
                )}
              </div>
            )}

            {/* Model assignment — AI agents only; drives token-based cost */}
            {agentKind === 'ai' && (
              <div>
                <label className="block text-xs font-semibold text-neutral-700 mb-1">
                  Model
                </label>
                <select
                  id="agent-model-select"
                  value={agentModelId}
                  onChange={(e) => handleAgentFieldChange('modelId', e.target.value)}
                  className="w-full text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 bg-white"
                >
                  <option value="">No model assigned (not costed)</option>
                  {settings.models.map(m => (
                    <option key={m.id} value={m.id}>
                      {m.label} — {settings.currencySymbol}{m.inputPer1M}/{settings.currencySymbol}{m.outputPer1M} per 1M in/out
                    </option>
                  ))}
                </select>
                <p className="text-[10px] text-neutral-400 mt-1">
                  Token rates and throughput assumptions are set in Settings.
                </p>
              </div>
            )}

            {/* Daily Capacity */}
            <div>
              <label className="block text-xs font-semibold text-neutral-700 mb-1">
                Daily Capacity (Hours)
              </label>
              <div className="flex items-center gap-2">
                <input
                  type="number"
                  min={1}
                  max={24}
                  value={agentCapacity}
                  onChange={(e) => handleAgentFieldChange('capacity', e.target.value)}
                  className="w-24 text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono"
                />
                <span className="text-xs text-neutral-500">hours/day (planning threshold)</span>
              </div>
            </div>

            {/* Identity Color Swatch Selection (§8) */}
            <div>
              <label className="block text-xs font-semibold text-neutral-700 mb-1">
                Identity Color Swatch (Categorical Preset)
              </label>
              <p className="text-[11px] text-neutral-400 mb-2">
                Used only for small identity swatches and thin cell edges.
              </p>
              <div className="flex items-center gap-2 flex-wrap">
                {AGENT_PALETTE.map((p) => {
                  const isSelected = agentColor.toLowerCase() === p.hex.toLowerCase();
                  return (
                    <button
                      key={p.hex}
                      type="button"
                      onClick={() => handleAgentFieldChange('color', p.hex)}
                      className={`w-7 h-7 rounded-md flex items-center justify-center transition-all ${
                        isSelected ? 'ring-2 ring-neutral-900 ring-offset-2 scale-110 shadow-xs' : 'hover:scale-105'
                      }`}
                      style={{ backgroundColor: p.hex }}
                      title={`${p.name} (${p.hex})`}
                    >
                      {isSelected && <CheckCircle2 className="w-4 h-4 text-white drop-shadow-xs" />}
                    </button>
                  );
                })}
              </div>
            </div>
          </div>

          {/* Footer */}
          <div className="h-14 px-6 border-t border-neutral-200 flex items-center justify-end gap-3 bg-neutral-50 shrink-0">
            {!entity.isNew && entity.agent && onDeleteAgent && (
              <div className="mr-auto flex items-center gap-2">
                {confirmRemoveAgent ? (
                  <>
                    <span className="text-xs text-red-700">Tasks return to backlog.</span>
                    <button
                      id="confirm-remove-agent-btn"
                      type="button"
                      onClick={() => onDeleteAgent(entity.agent!.id)}
                      className="px-3 py-1.5 text-xs font-semibold text-white bg-red-600 hover:bg-red-700 rounded"
                    >
                      Confirm remove
                    </button>
                    <button
                      type="button"
                      onClick={() => setConfirmRemoveAgent(false)}
                      className="px-2 py-1.5 text-xs text-neutral-600 hover:text-neutral-900"
                    >
                      Keep
                    </button>
                  </>
                ) : (
                  <button
                    id="remove-agent-btn"
                    type="button"
                    onClick={() => setConfirmRemoveAgent(true)}
                    className="px-3 py-1.5 text-xs font-medium text-red-600 hover:text-red-700 hover:bg-red-50 rounded"
                  >
                    Remove agent
                  </button>
                )}
              </div>
            )}
            <button
              type="button"
              onClick={handleRequestClose}
              className="px-3.5 py-1.5 text-xs text-neutral-600 hover:text-neutral-900 font-medium rounded hover:bg-neutral-200/50"
            >
              Cancel
            </button>
            <button
              id="save-agent-btn"
              type="button"
              onClick={handleSave}
              disabled={isSaving}
              className="px-4 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800 transition-colors shadow-xs disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {isSaving ? 'Saving…' : entity.isNew ? 'Add Agent' : 'Save Changes'}
            </button>
          </div>
        </div>
      </div>
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // STANDARD TASK & TIMELINE FORM (Unchanged behavior)
  // ══════════════════════════════════════════════════════════════════════
  return (
    <div 
      id="edit-modal-overlay"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4 animate-in fade-in duration-100"
      onClick={handleRequestClose}
    >
      <div 
        id="edit-modal-dialog"
        ref={modalRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="modal-title"
        className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-lg flex flex-col max-h-[90vh] overflow-hidden animate-in zoom-in-95 duration-100"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Modal Header */}
        <div className="h-14 px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
          <div className="flex items-center gap-2">
            <h2 id="modal-title" className="text-sm font-bold text-neutral-900">
              {entity.type === 'task' 
                ? (isBacklogTask ? 'Edit Backlog Task' : `Edit Step #${entity.task.seq}`)
                : `Edit Timeline — ${entity.timeline.name}`
              }
            </h2>
            {isLocked && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-medium text-neutral-600 bg-neutral-200 rounded">
                <Lock className="w-3 h-3" />
                <span>Published (Read-only)</span>
              </span>
            )}
          </div>
          <button
            id="modal-close-x-btn"
            type="button"
            onClick={handleRequestClose}
            className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50 transition-colors"
            aria-label="Close dialog"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Modal Body */}
        <div className="p-6 overflow-y-auto flex-1 flex flex-col gap-4">
          {entity.type === 'task' ? (
            <>
              {/* GAP-FIX W1 — provenance for a slot that is a job step.
                  Its text is READ from the job's pinned map version, not
                  stored here, so the planner needs to know that before
                  they treat this like a free-text task: typing over the
                  title makes a local copy that no longer tracks the map,
                  which is the "reference, do not copy" rule breaking in
                  the one place it is easiest to break it. */}
              {entity.task.workTaskId && (
                <div className="rounded-md border border-indigo-200 bg-indigo-50 px-3 py-2 text-[11px] text-indigo-900">
                  <p className="font-semibold">Step of "{entity.task.jobTitle ?? 'a job'}"</p>
                  <p className="mt-0.5">
                    The wording comes from that job's published map version. Changing the title here only renames this
                    slot — it doesn't change the map, and the person doing the work still sees the map's own
                    instructions.
                  </p>
                  {entity.task.jobDoneWhen && <p className="mt-1">Done when: {entity.task.jobDoneWhen}</p>}
                </div>
              )}

              {/* Title */}
              <div>
                <label className="block text-xs font-semibold text-neutral-700 mb-1">
                  Task Title <span className="text-red-500">*</span>
                </label>
                <input
                  ref={initialFocusRef}
                  type="text"
                  disabled={isLocked}
                  value={taskTitle}
                  onChange={(e) => handleTaskFieldChange('title', e.target.value)}
                  className={`w-full text-xs px-3 py-2 border rounded-md focus:outline-none ${
                    errors.title ? 'border-red-500 bg-red-50/20' : 'border-neutral-200 focus:border-neutral-900'
                  }`}
                />
                {errors.title && (
                  <p className="text-[11px] text-red-600 mt-1">{errors.title}</p>
                )}
              </div>

              {/* Start Time & Duration */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-neutral-700 mb-1">
                    Planned Start
                  </label>
                  <input
                    type="time"
                    disabled
                    readOnly
                    value={taskStart}
                    className="w-full text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100 disabled:text-neutral-400 font-mono"
                  />
                  <p className="text-[10px] text-neutral-400 mt-1">
                    {isBacklogTask
                      ? 'Start time is assigned upon landing on a timeline.'
                      : "Computed automatically from the timeline's start time and step order."}
                  </p>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-neutral-700 mb-1">
                    Duration (Minutes) <span className="text-red-500">*</span>
                  </label>
                  <input
                    type="number"
                    min={5}
                    step={5}
                    disabled={isLocked}
                    value={taskDuration}
                    onChange={(e) => handleTaskFieldChange('duration', e.target.value)}
                    className="w-full text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100 font-mono"
                  />
                </div>
              </div>

              {/* Assignee */}
              <div>
                <label className="block text-xs font-semibold text-neutral-700 mb-1">
                  Assignee
                </label>
                <input
                  type="text"
                  disabled={isLocked}
                  value={taskAssignee}
                  onChange={(e) => handleTaskFieldChange('assignee', e.target.value)}
                  placeholder="Inherits timeline assignee if blank"
                  className="w-full text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100"
                />
              </div>

              {/* Status */}
              {!isBacklogTask && (
                <div>
                  <label className="block text-xs font-semibold text-neutral-700 mb-1">
                    Readiness Status
                  </label>
                  <div className="flex items-center gap-4">
                    <label className="flex items-center gap-1.5 text-xs text-neutral-700">
                      <input
                        type="radio"
                        name="task-status"
                        disabled={isLocked}
                        value="planned"
                        checked={taskStatus === 'planned'}
                        onChange={() => handleTaskFieldChange('status', 'planned')}
                      />
                      <span>Planned (Ready)</span>
                    </label>
                    <label className="flex items-center gap-1.5 text-xs text-neutral-700">
                      <input
                        type="radio"
                        name="task-status"
                        disabled={isLocked}
                        value="needs_info"
                        checked={taskStatus === 'needs_info'}
                        onChange={() => handleTaskFieldChange('status', 'needs_info')}
                      />
                      <span className="text-red-700 font-medium">Needs Info (Blocked)</span>
                    </label>
                  </div>

                  {taskStatus === 'needs_info' && (
                    <div className="mt-2">
                      <label className="block text-[11px] font-semibold text-red-700 mb-1">
                        Reason for Needs Info:
                      </label>
                      <input
                        type="text"
                        disabled={isLocked}
                        value={taskNeedsInfoReason}
                        onChange={(e) => handleTaskFieldChange('needsInfoReason', e.target.value)}
                        placeholder="e.g. Missing technical brief, overlaps step below, etc."
                        className="w-full text-xs px-3 py-1.5 border border-red-300 rounded focus:outline-none focus:border-red-500 bg-red-50/20"
                      />
                    </div>
                  )}
                </div>
              )}

              {/* Notes */}
              <div>
                <label className="block text-xs font-semibold text-neutral-700 mb-1">
                  Notes
                </label>
                <textarea
                  rows={3}
                  disabled={isLocked}
                  value={taskNotes}
                  onChange={(e) => handleTaskFieldChange('notes', e.target.value)}
                  placeholder="Detailed instructions or prerequisites..."
                  className="w-full text-xs p-3 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100"
                />
              </div>
            </>
          ) : (
            <>
              {/* Planned Date */}
              <div>
                <label className="block text-xs font-semibold text-neutral-700 mb-1">
                  Planned Date <span className="text-red-500">*</span>
                </label>
                <input
                  ref={initialFocusRef}
                  type="date"
                  disabled={isLocked}
                  value={tlDate}
                  onChange={(e) => handleTimelineFieldChange('date', e.target.value)}
                  className="w-full text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100 font-mono"
                />
              </div>

              {/* Start Time - anchors the cascade; every step's start is computed from this */}
              <div>
                <label className="block text-xs font-semibold text-neutral-700 mb-1">
                  Start Time <span className="text-red-500">*</span>
                </label>
                <input
                  type="time"
                  disabled={isLocked}
                  value={tlStartTime}
                  onChange={(e) => handleTimelineFieldChange('startTime', e.target.value)}
                  className="w-full text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100 font-mono"
                />
                <p className="mt-1 text-[11px] text-neutral-400">
                  All steps in this timeline are scheduled back-to-back starting from this time.
                </p>
              </div>
            </>
          )}
        </div>

        {/* Footer */}
        <div className="h-14 px-6 border-t border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
          {isLocked ? (
            <div className="w-full flex justify-end">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-medium hover:bg-neutral-800"
              >
                Close
              </button>
            </div>
          ) : showDiscardConfirm ? (
            <div className="w-full flex items-center justify-between">
              <span className="text-xs font-semibold text-red-700">Discard your changes?</span>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setShowDiscardConfirm(false)}
                  className="px-3 py-1.5 text-xs text-neutral-700 hover:text-neutral-900 font-medium"
                >
                  Keep editing
                </button>
                <button
                  type="button"
                  onClick={handleConfirmDiscard}
                  className="px-3.5 py-1.5 text-xs bg-red-600 hover:bg-red-700 text-white font-medium rounded-md shadow-xs"
                >
                  Discard
                </button>
              </div>
            </div>
          ) : (
            <div className="w-full flex items-center justify-end gap-3">
              {/* PLN-6 (US-PLN-6-05): delete this day. Not offered for a
                  published one — the server refuses it (E-P3A-003) and
                  showing the control would only invite that refusal. */}
              {entity.type === 'timeline' && onDeleteTimeline && !isLocked && (
                <div className="mr-auto flex items-center gap-2">
                  {confirmDeleteTimeline ? (
                    <>
                      <span className="text-xs text-red-700">Tasks return to backlog.</span>
                      <button
                        id="confirm-delete-timeline-btn"
                        type="button"
                        onClick={() => onDeleteTimeline(entity.timeline.id)}
                        className="px-3 py-1.5 text-xs font-semibold text-white bg-red-600 hover:bg-red-700 rounded"
                      >
                        Confirm delete
                      </button>
                      <button
                        type="button"
                        onClick={() => setConfirmDeleteTimeline(false)}
                        className="px-2 py-1.5 text-xs text-neutral-600 hover:text-neutral-900"
                      >
                        Keep
                      </button>
                    </>
                  ) : (
                    <button
                      id="delete-timeline-btn"
                      type="button"
                      onClick={() => setConfirmDeleteTimeline(true)}
                      className="px-3 py-1.5 text-xs font-medium text-red-600 hover:text-red-700 hover:bg-red-50 rounded"
                    >
                      Delete this day
                    </button>
                  )}
                </div>
              )}
              <button
                type="button"
                onClick={handleRequestClose}
                className="px-3.5 py-1.5 text-xs text-neutral-600 hover:text-neutral-900 font-medium rounded hover:bg-neutral-200/50"
              >
                Cancel
              </button>
              <button
                id="modal-save-btn"
                type="button"
                onClick={handleSave}
                disabled={!hasChanges || isSaving}
                className={`px-4 py-1.5 rounded-md text-xs font-medium transition-all shadow-xs ${
                  hasChanges && !isSaving
                    ? 'bg-neutral-900 text-white hover:bg-neutral-800 cursor-pointer'
                    : 'bg-neutral-200 text-neutral-400 cursor-not-allowed border border-neutral-300'
                }`}
              >
                {isSaving ? 'Saving…' : hasChanges ? 'Save changes' : 'No changes'}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
