// PUX-1 / PUX-4 — where a job sits on the board, and one word for how far
// along its planning is. Pure, no imports: built from the board payload the
// planner already holds, never a new request.

export interface PlacementTask {
  timelineId: string | null;
  workItemId?: string;
  /** Steps this slot covers (BLK-1 cards); absent = 1. */
  jobStepCount?: number;
  planned_start: string;
}

export interface PlacementTimeline {
  id: string;
  plannedDate: string;
  agentId: string;
  status: 'draft' | 'published';
}

export interface PlacementAgent {
  id: string;
  name: string;
}

export interface Placement {
  timelineId: string;
  date: string;
  agentName: string;
  /** Earliest start among this job's slots on that day. */
  start: string;
  steps: number;
  published: boolean;
}

export function jobPlacements(
  workItemId: string,
  tasks: ReadonlyArray<PlacementTask>,
  timelines: ReadonlyArray<PlacementTimeline>,
  agents: ReadonlyArray<PlacementAgent>,
): Placement[] {
  const byTimeline = new Map<string, Placement>();
  for (const task of tasks) {
    if (task.workItemId !== workItemId || !task.timelineId) continue;
    const tl = timelines.find((x) => x.id === task.timelineId);
    if (!tl) continue;
    const steps = task.jobStepCount ?? 1;
    const existing = byTimeline.get(tl.id);
    if (existing) {
      existing.steps += steps;
      if (task.planned_start && (!existing.start || task.planned_start < existing.start)) existing.start = task.planned_start;
    } else {
      byTimeline.set(tl.id, {
        timelineId: tl.id,
        date: tl.plannedDate,
        agentName: agents.find((a) => a.id === tl.agentId)?.name ?? 'Unassigned',
        start: task.planned_start,
        steps,
        published: tl.status === 'published',
      });
    }
  }
  return [...byTimeline.values()].sort((a, b) => (a.date + a.start).localeCompare(b.date + b.start));
}

/** Every job's placements at once (the Jobs column needs them all). */
export function placementsByJob(
  tasks: ReadonlyArray<PlacementTask>,
  timelines: ReadonlyArray<PlacementTimeline>,
  agents: ReadonlyArray<PlacementAgent>,
): Map<string, Placement[]> {
  const ids = new Set<string>();
  for (const task of tasks) if (task.workItemId && task.timelineId) ids.add(task.workItemId);
  const out = new Map<string, Placement[]>();
  for (const id of ids) out.set(id, jobPlacements(id, tasks, timelines, agents));
  return out;
}

export type JobPlanKind = 'unscheduled' | 'partly' | 'scheduled' | 'live' | 'done' | 'cancelled';

export interface JobPlanStatus {
  kind: JobPlanKind;
  label: string;
  /** Steps not yet on any day. */
  left: number;
}

export function jobPlanStatus(job: {status: string; totalSteps: number}, placements: ReadonlyArray<Placement>): JobPlanStatus {
  if (job.status === 'completed') return {kind: 'done', label: 'Done', left: 0};
  if (job.status === 'cancelled') return {kind: 'cancelled', label: 'Cancelled', left: 0};
  const placed = placements.reduce((n, p) => n + p.steps, 0);
  const left = Math.max(0, job.totalSteps - placed);
  if (placed === 0) return {kind: 'unscheduled', label: 'Unscheduled', left};
  if (left > 0) return {kind: 'partly', label: `Partly · ${left} left`, left};
  if (placements.every((p) => p.published)) return {kind: 'live', label: 'Live', left: 0};
  return {kind: 'scheduled', label: 'Scheduled', left: 0};
}
