import { Task, Timeline, Workspace } from '../types';
import { isDateOutOfWindow } from './dateUtils';

export function parseTimeToMinutes(timeStr: string): number | null {
  if (!timeStr) return null;
  const parts = timeStr.split(':').map(Number);
  if (parts.length < 2 || isNaN(parts[0]) || isNaN(parts[1])) return null;
  return parts[0] * 60 + parts[1];
}

export function formatMinutesToTime(totalMin: number): string {
  const norm = ((totalMin % 1440) + 1440) % 1440;
  const h = Math.floor(norm / 60);
  const m = norm % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

export const DEFAULT_TIMELINE_START_TIME = '08:00';

export interface LandingResult {
  duration: number;
  assignee: string;
  status: 'planned' | 'needs_info';
  needsInfoReason?: string;
}

/**
 * Determines duration/assignee for a task landing into a timeline.
 * Start times are no longer computed per-drop: they are always derived
 * deterministically by recomputeTimelineTaskTimes() from the timeline's
 * startTime plus the cumulative duration of steps above. This means a
 * dropped/reordered task can never be "missing a start time" or "overlap
 * the next step" -- those states are now structurally impossible.
 */
export function calculateTaskLanding(task: Task, timeline: Timeline): LandingResult {
  const duration = task.duration || 30;
  const assignee = task.assignee?.trim() ? task.assignee : (timeline.assignee || '');
  return {
    duration,
    assignee,
    status: 'planned',
    needsInfoReason: undefined,
  };
}

/**
 * Recomputes every task's planned_start in a timeline, cascading from the
 * timeline's own startTime. Call this after ANY mutation that changes a
 * timeline's task order, membership, or durations (add, move, reorder,
 * delete, or edit-duration) to keep planned_start authoritative and in
 * sync. Tasks are assumed to already be in the desired order (by seq).
 */
export function recomputeTimelineTaskTimes(timeline: Timeline, orderedTasks: Task[]): Task[] {
  const startMin = parseTimeToMinutes(timeline.startTime) ?? parseTimeToMinutes(DEFAULT_TIMELINE_START_TIME)!;
  let cursor = startMin;
  return orderedTasks.map((t, idx) => {
    const duration = t.duration || 30;
    const planned_start = formatMinutesToTime(cursor);
    cursor += duration;
    return {
      ...t,
      seq: idx + 1,
      planned_start,
      duration,
      status: 'planned' as const,
      needsInfoReason: undefined,
    };
  });
}

export interface TimelineReadiness {
  ready: boolean;
  reasons: string[]; // human-readable blocking reasons; empty when ready
}

/**
 * Single source of truth for whether a timeline can be published.
 * Used by the per-column Publish control, Focus mode's Publish control,
 * and the bulk "Publish day" flow so all three enforce identical rules:
 *   - the timeline must have at least one step
 *   - the timeline's planned date must fall inside the workspace's
 *     planning window
 *   - no step may be in a needs_info state
 */
export function getTimelineReadiness(
  timeline: Timeline,
  timelineTasks: Task[],
  workspace: Workspace | null | undefined
): TimelineReadiness {
  const reasons: string[] = [];

  if (timelineTasks.length === 0) {
    reasons.push('This timeline has no steps yet.');
  }

  if (workspace && isDateOutOfWindow(timeline.plannedDate, workspace.planningWindowStart, workspace.planningWindowEnd)) {
    reasons.push(`Planned date (${timeline.plannedDate}) is outside the current planning window.`);
  }

  const blockedTask = timelineTasks.find(t => t.status === 'needs_info');
  if (blockedTask) {
    reasons.push(`Step #${blockedTask.seq} needs info: "${blockedTask.needsInfoReason || blockedTask.title}"`);
  }

  return { ready: reasons.length === 0, reasons };
}
