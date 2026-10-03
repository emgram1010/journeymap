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

interface EditModalProps {
  isOpen: boolean;
  entity: ModalEntity | null;
  onClose: () => void;
  onSaveTask: (taskId: string, updates: Partial<Task>) => void;
  onSaveTimeline: (timelineId: string, updates: Partial<Timeline>) => void;
  settings: AppSettings;
  onSaveAgent?: (agentId: string | null, updates: { name: string; kind: AgentKind; color: string; dailyCapacityHours: number; modelId?: string }) => void;
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
  onConfirmBulkPublish,
  onConfirmPublish,
  onReopenTimeline,
}: EditModalProps) {
  // Modal states
  const [showDiscardConfirm, setShowDiscardConfirm] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});

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

  // Trap focus ref
  const modalRef = useRef<HTMLDivElement>(null);
  const initialFocusRef = useRef<HTMLInputElement>(null);

  // Initialize data when entity changes
  useEffect(() => {
    if (!entity) return;

    setShowDiscardConfirm(false);
    setHasChanges(false);
    setErrors({});

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
      } else {
        setAgentName('');
        setAgentKind('person');
        setAgentColor(AGENT_PALETTE[0].hex);
        setAgentCapacity(8);
        setAgentModelId('');
      }
    }
  }, [entity]);

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
  const handleSave = () => {
    if (isLocked) {
      onClose();
      return;
    }

    const newErrors: Record<string, string> = {};

    if (entity.type === 'agent') {
      if (!agentName.trim()) {
        newErrors.name = 'Agent name is required.';
      }
      if (Object.keys(newErrors).length > 0) {
        setErrors(newErrors);
        return;
      }
      onSaveAgent?.(entity.agent?.id || null, {
        name: agentName.trim(),
        kind: agentKind,
        color: agentColor,
        dailyCapacityHours: agentCapacity,
        modelId: agentKind === 'ai' ? (agentModelId || undefined) : undefined,
      });
      onClose();
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
      onSaveTask(entity.task.id, {
        title: taskTitle.trim(),
        planned_start: isBacklogTask ? '' : taskStart.trim(),
        duration: durNum,
        assignee: taskAssignee.trim(),
        status: isBacklogTask ? 'planned' : taskStatus,
        notes: taskNotes.trim(),
        needsInfoReason: taskStatus === 'needs_info' ? (taskNeedsInfoReason.trim() || 'Missing required information') : undefined,
      });

      onClose();
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

      onSaveTimeline(entity.timeline.id, {
        plannedDate: tlDate,
        startTime: tlStartTime,
      });

      onClose();
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

          <div className="p-6">
            <p className="text-sm text-neutral-800">
              Publishing sends this plan to <strong>{entity.agentName}</strong> for execution.
            </p>
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
              {entity.isNew ? 'Add Agent to Roster' : `Edit Agent — ${entity.agent?.name}`}
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
            {/* Name */}
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
              className="px-4 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800 transition-colors shadow-xs"
            >
              {entity.isNew ? 'Add Agent' : 'Save Changes'}
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
                disabled={!hasChanges}
                className={`px-4 py-1.5 rounded-md text-xs font-medium transition-all shadow-xs ${
                  hasChanges
                    ? 'bg-neutral-900 text-white hover:bg-neutral-800 cursor-pointer'
                    : 'bg-neutral-200 text-neutral-400 cursor-not-allowed border border-neutral-300'
                }`}
              >
                {hasChanges ? 'Save changes' : 'No changes'}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
