import { Agent, Timeline, Task } from '../types';
import { AGENT_PALETTE } from '../data/initialData';

export interface AgentDayLoad {
  timeline: Timeline | undefined;
  tasks: Task[];
  taskCount: number;
  totalMinutes: number;
  hoursFormatted: string; // e.g., "5h" or "9.5h" or "9h 30m"
  capacityHours: number;
  loadRatio: number; // e.g. 0.625 or 1.18
  isOverCapacity: boolean;
  overCapacityReason?: string;
  isBlocked: boolean;
  blockedReason?: string;
  blockedCount: number;
  isPublished: boolean;
}

export function formatMinutesHuman(totalMin: number): string {
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

export function calculateAgentDayLoad(
  agent: Agent,
  date: string,
  timelines: Timeline[],
  tasks: Task[]
): AgentDayLoad {
  const timeline = timelines.find(
    t => t.agentId === agent.id && t.plannedDate === date && t.workspaceId === agent.workspaceId
  );

  const capacityHours = agent.dailyCapacityHours || 8;

  if (!timeline) {
    return {
      timeline: undefined,
      tasks: [],
      taskCount: 0,
      totalMinutes: 0,
      hoursFormatted: '0h',
      capacityHours,
      loadRatio: 0,
      isOverCapacity: false,
      isBlocked: false,
      blockedCount: 0,
      isPublished: false,
    };
  }

  const timelineTasks = tasks
    .filter(t => t.timelineId === timeline.id)
    .sort((a, b) => a.seq - b.seq);

  const totalMinutes = timelineTasks.reduce((sum, t) => sum + (t.duration || 0), 0);
  const capacityMinutes = capacityHours * 60;
  const isOverCapacity = totalMinutes > capacityMinutes;
  const loadRatio = capacityMinutes > 0 ? totalMinutes / capacityMinutes : 0;

  const blockedTasks = timelineTasks.filter(t => t.status === 'needs_info');
  const blockedTask = blockedTasks[0];
  const isBlocked = blockedTasks.length > 0;
  const blockedCount = blockedTasks.length;
  const blockedReason = blockedTask
    ? (blockedTask.needsInfoReason || `Step #${blockedTask.seq} needs information`)
    : undefined;

  const hoursFormatted = formatMinutesHuman(totalMinutes);
  const overCapacityReason = isOverCapacity
    ? `${agent.name}: ${hoursFormatted} planned, ${capacityHours}h capacity`
    : undefined;

  return {
    timeline,
    tasks: timelineTasks,
    taskCount: timelineTasks.length,
    totalMinutes,
    hoursFormatted,
    capacityHours,
    loadRatio,
    isOverCapacity,
    overCapacityReason,
    isBlocked,
    blockedReason,
    blockedCount,
    isPublished: timeline.status === 'published',
  };
}

export function calculateAgentRangeLoad(
  agent: Agent,
  visibleDates: string[],
  timelines: Timeline[],
  tasks: Task[]
): {
  plannedHoursText: string;
  totalCapacityText: string;
  loadLabel: string; // e.g. "18h / 40h"
  hasBlockedTimeline: boolean;
  hasOverCapacityDay: boolean;
  blockedCount: number;
} {
  let totalPlannedMinutes = 0;
  let hasBlocked = false;
  let hasOver = false;
  let blockedCount = 0;

  visibleDates.forEach(date => {
    const dayLoad = calculateAgentDayLoad(agent, date, timelines, tasks);
    totalPlannedMinutes += dayLoad.totalMinutes;
    if (dayLoad.isBlocked) {
      hasBlocked = true;
      blockedCount++;
    }
    if (dayLoad.isOverCapacity) {
      hasOver = true;
    }
  });

  const totalCapacityHours = visibleDates.length * (agent.dailyCapacityHours || 8);
  const plannedHoursNumber = Math.round((totalPlannedMinutes / 60) * 10) / 10;
  const plannedHoursText = Number.isInteger(plannedHoursNumber) 
    ? `${plannedHoursNumber}h` 
    : `${plannedHoursNumber.toFixed(1)}h`;
  const totalCapacityText = `${totalCapacityHours}h`;

  return {
    plannedHoursText,
    totalCapacityText,
    loadLabel: `${plannedHoursText} / ${totalCapacityText}`,
    hasBlockedTimeline: hasBlocked,
    hasOverCapacityDay: hasOver,
    blockedCount,
  };
}

export interface AgentCapacityRow {
  agent: Agent;
  plannedHours: number;
  capacityHours: number;
  openHours: number; // capacityHours - plannedHours; negative means over capacity
}

export interface WorkspaceCapacitySummary {
  totalCapacityHours: number;
  totalPlannedHours: number;
  openCapacityHours: number;
  utilizationPct: number; // 0-100+, rounded
  overCapacityAgentDays: number;
  perAgent: AgentCapacityRow[]; // sorted by openHours, most available first
}

/**
 * Aggregates capacity across a set of agents for a date range — the
 * workspace-level rollup behind the Backlog panel's "Plan Health" view.
 * Reuses calculateAgentDayLoad per agent/day so it stays in lockstep with
 * every other capacity signal in the app (Day Board, Schedule Grid).
 */
export function calculateWorkspaceCapacitySummary(
  agents: Agent[],
  visibleDates: string[],
  timelines: Timeline[],
  tasks: Task[]
): WorkspaceCapacitySummary {
  const perAgent: AgentCapacityRow[] = [];
  let totalCapacityMinutes = 0;
  let totalPlannedMinutes = 0;
  let overCapacityAgentDays = 0;

  agents.forEach(agent => {
    let plannedMinutes = 0;
    visibleDates.forEach(date => {
      const dayLoad = calculateAgentDayLoad(agent, date, timelines, tasks);
      plannedMinutes += dayLoad.totalMinutes;
      if (dayLoad.isOverCapacity) overCapacityAgentDays++;
    });

    const capacityMinutes = visibleDates.length * (agent.dailyCapacityHours || 8) * 60;
    totalCapacityMinutes += capacityMinutes;
    totalPlannedMinutes += plannedMinutes;

    perAgent.push({
      agent,
      plannedHours: Math.round((plannedMinutes / 60) * 10) / 10,
      capacityHours: Math.round((capacityMinutes / 60) * 10) / 10,
      openHours: Math.round(((capacityMinutes - plannedMinutes) / 60) * 10) / 10,
    });
  });

  perAgent.sort((a, b) => b.openHours - a.openHours);

  return {
    totalCapacityHours: Math.round((totalCapacityMinutes / 60) * 10) / 10,
    totalPlannedHours: Math.round((totalPlannedMinutes / 60) * 10) / 10,
    openCapacityHours: Math.round(((totalCapacityMinutes - totalPlannedMinutes) / 60) * 10) / 10,
    utilizationPct: totalCapacityMinutes > 0 ? Math.round((totalPlannedMinutes / totalCapacityMinutes) * 100) : 0,
    overCapacityAgentDays,
    perAgent,
  };
}

export function getNextAgentColor(existingAgents: Agent[]): string {
  const usedColors = new Set(existingAgents.map(a => a.color.toLowerCase()));
  const available = AGENT_PALETTE.find(p => !usedColors.has(p.hex.toLowerCase()));
  if (available) return available.hex;
  // If all used, wrap around
  return AGENT_PALETTE[existingAgents.length % AGENT_PALETTE.length].hex;
}
