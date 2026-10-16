import { useState, useEffect, useMemo, useCallback } from 'react';
import { Calendar, LayoutList, Hammer } from 'lucide-react';
import { Workspace, Timeline, Task, Agent, ViewMode, AppSettings } from './types';
import { DEFAULT_SETTINGS, DEFAULT_INPUT_TOKENS_PER_MINUTE, DEFAULT_OUTPUT_TOKENS_PER_MINUTE } from './data/initialData';
import {
  listWorkspaces, getBoard,
  createAgent, updateAgent, setWorkspaceAgentVisibility,
  createTimeline, updateTimeline, publishTimeline as publishTimelineApi, reorderTimeline,
  createTask, updateTask, placeTask,
  listTemplates, createWorkspaceFromTemplate, TemplateListEntry,
} from './lib/plannerApi';
import { adaptWorkspace, adaptBoard } from './lib/plannerAdapter';
import { ProductNav } from './components/ProductNav';
import { SettingsModal } from './components/SettingsModal';
import { WorkspaceSettingsModal } from './components/WorkspaceSettingsModal';
import { CreateWorkspaceModal } from './components/CreateWorkspaceModal';
import { Header } from './components/Header';
import { ScheduleGrid } from './components/ScheduleGrid';
import { DayBoard } from './components/DayBoard';
import { BacklogDrawer } from './components/BacklogDrawer';
import { EditModal, ModalEntity } from './components/EditModal';
import { ComponentSheetModal } from './components/ComponentSheetModal';
import { getTimelineReadiness, formatMinutesToTime, parseTimeToMinutes } from './utils/planningLogic';
import { formatShortDate, generateDaysList, getDaysDifference } from './utils/dateUtils';

export default function App() {
  const [dataLoaded, setDataLoaded] = useState(false);
  const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
  const [agents, setAgents] = useState<Agent[]>([]);
  const [timelines, setTimelines] = useState<Timeline[]>([]);
  const [tasks, setTasks] = useState<Task[]>([]);

  const [activeWorkspaceId, setActiveWorkspaceId] = useState<string>('');
  const [activeTimelineId, setActiveTimelineId] = useState<string | null>(null);

  // Agent-centric state
  const [activeDay, setActiveDay] = useState<string>('2026-10-13');
  const [activeAgentId, setActiveAgentId] = useState<string | null>(null);
  const [focusedAgentId, setFocusedAgentId] = useState<string | null>(null);

  // Edit Modal State (replaces right-hand inspector panel)
  const [activeModalEntity, setActiveModalEntity] = useState<ModalEntity | null>(null);
  const [acknowledgedTaskId, setAcknowledgedTaskId] = useState<string | null>(null);
  const [backlogPlacementConfirmation, setBacklogPlacementConfirmation] = useState<string | null>(null);

  // View mode ('plan' | 'schedule')
  const [viewMode, setViewMode] = useState<ViewMode>('plan');

  // Component Sheet Modal state
  const [isComponentSheetOpen, setIsComponentSheetOpen] = useState(false);

  // Workspace settings (cost rates + model pricing)
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_SETTINGS);
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [isWorkspaceSettingsOpen, setIsWorkspaceSettingsOpen] = useState(false);

  // Drag tracking state across components
  const [isDraggingTaskFromTimeline, setIsDraggingTaskFromTimeline] = useState(false);

  // PLN-9 (US-PLN-9-03/04/05): every mutation below hits the real
  // backend, then refetches the whole board rather than hand-patching
  // local state — the same call Checkpoint 1 already proved derives
  // planned_start correctly. This is a deliberate simplification over
  // the old localStorage version's in-memory recompute helpers
  // (`recomputeTimelineTaskTimes`, `calculateTaskLanding`): the server
  // is the single source of truth for sequencing, derived start times
  // and effective assignees (CLAUDE.md: "reference, do not copy"), so
  // duplicating that math client-side would just be a second place for
  // it to drift out of sync.
  const [actionError, setActionError] = useState<string | null>(null);
  const reportActionError = (err: unknown) => {
    setActionError(err instanceof Error ? err.message : 'Something went wrong — please try again.');
    setTimeout(() => setActionError(null), 6000);
  };

  // PLN-9 (US-PLN-9-02): real data, not localStorage. Two loads, same
  // shape the old `loadStoredData()` produced in one synchronous call —
  // this app never had a loading or error state before, because a
  // localStorage read cannot fail. Both are new here.
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isLoadingBoard, setIsLoadingBoard] = useState(false);

  // 1. Which plans does this account have? Picks the first as active,
  // same default behaviour as before.
  useEffect(() => {
    let cancelled = false;
    listWorkspaces()
      .then(({ workspaces: entries }) => {
        if (cancelled) return;
        const mapped = entries.map(adaptWorkspace);
        setWorkspaces(mapped);
        if (mapped.length > 0) setActiveWorkspaceId(mapped[0].id);
        else setDataLoaded(true); // nothing to load a board for
      })
      .catch((err) => {
        if (cancelled) return;
        setLoadError(err instanceof Error ? err.message : 'Could not load your plans.');
        setDataLoaded(true);
      });
    return () => { cancelled = true; };
  }, []);

  // 2. Everything in the active plan, one request (PLN-8's board
  // endpoint) — agents, every timeline, every task (scheduled and
  // backlog), settings, models. Re-runs whenever the active plan
  // changes, which is also how a refresh-after-mutation will work
  // later: refetch the board, don't hand-patch local state.
  const loadActiveBoard = useCallback((workspaceId: string) => {
    setIsLoadingBoard(true);
    setLoadError(null);
    return getBoard(Number(workspaceId))
      .then((board) => {
        const { agents: a, timelines: tl, tasks: tk, settings: s } = adaptBoard(board);
        setAgents(a);
        setTimelines(tl);
        setTasks(tk);
        setSettings(s);

        const firstTl = tl[0];
        if (firstTl) {
          setActiveTimelineId(firstTl.id);
          if (firstTl.plannedDate) setActiveDay(firstTl.plannedDate);
          if (firstTl.agentId) setActiveAgentId(firstTl.agentId);
        }
      })
      .catch((err) => {
        setLoadError(err instanceof Error ? err.message : 'Could not load this plan.');
      })
      .finally(() => {
        setIsLoadingBoard(false);
        setDataLoaded(true);
      });
  }, []);

  useEffect(() => {
    if (!activeWorkspaceId) return;
    void loadActiveBoard(activeWorkspaceId);
  }, [activeWorkspaceId, loadActiveBoard]);

  // Re-pull the active board after a write succeeds. Deliberately does
  // NOT reset `dataLoaded`/show the full-screen spinner again — only
  // the small "Loading…" pill (already wired to `isLoadingBoard`)
  // appears, so a save doesn't blank the screen the user is looking at.
  const refreshBoard = useCallback(() => {
    if (!activeWorkspaceId) return Promise.resolve();
    return loadActiveBoard(activeWorkspaceId);
  }, [activeWorkspaceId, loadActiveBoard]);

  // Derived current workspace & agents
  const activeWorkspace = useMemo(() => {
    return workspaces.find(ws => ws.id === activeWorkspaceId) || null;
  }, [workspaces, activeWorkspaceId]);

  const agentsInActiveWs = useMemo(() => {
    return agents.filter(a => a.workspaceId === activeWorkspaceId);
  }, [agents, activeWorkspaceId]);

  const timelinesInActiveWs = useMemo(() => {
    return timelines.filter(tl => tl.workspaceId === activeWorkspaceId);
  }, [timelines, activeWorkspaceId]);

  const activeTimeline = useMemo(() => {
    return timelines.find(tl => tl.id === activeTimelineId) || null;
  }, [timelines, activeTimelineId]);

  const tasksInActiveTimeline = useMemo(() => {
    if (!activeTimelineId) return [];
    return tasks
      .filter(t => t.timelineId === activeTimelineId)
      .sort((a, b) => a.seq - b.seq);
  }, [tasks, activeTimelineId]);

  const backlogTasksInActiveWs = useMemo(() => {
    return tasks.filter(t => t.workspaceId === activeWorkspaceId && !t.timelineId);
  }, [tasks, activeWorkspaceId]);

  // Active modal task id helper (highlighted row only while modal is open)
  const activeModalTaskId = activeModalEntity?.type === 'task' ? activeModalEntity.task.id : null;

  // Visible dates in planning window
  const visibleDates = useMemo(() => {
    const start = activeWorkspace?.planningWindowStart || '2026-10-12';
    const end = activeWorkspace?.planningWindowEnd || '2026-10-25';
    return generateDaysList(start, getDaysDifference(start, end));
  }, [activeWorkspace]);

  // The active workspace's throughput assumptions — the per-workspace half
  // of the cost inputs (rates are global).
  const activeThroughput = useMemo(() => ({
    inputTokensPerMinute: activeWorkspace?.inputTokensPerMinute ?? DEFAULT_INPUT_TOKENS_PER_MINUTE,
    outputTokensPerMinute: activeWorkspace?.outputTokensPerMinute ?? DEFAULT_OUTPUT_TOKENS_PER_MINUTE,
  }), [activeWorkspace]);

  // Handler: Update workspace-scoped settings (planning window + throughput)
  const handleUpdateWorkspaceSettings = (workspaceId: string, updates: Partial<Workspace>) => {
    setWorkspaces(prev => prev.map(ws => ws.id === workspaceId ? { ...ws, ...updates } : ws));
  };

  // Handler: Select Workspace
  const handleSelectWorkspace = (wsId: string) => {
    setActiveWorkspaceId(wsId);
    const firstTl = timelines.find(t => t.workspaceId === wsId);
    if (firstTl) {
      setActiveTimelineId(firstTl.id);
      if (firstTl.plannedDate) setActiveDay(firstTl.plannedDate);
      if (firstTl.agentId) setActiveAgentId(firstTl.agentId);
    } else {
      setActiveTimelineId(null);
      setActiveAgentId(null);
    }
  };

  // US-PLN-9-07: a real plan is created from a template (PLAN-1's
  // instance endpoint), not from a bare name — the template supplies
  // the window length, default start time and accepted maps. Creating
  // or editing a TEMPLATE is explicitly deferred by this epic's own
  // scope table; this app only ever starts a plan from one that
  // already exists.
  const [isCreateWorkspaceModalOpen, setIsCreateWorkspaceModalOpen] = useState(false);
  const [templates, setTemplates] = useState<TemplateListEntry[]>([]);
  const [isLoadingTemplates, setIsLoadingTemplates] = useState(false);

  const handleOpenCreateWorkspaceModal = () => {
    setIsCreateWorkspaceModalOpen(true);
    setIsLoadingTemplates(true);
    listTemplates()
      .then(({ templates: t }) => setTemplates(t))
      .catch(() => setTemplates([]))
      .finally(() => setIsLoadingTemplates(false));
  };

  const handleCreateWorkspaceFromTemplate = async (templateId: number, name: string, startDate: string): Promise<boolean> => {
    try {
      const { workspace } = await createWorkspaceFromTemplate(templateId, { name, start_date: startDate });
      const { workspaces: entries } = await listWorkspaces();
      setWorkspaces(entries.map(adaptWorkspace));
      setActiveTimelineId(null);
      setActiveWorkspaceId(String(workspace.id));
      return true;
    } catch (err) {
      reportActionError(err);
      return false;
    }
  };

  // Handler: Rename Workspace
  const handleRenameWorkspace = (id: string, newName: string) => {
    setWorkspaces(prev => prev.map(ws => ws.id === id ? { ...ws, name: newName } : ws));
  };

  // Handler: Delete Workspace
  const handleDeleteWorkspace = (id: string) => {
    const remaining = workspaces.filter(ws => ws.id !== id);
    setWorkspaces(remaining);
    setAgents(prev => prev.filter(a => a.workspaceId !== id));
    setTimelines(prev => prev.filter(t => t.workspaceId !== id));
    setTasks(prev => prev.filter(t => t.workspaceId !== id));

    if (remaining.length > 0) {
      handleSelectWorkspace(remaining[0].id);
    } else {
      setActiveWorkspaceId('');
      setActiveTimelineId(null);
    }
  };

  // Update Planning Window
  const handleUpdatePlanningWindow = (start: string, end: string) => {
    if (!activeWorkspaceId) return;
    setWorkspaces(prev => prev.map(ws => {
      if (ws.id === activeWorkspaceId) {
        return {
          ...ws,
          planningWindowStart: start,
          planningWindowEnd: end,
        };
      }
      return ws;
    }));
  };

  // Agent Roster handlers (US-PLN-9-03)
  const handleToggleAgentVisibility = (agentId: string) => {
    const agent = agents.find(a => a.id === agentId);
    if (!agent) return;
    updateAgent(Number(agentId), { is_visible: !agent.isVisible })
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  const handleShowAllAgents = () => {
    if (!activeWorkspaceId) return;
    setWorkspaceAgentVisibility(Number(activeWorkspaceId), true)
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // The backend's bulk endpoint is a plain "everyone visible/hidden" —
  // it has no notion of "except the one I'm looking at". This UI's own
  // "hide all" has always meant that exception, so it stays a
  // two-step client action: hide everyone, then show the one(s) the
  // user is actively focused on back.
  const handleHideAllAgents = () => {
    if (!activeWorkspaceId) return;
    const keepVisibleIds = new Set([activeAgentId, focusedAgentId].filter((id): id is string => !!id));
    setWorkspaceAgentVisibility(Number(activeWorkspaceId), false)
      .then(() => Promise.all([...keepVisibleIds].map(id => updateAgent(Number(id), { is_visible: true }))))
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  const handleOpenAddAgentModal = () => {
    setActiveModalEntity({
      type: 'agent',
      agent: null,
    });
  };

  const handleOpenEditAgentModal = (agentId: string) => {
    const agent = agents.find(a => a.id === agentId);
    if (!agent) return;
    setActiveModalEntity({
      type: 'agent',
      agent,
    });
  };

  // Returns `false` on a rejected save so EditModal keeps the form open
  // with the user's typing intact instead of closing as if it worked.
  const handleSaveAgent = async (
    agentId: string | null,
    updates: { name: string; kind: 'person' | 'ai'; color: string; dailyCapacityHours: number; modelId?: string }
  ): Promise<boolean> => {
    try {
      if (agentId) {
        await updateAgent(Number(agentId), {
          name: updates.name,
          kind: updates.kind,
          color: updates.color,
          daily_capacity_hours: updates.dailyCapacityHours,
          model_id: updates.kind === 'ai' && updates.modelId ? Number(updates.modelId) : 0,
        });
      } else {
        if (!activeWorkspaceId) return false;
        const { agent } = await createAgent(Number(activeWorkspaceId), {
          name: updates.name,
          kind: updates.kind,
          color: updates.color || undefined,
          daily_capacity_hours: updates.dailyCapacityHours,
          model_id: updates.kind === 'ai' && updates.modelId ? Number(updates.modelId) : undefined,
        });
        setActiveAgentId(String(agent.id));
      }
      await refreshBoard();
      return true;
    } catch (err) {
      reportActionError(err);
      return false;
    }
  };

  // PLN-9: deleting an agent (and a task, and a timeline) has no live
  // backend endpoint yet — `functions/planner/delete_agent_cascade.xs`
  // exists but is deliberately NOT pushed, per CLAUDE.md's "ask before
  // any delete." Rather than fake a delete that doesn't persist, this
  // action is left unavailable (onDeleteAgent simply isn't passed to
  // EditModal below) until the founder approves pushing it.

  // Open Task Edit Modal
  const handleOpenTaskEditModal = (taskId: string) => {
    const task = tasks.find(t => t.id === taskId);
    if (!task) return;

    if (task.timelineId) {
      const tl = timelines.find(t => t.id === task.timelineId) || null;
      const tlTasks = tasks
        .filter(t => t.timelineId === task.timelineId)
        .sort((a, b) => a.seq - b.seq);
      const taskIndex = tlTasks.findIndex(t => t.id === taskId);

      let prevTaskEnd: string | undefined = undefined;
      if (taskIndex > 0) {
        const prev = tlTasks[taskIndex - 1];
        if (prev.planned_start) {
          const prevStartM = parseTimeToMinutes(prev.planned_start);
          if (prevStartM !== null) {
            prevTaskEnd = formatMinutesToTime(prevStartM + prev.duration);
          }
        }
      }

      let nextTaskStart: string | undefined = undefined;
      if (taskIndex < tlTasks.length - 1) {
        const next = tlTasks[taskIndex + 1];
        if (next.planned_start) {
          nextTaskStart = next.planned_start;
        }
      }

      setActiveModalEntity({
        type: 'task',
        task,
        timeline: tl,
        totalTasksInTimeline: tlTasks.length,
        prevTaskEnd,
        nextTaskStart,
      });
    } else {
      setActiveModalEntity({
        type: 'task',
        task,
        timeline: null,
        totalTasksInTimeline: 0,
      });
    }
  };

  // Open Timeline Edit Modal
  const handleOpenTimelineEditModal = (timelineId?: string) => {
    const tlId = timelineId || activeTimelineId;
    if (!tlId) return;
    const tl = timelines.find(t => t.id === tlId);
    if (!tl) return;
    const tlTasks = tasks.filter(t => t.timelineId === tl.id).sort((a, b) => a.seq - b.seq);

    setActiveModalEntity({
      type: 'timeline',
      timeline: tl,
      tasksInTimeline: tlTasks,
      planningWindowStart: activeWorkspace?.planningWindowStart || '2026-10-12',
      planningWindowEnd: activeWorkspace?.planningWindowEnd || '2026-10-25',
    });
  };

  // Save Task from Modal — EditModal's own form only ever sends title,
  // duration, assignee, status, notes, needsInfoReason: never
  // timelineId/seq (moving a task is always `task/place`, never this).
  //
  // The assignee field is free text ("inherits timeline assignee if
  // blank"), but the backend only takes an `assignee_agent_id` int
  // override. Blank clears the override (0); a name that matches an
  // agent in this plan resolves to that override; anything else can't
  // be saved as a real override, so the save is refused client-side
  // rather than silently dropped.
  const handleSaveTaskFromModal = async (taskId: string, updates: Partial<Task>): Promise<boolean> => {
    const target = tasks.find(t => t.id === taskId);
    const nextAssignee = (updates.assignee ?? '').trim();
    let assigneeAgentId: number | undefined;
    if (nextAssignee !== (target?.assignee ?? '').trim()) {
      if (nextAssignee === '') {
        assigneeAgentId = 0;
      } else {
        const match = agentsInActiveWs.find(a => a.name === nextAssignee);
        if (!match) {
          reportActionError(new Error(`No one in this plan is named "${nextAssignee}" — pick an existing agent's name, or leave it blank to inherit the day's assignee.`));
          return false;
        }
        assigneeAgentId = Number(match.id);
      }
    }
    try {
      await updateTask(Number(taskId), {
        title: updates.title,
        duration_minutes: updates.duration,
        notes: updates.notes,
        status: updates.status,
        needs_info_reason: updates.needsInfoReason ?? '',
        ...(assigneeAgentId !== undefined ? { assignee_agent_id: assigneeAgentId } : {}),
      });
      await refreshBoard();
      setAcknowledgedTaskId(taskId);
      setTimeout(() => setAcknowledgedTaskId(null), 2500);
      return true;
    } catch (err) {
      reportActionError(err);
      return false;
    }
  };

  // Save Timeline from Modal — only start time and date are editable
  // here; moving to a different agent is the grid's own drag gesture
  // (handleMoveTimelineCell).
  const handleSaveTimelineFromModal = async (timelineId: string, updates: Partial<Timeline>): Promise<boolean> => {
    try {
      await updateTimeline(Number(timelineId), {
        start_time: updates.startTime,
        planned_date: updates.plannedDate,
      });
      await refreshBoard();
      return true;
    } catch (err) {
      reportActionError(err);
      return false;
    }
  };

  // Request confirmation before publishing a single timeline (Story G1).
  // Publish triggers real downstream execution, so this always interposes
  // a one-sentence confirmation naming the agent it goes to.
  const handleRequestPublishConfirm = (timelineId: string) => {
    const tl = timelines.find(t => t.id === timelineId);
    if (!tl) return;
    const agent = agents.find(a => a.id === tl.agentId);
    setActiveModalEntity({
      type: 'publish_confirm',
      timeline: tl,
      agentName: agent?.name || tl.assignee || 'the assigned agent',
    });
  };

  // Publish Timeline (LIVE-1). The server re-checks readiness itself and
  // returns every blocker at once (its own doc comment) — the client
  // check here is only to avoid an obviously-futile request.
  const handlePublishTimeline = (timelineId: string) => {
    const tl = timelines.find(t => t.id === timelineId);
    if (!tl) return;
    const tlTasks = tasks.filter(t => t.timelineId === tl.id);
    const readiness = getTimelineReadiness(tl, tlTasks, activeWorkspace);
    if (!readiness.ready) return;
    publishTimelineApi(Number(timelineId))
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // PLN-9: there is no "unpublish" on the backend (LIVE-1's own design —
  // once live, the planner keeps editing the SAME published day forward,
  // with every change logged rather than the day reverting to draft;
  // that logging is VAR-1/LOG-1 territory, out of this epic's scope).
  // The UI's "Reopen to edit" buttons stay in place but can't actually
  // revert anything yet, so this just says so instead of lying about it.
  const handleReopenTimeline = (_timelineId: string) => {
    reportActionError(new Error('Reopening a published day isn’t available yet — ask the founder.'));
  };

  // Reorder Tasks within Timeline (PLN-7: exact permutation of this
  // day's own task ids; the server refuses and writes nothing on a
  // partial or foreign id, so the client doesn't need to pre-check).
  const handleReorderTasks = (timelineId: string, reorderedTasks: Task[]) => {
    reorderTimeline(Number(timelineId), reorderedTasks.map(t => Number(t.id)))
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // Add Task directly into timeline
  const handleAddTaskToTimeline = (
    timelineId: string,
    title: string,
    _plannedStart: string,
    duration: number,
    assignee?: string
  ) => {
    if (!activeWorkspaceId || !timelineId) return;
    const agentOverride = assignee ? agentsInActiveWs.find(a => a.name === assignee) : undefined;
    createTask(Number(activeWorkspaceId), {
      title,
      duration_minutes: duration,
      timeline_id: Number(timelineId),
      ...(agentOverride ? { assignee_agent_id: Number(agentOverride.id) } : {}),
    })
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // Move Task to Backlog (PLN-7's `place`, destination omitted).
  const handleMoveTaskToBacklog = (taskId: string) => {
    placeTask(Number(taskId), {})
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // Move Task across Agent Day Columns (DayBoard drag) — lands at a
  // specific index within an EXISTING timeline.
  const handleMoveTaskToAgentDayTimeline = (
    taskId: string,
    targetTimelineId: string,
    targetIndex: number
  ) => {
    placeTask(Number(taskId), { timeline_id: Number(targetTimelineId), index: targetIndex })
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // Move a task that's already on a timeline to a different agent/day
  // (Epic E3's "Move…" menu action). `createTimeline` is idempotent — if
  // that agent already has a day started, it just returns it.
  const handleMoveTaskToAgentDay = (taskId: string, agentId: string, day: string) => {
    if (!activeWorkspaceId) return;
    createTimeline(Number(activeWorkspaceId), Number(agentId), day)
      .then(({ timeline }) => placeTask(Number(taskId), { timeline_id: timeline.id }))
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // Pull Task from Backlog into Timeline (or reorder within one, when
  // targetTimelineId is omitted — defaults to the active timeline).
  const handlePullToTimeline = (
    taskId: string,
    targetTimelineId?: string,
    targetIndex?: number
  ) => {
    const tlId = targetTimelineId || activeTimelineId;
    if (!tlId) return;
    placeTask(Number(taskId), { timeline_id: Number(tlId), ...(targetIndex !== undefined ? { index: targetIndex } : {}) })
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // Add a backlog task to a chosen agent's timeline on a chosen day, from
  // the Backlog drawer's "Add to timeline..." picker. Creates the
  // timeline if that agent doesn't have one on that day yet (idempotent),
  // then shows a brief confirmation of exactly where the task landed.
  const handleAddBacklogTaskToAgentDay = (
    taskId: string,
    agentId: string,
    day: string,
    targetIndex?: number
  ) => {
    if (!activeWorkspaceId) return;
    const agent = agents.find(a => a.id === agentId);
    if (!agent) return;
    createTimeline(Number(activeWorkspaceId), Number(agentId), day)
      .then(({ timeline }) =>
        placeTask(Number(taskId), { timeline_id: timeline.id, ...(targetIndex !== undefined ? { index: targetIndex } : {}) })
      )
      .then(({ moved }) => {
        setBacklogPlacementConfirmation(`Added to ${agent.name} · ${formatShortDate(day)}, step ${moved.clamped_index + 1}`);
        setTimeout(() => setBacklogPlacementConfirmation(null), 3500);
        return refreshBoard();
      })
      .catch(reportActionError);
  };

  // Create Backlog Task
  const handleCreateBacklogTask = (title: string, duration: number, assignee?: string) => {
    if (!activeWorkspaceId) return;
    const agentOverride = assignee ? agentsInActiveWs.find(a => a.name === assignee) : undefined;
    createTask(Number(activeWorkspaceId), {
      title,
      duration_minutes: duration,
      ...(agentOverride ? { assignee_agent_id: Number(agentOverride.id) } : {}),
    })
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // PLN-9: deleting a task has no live backend endpoint yet — same
  // "held, not pushed" reasoning as handleDeleteAgent above
  // (`functions/planner/delete_task.xs`). DayBoard/BacklogDrawer both
  // require this prop, so it stays wired to a clear refusal rather
  // than silently removing the row from local state only.
  const handleDeleteTask = (_taskId: string) => {
    reportActionError(new Error('Deleting a task isn’t available yet — ask the founder.'));
  };

  // Create or start timeline for an Agent on a specific Day (idempotent
  // server-side — a second click on the same cell just opens the
  // existing day rather than erroring).
  const handleStartTimelineForAgentDay = (agentId: string, day: string) => {
    if (!activeWorkspaceId) return;
    createTimeline(Number(activeWorkspaceId), Number(agentId), day)
      .then(({ timeline }) => {
        setActiveTimelineId(String(timeline.id));
        setActiveAgentId(agentId);
        setActiveDay(day);
        return refreshBoard();
      })
      .catch(reportActionError);
  };

  // Grid Drag: Move timeline cell to new day (sideways) or new agent
  // (vertically). The server refuses (never merges) if the target agent
  // already has a timeline on that date — ONE AGENT, ONE TIMELINE, PER
  // DAY (§4) — so no client-side pre-check is needed to stay honest.
  const handleMoveTimelineCell = (timelineId: string, targetAgentId: string, targetDate: string) => {
    updateTimeline(Number(timelineId), { agent_id: Number(targetAgentId), planned_date: targetDate })
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // Grid Drop: Task from backlog dropped onto filled cell
  const handleDropTaskOnTimelineCell = (taskId: string, timelineId: string) => {
    handlePullToTimeline(taskId, timelineId);
  };

  // Grid Drop: Task from backlog dropped onto empty cell — creates the
  // timeline for that agent/day, then places the task into it. (§4)
  const handleDropTaskOnEmptyCell = (taskId: string, agentId: string, date: string) => {
    if (!activeWorkspaceId) return;
    createTimeline(Number(activeWorkspaceId), Number(agentId), date)
      .then(({ timeline }) => {
        setActiveTimelineId(String(timeline.id));
        return placeTask(Number(taskId), { timeline_id: timeline.id });
      })
      .then(() => refreshBoard())
      .catch(reportActionError);
  };

  // Roster Drop: Drop backlog task directly onto an agent in the roster
  const handleDropTaskOnAgent = (taskId: string, agentId: string) => {
    const tl = timelines.find(t => t.workspaceId === activeWorkspaceId && t.agentId === agentId && t.plannedDate === activeDay);
    if (tl) {
      handlePullToTimeline(taskId, tl.id);
    } else {
      handleDropTaskOnEmptyCell(taskId, agentId, activeDay);
    }
  };

  // Open Bulk Publish confirmation modal (§6 & Deliverable J)
  const handleOpenBulkPublishModal = () => {
    const dayTimelines = timelines.filter(t => t.workspaceId === activeWorkspaceId && t.plannedDate === activeDay);

    const outcomes = dayTimelines.map(tl => {
      const agent = agents.find(a => a.id === tl.agentId);
      const tlTasks = tasks.filter(t => t.timelineId === tl.id);
      if (tl.status === 'published') {
        return {
          timeline: tl,
          agent,
          status: 'already_published' as const,
          taskCount: tlTasks.length,
        };
      }
      const readiness = getTimelineReadiness(tl, tlTasks, activeWorkspace);
      if (!readiness.ready) {
        return {
          timeline: tl,
          agent,
          status: 'blocked' as const,
          reason: readiness.reasons[0],
          taskCount: tlTasks.length,
        };
      }
      return {
        timeline: tl,
        agent,
        status: 'ready' as const,
        taskCount: tlTasks.length,
      };
    });

    setActiveModalEntity({
      type: 'bulk_publish_day',
      date: activeDay,
      outcomes,
    });
  };

  // Confirm Bulk Publish (US-PLN-9-05): LIVE-1 only exposes a
  // single-timeline publish, so "publish day" is this client-side loop
  // over it — flagged as a deliberate, not-yet-built backend gap in the
  // epic itself. Each call re-checks readiness on the server regardless
  // of what this modal showed when it opened, and failures accumulate
  // into one message rather than stopping the whole batch at the first
  // one (a day half-published is still useful; a silent full failure
  // over one bad timeline would not be).
  const handleConfirmBulkPublish = (timelineIdsToPublish: string[]) => {
    Promise.allSettled(timelineIdsToPublish.map(id => publishTimelineApi(Number(id))))
      .then((results) => {
        const failures = results.filter((r): r is PromiseRejectedResult => r.status === 'rejected');
        if (failures.length > 0) {
          const firstMsg = failures[0].reason instanceof Error ? failures[0].reason.message : 'Something went wrong.';
          reportActionError(new Error(
            failures.length === timelineIdsToPublish.length
              ? firstMsg
              : `${timelineIdsToPublish.length - failures.length} of ${timelineIdsToPublish.length} published. First problem: ${firstMsg}`
          ));
        }
        return refreshBoard();
      });
    setActiveModalEntity(null);
  };

  // Deliverable Scenarios A–J Interactive Verification (§11)
  const handleSelectScenario = (scenarioId: string) => {
    switch (scenarioId) {
      case 'scenario-a':
        // 5 agents × 2 weeks, mixed filled/empty, one over capacity, one blocked, one published
        setViewMode('schedule');
        setActiveDay('2026-10-13');
        setAgents(prev => prev.map((a, i) => ({
          ...a,
          isVisible: i < 5, // Show first 5 agents
        })));
        break;

      case 'scenario-b':
        // 10 agents, vertical scroll with pinned headers
        setViewMode('schedule');
        setAgents(prev => prev.map(a => ({ ...a, isVisible: true })));
        break;

      case 'scenario-c':
        // Mid-drag in grid states
        setViewMode('schedule');
        break;

      case 'scenario-d':
        // Bucket task dropping onto empty cell
        setViewMode('schedule');
        break;

      case 'scenario-e':
        // Day board: 3 agents, one over capacity, one published
        setViewMode('plan');
        setActiveDay('2026-10-13');
        setFocusedAgentId(null);
        setAgents(prev => prev.map(a => ({
          ...a,
          isVisible: ['agent-marcus', 'agent-kavita', 'agent-intake'].includes(a.id),
        })));
        break;

      case 'scenario-f':
        // Day board: mid-drag of task across two agent columns
        setViewMode('plan');
        setActiveDay('2026-10-13');
        setFocusedAgentId(null);
        break;

      case 'scenario-g':
        // Day board: 6 agents, horizontal scroll
        setViewMode('plan');
        setActiveDay('2026-10-13');
        setFocusedAgentId(null);
        setAgents(prev => prev.map((a, idx) => ({
          ...a,
          isVisible: idx < 6,
        })));
        break;

      case 'scenario-h':
        // Focus mode: one agent, existing detailed table, 'Back to all agents'
        setViewMode('plan');
        setActiveDay('2026-10-13');
        setFocusedAgentId('agent-marcus');
        break;

      case 'scenario-i':
        // Roster default, search state, add-agent modal
        handleOpenAddAgentModal();
        break;

      case 'scenario-j':
        // 'Publish day' confirmation with mixed outcomes
        setActiveDay('2026-10-13');
        handleOpenBulkPublishModal();
        break;

      default:
        break;
    }
  };

  // Shared toolbar controls. Defined once here and handed to whichever view
  // is mounted, so the view switcher can live in each view's own toolbar row
  // without duplicating markup (and without stranding the user in a view
  // that has no way back).
  const viewSwitcher = (
    <div className="inline-flex rounded-lg border border-neutral-300 p-0.5 bg-neutral-100 text-xs shrink-0">
      <button
        id="view-mode-plan-btn"
        type="button"
        onClick={() => setViewMode('plan')}
        className={`flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors ${
          viewMode === 'plan'
            ? 'bg-white text-neutral-900 shadow-2xs font-semibold'
            : 'text-neutral-600 hover:text-neutral-900'
        }`}
      >
        <LayoutList className="w-3.5 h-3.5" />
        Plan
      </button>
      <button
        id="view-mode-schedule-btn"
        type="button"
        onClick={() => setViewMode('schedule')}
        className={`flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors ${
          viewMode === 'schedule'
            ? 'bg-white text-neutral-900 shadow-2xs font-semibold'
            : 'text-neutral-600 hover:text-neutral-900'
        }`}
      >
        <Calendar className="w-3.5 h-3.5" />
        Schedule
      </button>
    </div>
  );

  // Width is passed per view so each toolbar's right-hand cluster can span
  // the same 366px as the header cluster above it: Plan pairs it with
  // "Publish day", Schedule with Agents + the week toggle.
  const renderBuildPlanButton = (widthClass = '') => (
    <button
      id="build-plan-btn"
      type="button"
      className={`${widthClass} flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-md border border-emerald-300 bg-emerald-100 text-emerald-900 text-xs font-semibold hover:bg-emerald-200 hover:border-emerald-400 transition-colors shrink-0`}
    >
      <Hammer className="w-3.5 h-3.5 shrink-0" />
      Build Plan
    </button>
  );

  // PLN-9: this app never had a loading or error state before — a
  // localStorage read cannot fail or take time. Both are real now.
  if (!dataLoaded) {
    return (
      <div className="flex h-screen w-screen items-center justify-center bg-white">
        <div className="w-6 h-6 border-2 border-zinc-300 border-t-zinc-700 rounded-full animate-spin" />
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="flex h-screen w-screen items-center justify-center bg-white p-4">
        <div className="max-w-sm text-center">
          <p className="text-sm text-zinc-700">{loadError}</p>
          <button
            type="button"
            onClick={() => (activeWorkspaceId ? void loadActiveBoard(activeWorkspaceId) : window.location.reload())}
            className="mt-4 rounded-lg bg-zinc-900 px-4 py-2 text-sm text-white"
          >
            Try again
          </button>
        </div>
      </div>
    );
  }

  if (workspaces.length === 0) {
    return (
      <div className="flex h-screen w-screen items-center justify-center bg-white p-4">
        <p className="text-sm text-zinc-500">No plans yet for this account.</p>
      </div>
    );
  }

  return (
    <div id="emgram-planner-app" className="flex h-screen w-screen overflow-hidden bg-white text-neutral-900 font-sans antialiased">
      {isLoadingBoard && (
        <div className="absolute top-3 right-3 z-50 flex items-center gap-2 rounded-full bg-white border border-zinc-200 shadow-sm px-3 py-1.5 text-xs text-zinc-500">
          <div className="w-3 h-3 border-2 border-zinc-300 border-t-zinc-700 rounded-full animate-spin" />
          Loading…
        </div>
      )}
      {/* PLN-9: a rejected write's friendly server message (VAL-1), or a
          not-yet-available action's own explanation — surfaced here
          rather than inside EditModal so it still reaches the user for
          actions with no modal at all (visibility toggles, drag moves). */}
      {actionError && (
        <div
          id="action-error-toast"
          className="absolute top-3 left-1/2 -translate-x-1/2 z-50 max-w-md rounded-lg bg-red-50 border border-red-200 shadow-sm px-3.5 py-2 text-xs text-red-800"
        >
          {actionError}
        </div>
      )}
      {/* LEFT PRODUCT RAIL NAV (~60px) */}
      <ProductNav onOpenSettings={() => setIsSettingsOpen(true)} />

      {/* MAIN VIEW AREA */}
      <div className="flex-1 flex flex-col min-w-0 h-full overflow-hidden">
        {/* HEADER (56px) with Workspace Switcher, Planning Window, View Mode Switcher */}
        <Header
          workspaces={workspaces}
          activeWorkspace={activeWorkspace}
          onSelectWorkspace={handleSelectWorkspace}
          onRequestCreateWorkspace={handleOpenCreateWorkspaceModal}
          onRenameWorkspace={handleRenameWorkspace}
          onDeleteWorkspace={handleDeleteWorkspace}
          onOpenWorkspaceSettings={() => setIsWorkspaceSettingsOpen(true)}
        />

        {/* Workspace Body: Board/Grid + Backlog */}
        <div className="flex-1 flex min-h-0 overflow-hidden">
          {/* Center Column: Day Board (Plan View) or Schedule Grid (Schedule View) + Backlog Drawer */}
          <div className="flex-1 flex flex-col min-w-0 h-full overflow-hidden bg-white">
            {viewMode === 'plan' ? (
              /* DAY BOARD (Section 5: One Day, All Agents Side-by-Side) */
              <DayBoard
                workspace={activeWorkspace}
                agents={agentsInActiveWs}
                timelines={timelinesInActiveWs}
                tasks={tasks}
                activeDay={activeDay}
                focusedAgentId={focusedAgentId}
                planningWindowStart={activeWorkspace?.planningWindowStart || '2026-10-12'}
                planningWindowEnd={activeWorkspace?.planningWindowEnd || '2026-10-25'}
                onChangeDay={(newDay) => {
                  setActiveDay(newDay);
                  const tl = timelines.find(t => t.workspaceId === activeWorkspaceId && t.plannedDate === newDay && (activeAgentId ? t.agentId === activeAgentId : true));
                  if (tl) setActiveTimelineId(tl.id);
                }}
                onFocusAgent={setFocusedAgentId}
                onOpenTaskEditModal={handleOpenTaskEditModal}
                onOpenTimelineEditModal={handleOpenTimelineEditModal}
                onStartTimelineForAgentDay={handleStartTimelineForAgentDay}
                onReorderTasksInTimeline={handleReorderTasks}
                onMoveTaskToAgentDayTimeline={handleMoveTaskToAgentDayTimeline}
                onAddTaskToTimeline={handleAddTaskToTimeline}
                onPublishTimeline={handlePublishTimeline}
                onReopenTimeline={handleReopenTimeline}
                onDeleteTask={handleDeleteTask}
                onMoveTaskToBacklog={handleMoveTaskToBacklog}
                onMoveTaskToAgentDay={handleMoveTaskToAgentDay}
                onOpenBulkPublishModal={handleOpenBulkPublishModal}
                onRequestPublishConfirm={handleRequestPublishConfirm}
                viewSwitcher={viewSwitcher}
                buildPlanButton={renderBuildPlanButton('w-[229px]')}
                onToggleAgentVisibility={handleToggleAgentVisibility}
                onShowAllAgents={handleShowAllAgents}
                onHideAllAgents={handleHideAllAgents}
                onOpenAddAgentModal={handleOpenAddAgentModal}
                onEditAgent={handleOpenEditAgentModal}
                onTimelineTaskDragStart={() => setIsDraggingTaskFromTimeline(true)}
                onTimelineTaskDragEnd={() => setIsDraggingTaskFromTimeline(false)}
              />
            ) : (
              /* SCHEDULE GRID (Section 4: Agents × Days Matrix) */
              <ScheduleGrid
                workspace={activeWorkspace}
                agents={agentsInActiveWs}
                timelines={timelinesInActiveWs}
                tasks={tasks}
                onOpenCellInPlan={(date, agentId) => {
                  setActiveDay(date);
                  setActiveAgentId(agentId);
                  const tl = timelines.find(t => t.workspaceId === activeWorkspaceId && t.agentId === agentId && t.plannedDate === date);
                  if (tl) setActiveTimelineId(tl.id);
                  setViewMode('plan');
                }}
                onCreateTimelineForCell={handleStartTimelineForAgentDay}
                onMoveTimelineCell={handleMoveTimelineCell}
                onDropTaskOnTimelineCell={handleDropTaskOnTimelineCell}
                onDropTaskOnEmptyCell={handleDropTaskOnEmptyCell}
                onToggleAgentVisibility={handleToggleAgentVisibility}
                onShowAllAgents={handleShowAllAgents}
                onHideAllAgents={handleHideAllAgents}
                onOpenAddAgentModal={handleOpenAddAgentModal}
                onEditAgent={handleOpenEditAgentModal}
                viewSwitcher={viewSwitcher}
                buildPlanButton={renderBuildPlanButton()}
              />
            )}

            {/* UNPLANNED BACKLOG DRAWER (Enabled without expand/collapse, drop target & task provider) */}
            <BacklogDrawer
              backlogTasks={backlogTasksInActiveWs}
              tasks={tasks}
              agents={agentsInActiveWs}
              workspace={activeWorkspace}
              timelinesInWorkspace={timelinesInActiveWs}
              visibleDates={visibleDates}
              showCapacityPanel
              compactMetrics={viewMode === 'plan'}
              settings={settings}
              throughput={activeThroughput}
              onOpenSettings={() => setIsSettingsOpen(true)}
              activeModalTaskId={activeModalTaskId}
              isDraggingTaskFromTimeline={isDraggingTaskFromTimeline}
              confirmationMessage={backlogPlacementConfirmation}
              onOpenTaskEditModal={handleOpenTaskEditModal}
              onSelectTask={handleOpenTaskEditModal}
              onAddToAgentDay={handleAddBacklogTaskToAgentDay}
              onCreateBacklogTask={handleCreateBacklogTask}
              onDeleteTask={handleDeleteTask}
              onDropTaskIntoBucket={handleMoveTaskToBacklog}
            />
          </div>
        </div>
      </div>

      {/* Centered Edit Modal over dimmed scrim */}
      <EditModal
        isOpen={activeModalEntity !== null}
        entity={activeModalEntity}
        onClose={() => setActiveModalEntity(null)}
        onSaveTask={handleSaveTaskFromModal}
        onSaveTimeline={handleSaveTimelineFromModal}
        settings={settings}
        onSaveAgent={handleSaveAgent}
        onConfirmBulkPublish={handleConfirmBulkPublish}
        onConfirmPublish={handlePublishTimeline}
        onReopenTimeline={handleReopenTimeline}
      />

      {/* Settings: cost rates & model pricing */}
      <SettingsModal
        isOpen={isSettingsOpen}
        settings={settings}
        throughput={activeThroughput}
        onClose={() => setIsSettingsOpen(false)}
        onSave={setSettings}
      />

      {/* Workspace Settings: planning window + this project's throughput */}
      <WorkspaceSettingsModal
        isOpen={isWorkspaceSettingsOpen}
        workspace={activeWorkspace}
        onClose={() => setIsWorkspaceSettingsOpen(false)}
        onSave={handleUpdateWorkspaceSettings}
        onOpenGlobalSettings={() => setIsSettingsOpen(true)}
      />

      {/* New plan from a template (US-PLN-9-07) */}
      <CreateWorkspaceModal
        isOpen={isCreateWorkspaceModalOpen}
        templates={templates}
        isLoadingTemplates={isLoadingTemplates}
        onClose={() => setIsCreateWorkspaceModalOpen(false)}
        onCreate={handleCreateWorkspaceFromTemplate}
      />

      {/* Component Sheet & Deliverables Modal (§11 & §8) */}
      <ComponentSheetModal
        isOpen={isComponentSheetOpen}
        onClose={() => setIsComponentSheetOpen(false)}
        onSelectScenario={handleSelectScenario}
      />
    </div>
  );
}
