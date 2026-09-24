import { useState, useEffect, useMemo } from 'react';
import { Calendar, LayoutList, Hammer } from 'lucide-react';
import { Workspace, Timeline, Task, Agent, ViewMode, AppSettings } from './types';
import { loadStoredData, saveStoredData, DEFAULT_SETTINGS, DEFAULT_INPUT_TOKENS_PER_MINUTE, DEFAULT_OUTPUT_TOKENS_PER_MINUTE } from './data/initialData';
import { ProductNav } from './components/ProductNav';
import { SettingsModal } from './components/SettingsModal';
import { WorkspaceSettingsModal } from './components/WorkspaceSettingsModal';
import { Header } from './components/Header';
import { AgentRosterRail } from './components/AgentRosterRail';
import { ScheduleGrid } from './components/ScheduleGrid';
import { DayBoard } from './components/DayBoard';
import { BacklogDrawer } from './components/BacklogDrawer';
import { EditModal, ModalEntity } from './components/EditModal';
import { ComponentSheetModal } from './components/ComponentSheetModal';
import { calculateTaskLanding, recomputeTimelineTaskTimes, getTimelineReadiness, formatMinutesToTime, parseTimeToMinutes } from './utils/planningLogic';
import { formatShortDate, generateDaysList, getDaysDifference } from './utils/dateUtils';
import { getNextAgentColor } from './utils/agentUtils';

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

  // Recomputes planned_start for every task in a timeline (cascading from
  // the timeline's own startTime) and merges the result back into a full
  // tasks array. Call this as the final step of ANY mutation that touches
  // a timeline's tasks (add / move / reorder / delete) or its startTime.
  const recomputeTimeline = (allTasks: Task[], timelineId: string | null, timelineOverride?: Timeline): Task[] => {
    if (!timelineId) return allTasks;
    const timeline = timelineOverride || timelines.find(tl => tl.id === timelineId);
    if (!timeline) return allTasks;
    const ordered = allTasks.filter(t => t.timelineId === timelineId).sort((a, b) => a.seq - b.seq);
    const recomputed = recomputeTimelineTaskTimes(timeline, ordered);
    const map = new Map(recomputed.map(t => [t.id, t]));
    return allTasks.map(t => map.has(t.id) ? map.get(t.id)! : t);
  };

  // Load initial data on mount
  useEffect(() => {
    const data = loadStoredData();
    setWorkspaces(data.workspaces);
    setAgents(data.agents);
    setTimelines(data.timelines);
    setTasks(data.tasks);
    setSettings(data.settings);

    if (data.workspaces.length > 0) {
      const defaultWsId = data.workspaces[0].id;
      setActiveWorkspaceId(defaultWsId);

      const firstTl = data.timelines.find(t => t.workspaceId === defaultWsId);
      if (firstTl) {
        setActiveTimelineId(firstTl.id);
        if (firstTl.plannedDate) {
          setActiveDay(firstTl.plannedDate);
        }
        if (firstTl.agentId) {
          setActiveAgentId(firstTl.agentId);
        }
      }
    }

    setDataLoaded(true);
  }, []);

  // Save to localStorage when state changes
  useEffect(() => {
    if (!dataLoaded) return;
    saveStoredData(workspaces, agents, timelines, tasks, settings);
  }, [workspaces, agents, timelines, tasks, settings, dataLoaded]);

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

  // Handler: Create Workspace
  const handleCreateWorkspace = (name: string) => {
    const newWs: Workspace = {
      id: `ws-${Date.now()}`,
      name,
      createdAt: new Date().toISOString().split('T')[0],
      planningWindowStart: '2026-10-12',
      planningWindowEnd: '2026-10-25',
      inputTokensPerMinute: DEFAULT_INPUT_TOKENS_PER_MINUTE,
      outputTokensPerMinute: DEFAULT_OUTPUT_TOKENS_PER_MINUTE,
    };
    setWorkspaces(prev => [...prev, newWs]);
    setActiveWorkspaceId(newWs.id);
    setActiveTimelineId(null);
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

  // Agent Roster handlers
  const handleToggleAgentVisibility = (agentId: string) => {
    setAgents(prev => prev.map(a => a.id === agentId ? { ...a, isVisible: !a.isVisible } : a));
  };

  const handleShowAllAgents = () => {
    setAgents(prev => prev.map(a => a.workspaceId === activeWorkspaceId ? { ...a, isVisible: true } : a));
  };

  const handleHideAllAgents = () => {
    setAgents(prev => prev.map(a => {
      if (a.workspaceId === activeWorkspaceId) {
        return { ...a, isVisible: a.id === activeAgentId || a.id === focusedAgentId };
      }
      return a;
    }));
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

  const handleSaveAgent = (
    agentId: string | null,
    updates: { name: string; kind: 'person' | 'ai'; color: string; dailyCapacityHours: number; modelId?: string }
  ) => {
    if (agentId) {
      // Update existing agent
      setAgents(prev => prev.map(a => a.id === agentId ? { ...a, ...updates } : a));
      // Update assignee name on timelines and tasks
      setTimelines(prev => prev.map(tl => tl.agentId === agentId ? { ...tl, assignee: updates.name } : tl));
      setTasks(prev => prev.map(t => {
        const tl = timelines.find(x => x.id === t.timelineId);
        if (tl && tl.agentId === agentId) {
          return { ...t, assignee: updates.name };
        }
        return t;
      }));
    } else {
      // Add new agent
      const nextColor = updates.color || getNextAgentColor(agentsInActiveWs);
      const newAgent: Agent = {
        id: `agent-${Date.now()}`,
        workspaceId: activeWorkspaceId,
        name: updates.name,
        kind: updates.kind,
        color: nextColor,
        dailyCapacityHours: updates.dailyCapacityHours || 8,
        isVisible: true,
        modelId: updates.modelId,
      };
      setAgents(prev => [...prev, newAgent]);
      setActiveAgentId(newAgent.id);
    }
    setActiveModalEntity(null);
  };

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

  // Save Task from Modal
  const handleSaveTaskFromModal = (taskId: string, updates: Partial<Task>) => {
    setTasks(prev => {
      const target = prev.find(t => t.id === taskId);
      const merged = prev.map(t => t.id === taskId ? { ...t, ...updates } : t);
      // Duration/status edits shift every step below it, so recompute the
      // cascade for this task's timeline (planned_start is never taken
      // from the modal directly).
      return recomputeTimeline(merged, target?.timelineId ?? null);
    });
    setActiveModalEntity(null);
    setAcknowledgedTaskId(taskId);
    setTimeout(() => {
      setAcknowledgedTaskId(null);
    }, 2500);
  };

  // Save Timeline from Modal
  const handleSaveTimelineFromModal = (timelineId: string, updates: Partial<Timeline>) => {
    let mergedTimeline: Timeline | null = null;
    setTimelines(prev => prev.map(tl => {
      if (tl.id !== timelineId) return tl;
      mergedTimeline = { ...tl, ...updates };
      return mergedTimeline;
    }));
    if (updates.startTime !== undefined && mergedTimeline) {
      setTasks(prev => recomputeTimeline(prev, timelineId, mergedTimeline!));
    }
    setActiveModalEntity(null);
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

  // Publish Timeline
  const handlePublishTimeline = (timelineId: string) => {
    setTimelines(prev => prev.map(tl => {
      if (tl.id !== timelineId) return tl;
      // Defense-in-depth: never publish a timeline that isn't ready, even
      // if a caller bypasses its own disabled-state check.
      const tlTasks = tasks.filter(t => t.timelineId === tl.id);
      const readiness = getTimelineReadiness(tl, tlTasks, activeWorkspace);
      if (!readiness.ready) return tl;
      return { ...tl, status: 'published' };
    }));
  };

  // Reopen Timeline
  const handleReopenTimeline = (timelineId: string) => {
    setTimelines(prev => prev.map(tl => tl.id === timelineId ? { ...tl, status: 'draft' } : tl));
    if (activeModalEntity && activeModalEntity.type === 'timeline' && activeModalEntity.timeline.id === timelineId) {
      setActiveModalEntity((prev: ModalEntity | null) => prev && prev.type === 'timeline' ? {
        ...prev,
        timeline: { ...prev.timeline, status: 'draft' }
      } : prev);
    } else if (activeModalEntity && activeModalEntity.type === 'task' && activeModalEntity.timeline?.id === timelineId) {
      setActiveModalEntity((prev: ModalEntity | null) => prev && prev.type === 'task' && prev.timeline ? {
        ...prev,
        timeline: { ...prev.timeline, status: 'draft' }
      } : prev);
    }
  };

  // Reorder Tasks within Timeline
  const handleReorderTasks = (timelineId: string, reorderedTasks: Task[]) => {
    setTasks(prev => {
      const taskMap = new Map(reorderedTasks.map(t => [t.id, t]));
      const merged = prev.map(t => taskMap.has(t.id) ? taskMap.get(t.id)! : t);
      return recomputeTimeline(merged, timelineId);
    });
  };

  // Add Task directly into timeline
  const handleAddTaskToTimeline = (
    timelineId: string,
    title: string, 
    plannedStart: string, 
    duration: number, 
    assignee?: string
  ) => {
    if (!activeWorkspaceId || !timelineId) return;

    const currentTasks = tasks.filter(t => t.timelineId === timelineId);
    const nextSeq = currentTasks.length + 1;

    const newTask: Task = {
      id: `task-${Date.now()}`,
      workspaceId: activeWorkspaceId,
      timelineId,
      title,
      seq: nextSeq,
      planned_start: plannedStart,
      duration,
      assignee: assignee || '',
      notes: '',
      status: 'planned',
    };

    setTasks(prev => recomputeTimeline([...prev, newTask], timelineId));
  };

  // Move Task to Backlog
  const handleMoveTaskToBacklog = (taskId: string) => {
    const currentTask = tasks.find(t => t.id === taskId);
    if (!currentTask) return;
    const oldTimelineId = currentTask.timelineId;

    setTasks(prev => {
      return prev.map(t => {
        if (t.id === taskId) {
          return {
            ...t,
            timelineId: null,
            seq: 0,
            planned_start: '',
          };
        }
        return t;
      });
    });

    // Re-index and recompute cascade times for remaining tasks in old timeline
    if (oldTimelineId) {
      setTimeout(() => {
        setTasks(latestTasks => recomputeTimeline(latestTasks, oldTimelineId));
      }, 10);
    }
  };

  // Move Task across Agent Day Columns (DayBoard drag)
  const handleMoveTaskToAgentDayTimeline = (
    taskId: string, 
    targetTimelineId: string, 
    targetIndex: number
  ) => {
    const task = tasks.find(t => t.id === taskId);
    const targetTl = timelines.find(t => t.id === targetTimelineId);
    if (!task || !targetTl) return;

    const targetTlTasks = tasks
      .filter(t => t.timelineId === targetTimelineId && t.id !== taskId)
      .sort((a, b) => a.seq - b.seq);

    const oldTimelineId = task.timelineId;

    // Determine duration/assignee for the arriving task; start time is
    // always recomputed by the cascade below, never set here.
    const landing = calculateTaskLanding(task, targetTl);

    const updatedTask: Task = {
      ...task,
      timelineId: targetTimelineId,
      duration: landing.duration,
      assignee: landing.assignee,
      status: landing.status,
      needsInfoReason: landing.needsInfoReason,
    };

    // Insert at target index
    const newList = [...targetTlTasks];
    const clampedIndex = Math.min(Math.max(0, targetIndex), newList.length);
    newList.splice(clampedIndex, 0, updatedTask);

    const reorderedTarget = newList.map((t, idx) => ({
      ...t,
      seq: idx + 1,
    }));

    setTasks(prev => {
      const map = new Map(reorderedTarget.map(t => [t.id, t]));
      const merged = prev.map(t => {
        if (map.has(t.id)) return map.get(t.id)!;
        return t;
      });
      return recomputeTimeline(merged, targetTimelineId);
    });

    // Re-index & recompute old timeline if different
    if (oldTimelineId && oldTimelineId !== targetTimelineId) {
      setTimeout(() => {
        setTasks(latestTasks => recomputeTimeline(latestTasks, oldTimelineId));
      }, 10);
    }
  };

  // Move a task that's already on a timeline to a different agent/day
  // (Epic E3's "Move…" menu action). Creates the target timeline if that
  // agent doesn't have one on that day yet, mirroring
  // handleAddBacklogTaskToAgentDay's creation logic.
  const handleMoveTaskToAgentDay = (taskId: string, agentId: string, day: string) => {
    if (!activeWorkspaceId) return;
    const agent = agents.find(a => a.id === agentId);
    const task = tasks.find(t => t.id === taskId);
    if (!agent || !task) return;

    let targetTl = timelines.find(
      tl => tl.workspaceId === activeWorkspaceId && tl.agentId === agentId && tl.plannedDate === day
    );
    const isNewTimeline = !targetTl;
    if (!targetTl) {
      targetTl = {
        id: `tl-${Date.now()}`,
        workspaceId: activeWorkspaceId,
        agentId,
        name: `${formatShortDate(day)} — ${agent.name}`,
        plannedDate: day,
        assignee: agent.name,
        status: 'draft',
        startTime: '08:00',
      };
      setTimelines(prev => [...prev, targetTl!]);
    } else if (targetTl.status === 'published') {
      // Defense-in-depth: the picker already disables this combination.
      return;
    }

    const oldTimelineId = task.timelineId;

    const targetTlTasks = tasks
      .filter(t => t.timelineId === targetTl!.id && t.id !== taskId)
      .sort((a, b) => a.seq - b.seq);

    const landing = calculateTaskLanding(task, targetTl);

    const movedTask: Task = {
      ...task,
      timelineId: targetTl.id,
      duration: landing.duration,
      assignee: landing.assignee,
      status: landing.status,
      needsInfoReason: landing.needsInfoReason,
    };

    const newList = [...targetTlTasks, movedTask];
    const reordered = newList.map((t, idx) => ({ ...t, seq: idx + 1 }));

    setTasks(prev => {
      const map = new Map(reordered.map(t => [t.id, t]));
      const merged = prev.map(t => map.has(t.id) ? map.get(t.id)! : t);
      return recomputeTimeline(merged, targetTl!.id, isNewTimeline ? targetTl! : undefined);
    });

    if (oldTimelineId && oldTimelineId !== targetTl.id) {
      setTimeout(() => {
        setTasks(latestTasks => recomputeTimeline(latestTasks, oldTimelineId));
      }, 10);
    }
  };

  // Pull Task from Backlog into Timeline
  const handlePullToTimeline = (
    taskId: string, 
    targetTimelineId?: string, 
    targetIndex?: number
  ) => {
    const tlId = targetTimelineId || activeTimelineId;
    if (!tlId) return;
    const targetTl = timelines.find(t => t.id === tlId);
    if (!targetTl) return;

    const task = tasks.find(t => t.id === taskId);
    if (!task) return;

    const tlTasks = tasks
      .filter(t => t.timelineId === tlId)
      .sort((a, b) => a.seq - b.seq);

    const insertIdx = targetIndex !== undefined ? targetIndex : tlTasks.length;

    // Determine duration/assignee only; start time is always recomputed
    // by the cascade below, never set here.
    const landing = calculateTaskLanding(task, targetTl);

    const placedTask: Task = {
      ...task,
      timelineId: tlId,
      duration: landing.duration,
      assignee: landing.assignee,
      status: landing.status,
      needsInfoReason: landing.needsInfoReason,
    };

    const newList = [...tlTasks];
    const clamped = Math.min(Math.max(0, insertIdx), newList.length);
    newList.splice(clamped, 0, placedTask);

    const reordered = newList.map((t, idx) => ({
      ...t,
      seq: idx + 1,
    }));

    setTasks(prev => {
      const map = new Map(reordered.map(t => [t.id, t]));
      const merged = prev.map(t => map.has(t.id) ? map.get(t.id)! : t);
      return recomputeTimeline(merged, tlId);
    });
  };

  // Add a backlog task to a chosen agent's timeline on a chosen day, from
  // the Backlog drawer's "Add to timeline..." picker (replaces the old
  // ambiguous "Place onto active timeline" quick action). Creates the
  // timeline if that agent doesn't have one on that day yet, then shows a
  // brief confirmation of exactly where the task landed.
  const handleAddBacklogTaskToAgentDay = (
    taskId: string,
    agentId: string,
    day: string,
    targetIndex?: number
  ) => {
    if (!activeWorkspaceId) return;
    const agent = agents.find(a => a.id === agentId);
    const task = tasks.find(t => t.id === taskId);
    if (!agent || !task) return;

    let targetTl = timelines.find(
      tl => tl.workspaceId === activeWorkspaceId && tl.agentId === agentId && tl.plannedDate === day
    );
    const isNewTimeline = !targetTl;
    if (!targetTl) {
      targetTl = {
        id: `tl-${Date.now()}`,
        workspaceId: activeWorkspaceId,
        agentId,
        name: `${formatShortDate(day)} — ${agent.name}`,
        plannedDate: day,
        assignee: agent.name,
        status: 'draft',
        startTime: '08:00',
      };
      setTimelines(prev => [...prev, targetTl!]);
    } else if (targetTl.status === 'published') {
      // Defense-in-depth: the picker already disables this combination.
      return;
    }

    const tlTasks = tasks
      .filter(t => t.timelineId === targetTl!.id)
      .sort((a, b) => a.seq - b.seq);
    const insertIdx = targetIndex !== undefined ? targetIndex : tlTasks.length;

    const landing = calculateTaskLanding(task, targetTl);

    const placedTask: Task = {
      ...task,
      timelineId: targetTl.id,
      duration: landing.duration,
      assignee: landing.assignee,
      status: landing.status,
      needsInfoReason: landing.needsInfoReason,
    };

    const newList = [...tlTasks];
    const clamped = Math.min(Math.max(0, insertIdx), newList.length);
    newList.splice(clamped, 0, placedTask);

    const reordered = newList.map((t, idx) => ({
      ...t,
      seq: idx + 1,
    }));

    setTasks(prev => {
      const map = new Map(reordered.map(t => [t.id, t]));
      const merged = prev.map(t => map.has(t.id) ? map.get(t.id)! : t);
      return recomputeTimeline(merged, targetTl!.id, isNewTimeline ? targetTl! : undefined);
    });

    const landedStep = clamped + 1;
    setBacklogPlacementConfirmation(`Added to ${agent.name} · ${formatShortDate(day)}, step ${landedStep}`);
    setTimeout(() => setBacklogPlacementConfirmation(null), 3500);
  };

  // Create Backlog Task
  const handleCreateBacklogTask = (title: string, duration: number, assignee?: string) => {
    if (!activeWorkspaceId) return;
    const newTask: Task = {
      id: `task-${Date.now()}`,
      workspaceId: activeWorkspaceId,
      timelineId: null,
      title,
      seq: 0,
      planned_start: '',
      duration,
      assignee: assignee || '',
      notes: '',
      status: 'planned',
    };
    setTasks(prev => [...prev, newTask]);
  };

  // Delete Task
  const handleDeleteTask = (taskId: string) => {
    const taskToDelete = tasks.find(t => t.id === taskId);
    setTasks(prev => prev.filter(t => t.id !== taskId));

    if (taskToDelete?.timelineId) {
      const tlId = taskToDelete.timelineId;
      setTimeout(() => {
        setTasks(latestTasks => recomputeTimeline(latestTasks, tlId));
      }, 10);
    }
  };

  // Create or start timeline for an Agent on a specific Day
  const handleStartTimelineForAgentDay = (agentId: string, day: string) => {
    if (!activeWorkspaceId) return;

    // Check if timeline already exists for this agent on this day
    const existing = timelines.find(t => t.workspaceId === activeWorkspaceId && t.agentId === agentId && t.plannedDate === day);
    if (existing) {
      setActiveTimelineId(existing.id);
      setActiveAgentId(agentId);
      setActiveDay(day);
      return;
    }

    const agent = agents.find(a => a.id === agentId);
    const newTl: Timeline = {
      id: `tl-${Date.now()}`,
      workspaceId: activeWorkspaceId,
      agentId,
      name: `${formatShortDate(day)} — ${agent?.name || 'Agent'}`,
      plannedDate: day,
      assignee: agent?.name || 'Agent',
      status: 'draft',
      startTime: '08:00',
    };

    setTimelines(prev => [...prev, newTl]);
    setActiveTimelineId(newTl.id);
    setActiveAgentId(agentId);
    setActiveDay(day);
  };

  // Grid Drag: Move timeline cell to new day (sideways) or new agent (vertically)
  // Enforces ONE AGENT, ONE TIMELINE, PER DAY rule (§4)
  const handleMoveTimelineCell = (timelineId: string, targetAgentId: string, targetDate: string) => {
    // Refusal check: does target cell already have a timeline?
    const occupied = timelines.find(t => 
      t.workspaceId === activeWorkspaceId && 
      t.agentId === targetAgentId && 
      t.plannedDate === targetDate && 
      t.id !== timelineId
    );

    if (occupied) {
      console.warn('Move refused: Target agent already has a timeline on that date.');
      return;
    }

    const targetAgent = agents.find(a => a.id === targetAgentId);

    setTimelines(prev => prev.map(tl => {
      if (tl.id === timelineId) {
        return {
          ...tl,
          agentId: targetAgentId,
          plannedDate: targetDate,
          assignee: targetAgent?.name || tl.assignee,
          name: `${formatShortDate(targetDate)} — ${targetAgent?.name || tl.assignee}`,
        };
      }
      return tl;
    }));

    if (targetAgent) {
      setTasks(prev => prev.map(t => t.timelineId === timelineId ? { ...t, assignee: targetAgent.name } : t));
    }
  };

  // Grid Drop: Task from backlog dropped onto filled cell
  const handleDropTaskOnTimelineCell = (taskId: string, timelineId: string) => {
    handlePullToTimeline(taskId, timelineId);
  };

  // Grid Drop: Task from backlog dropped onto empty cell
  // Creates timeline for agent on that day, and places task in it! (§4)
  const handleDropTaskOnEmptyCell = (taskId: string, agentId: string, date: string) => {
    const agent = agents.find(a => a.id === agentId);
    const newTlId = `tl-${Date.now()}`;
    const newTl: Timeline = {
      id: newTlId,
      workspaceId: activeWorkspaceId,
      agentId,
      name: `${formatShortDate(date)} — ${agent?.name || 'Agent'}`,
      plannedDate: date,
      assignee: agent?.name || 'Agent',
      status: 'draft',
      startTime: '08:00',
    };

    setTimelines(prev => [...prev, newTl]);
    setActiveTimelineId(newTlId);

    // Place the task into the newly created timeline (start time cascades
    // from the new timeline's startTime, not hardcoded)
    setTasks(prev => {
      const merged = prev.map(t => {
        if (t.id === taskId) {
          return {
            ...t,
            timelineId: newTlId,
            seq: 1,
            assignee: agent?.name || t.assignee,
            status: 'planned' as const,
          };
        }
        return t;
      });
      return recomputeTimeline(merged, newTlId, newTl);
    });
  };

  // Roster Drop: Drop backlog task directly onto an agent in the roster
  const handleDropTaskOnAgent = (taskId: string, agentId: string) => {
    // Find timeline for agent on activeDay, or create one
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

  // Confirm Bulk Publish
  const handleConfirmBulkPublish = (timelineIdsToPublish: string[]) => {
    setTimelines(prev => prev.map(tl => {
      if (!timelineIdsToPublish.includes(tl.id)) return tl;
      // Defense-in-depth: re-check readiness here too, in case state
      // shifted between opening the modal and confirming.
      const tlTasks = tasks.filter(t => t.timelineId === tl.id);
      const readiness = getTimelineReadiness(tl, tlTasks, activeWorkspace);
      if (!readiness.ready) return tl;
      return { ...tl, status: 'published' };
    }));
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

  return (
    <div id="emgram-planner-app" className="flex h-screen w-screen overflow-hidden bg-white text-neutral-900 font-sans antialiased">
      {/* LEFT PRODUCT RAIL NAV (~60px) */}
      <ProductNav onOpenSettings={() => setIsSettingsOpen(true)} />

      {/* MAIN VIEW AREA */}
      <div className="flex-1 flex flex-col min-w-0 h-full overflow-hidden">
        {/* HEADER (56px) with Workspace Switcher, Planning Window, View Mode Switcher */}
        <Header
          workspaces={workspaces}
          activeWorkspace={activeWorkspace}
          onSelectWorkspace={handleSelectWorkspace}
          onCreateWorkspace={handleCreateWorkspace}
          onRenameWorkspace={handleRenameWorkspace}
          onDeleteWorkspace={handleDeleteWorkspace}
          onOpenWorkspaceSettings={() => setIsWorkspaceSettingsOpen(true)}
        />

        {/* Workspace Body: Agent Roster Rail + Board/Grid + Backlog */}
        <div className="flex-1 flex min-h-0 overflow-hidden">
          {/* AGENT ROSTER RAIL (~260px) — Plan view only. Schedule view's
              own Grid already shows agent identity per row, plus an
              Agents popover for visibility/search/add, so the rail would
              be pure duplication there. */}
          {viewMode === 'plan' && (
            <AgentRosterRail
              agents={agentsInActiveWs}
              timelines={timelinesInActiveWs}
              tasks={tasks}
              activeDate={activeDay}
              activeAgentId={activeAgentId}
              focusedAgentId={focusedAgentId}
              onSelectAgent={(agentId) => {
                setActiveAgentId(agentId);
                // Find timeline for this agent on activeDay
                const tl = timelines.find(t => t.workspaceId === activeWorkspaceId && t.agentId === agentId && t.plannedDate === activeDay);
                if (tl) setActiveTimelineId(tl.id);
              }}
              onFocusAgent={(agentId) => {
                setFocusedAgentId(prev => prev === agentId ? null : agentId);
                if (viewMode !== 'plan') setViewMode('plan');
              }}
              onToggleAgentVisibility={handleToggleAgentVisibility}
              onEditAgent={handleOpenEditAgentModal}
              onShowAllAgents={handleShowAllAgents}
              onHideAllAgents={handleHideAllAgents}
              onOpenAddAgentModal={handleOpenAddAgentModal}
              onDropTaskOnAgent={handleDropTaskOnAgent}
            />
          )}

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

      {/* Component Sheet & Deliverables Modal (§11 & §8) */}
      <ComponentSheetModal
        isOpen={isComponentSheetOpen}
        onClose={() => setIsComponentSheetOpen(false)}
        onSelectScenario={handleSelectScenario}
      />
    </div>
  );
}
