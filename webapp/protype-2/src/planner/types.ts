export type TimelineStatus = 'draft' | 'published';

export type TaskPlanningStatus = 'planned' | 'needs_info';

export type ViewMode = 'plan' | 'schedule';

export type AgentKind = 'person' | 'ai';

export interface Agent {
  id: string;
  workspaceId: string;
  name: string;
  kind: AgentKind;
  color: string; // From preset palette
  dailyCapacityHours: number; // e.g. 8
  isVisible: boolean; // For show/hide roster toggle
  modelId?: string; // AI agents only: which model in settings.models it runs on
}

/**
 * Token pricing for a model an AI agent can be assigned to. Rates are USD
 * per 1M tokens, matching how model providers publish pricing.
 */
export interface ModelPricing {
  id: string;
  label: string;
  inputPer1M: number;
  outputPer1M: number;
  isCustom?: boolean;
}

/**
 * Global rate settings — what things cost, independent of any one project.
 * Humans cost hours x rate; AI agents cost tokens x price, where token
 * volume comes from the *workspace's* throughput assumptions (the plan
 * stores durations, not tokens).
 */
export interface AppSettings {
  currencySymbol: string;
  humanHourlyRate: number; // applies to every kind === 'person' agent
  models: ModelPricing[];
}

/** The per-workspace half of the cost inputs. */
export interface Throughput {
  inputTokensPerMinute: number;
  outputTokensPerMinute: number;
}

export interface Workspace {
  id: string;
  name: string;
  createdAt: string;
  planningWindowStart: string; // YYYY-MM-DD
  planningWindowEnd: string;   // YYYY-MM-DD
  // AI throughput assumptions live per workspace: how token-intensive this
  // particular body of work is. Rates (what a token costs) stay global.
  inputTokensPerMinute: number;
  outputTokensPerMinute: number;
}

export interface Timeline {
  id: string;
  workspaceId: string;
  agentId: string; // Links timeline to agent (one agent, one timeline, per day)
  name: string;
  plannedDate: string; // YYYY-MM-DD
  assignee: string; // Default assignee name for tasks in this timeline
  status: TimelineStatus;
  startTime: string; // e.g. "08:00" - anchor time; all task starts cascade from this
}

export interface Task {
  id: string;
  workspaceId: string;
  timelineId: string | null; // null = in unplanned backlog
  title: string;
  seq: number; // 1, 2, 3... within its timeline (or order in backlog)
  planned_start: string; // e.g., "09:00"
  duration: number; // minutes
  assignee?: string; // optional; inherits timeline's if unset or blank
  notes: string;
  status: TaskPlanningStatus;
  needsInfoReason?: string; // Optional explanation of what is missing
}

export type SelectedEntity = 
  | { type: 'timeline'; id: string }
  | { type: 'task'; id: string }
  | { type: 'agent'; id: string }
  | null;

export type ModalEntity =
  | { type: 'task'; task: Task; prevTaskEnd?: string | null; nextTaskStart?: string | null; timelineStatus?: TimelineStatus; timeline?: Timeline | null; totalTasksInTimeline?: number }
  | { type: 'timeline'; timeline: Timeline; tasksInTimeline: Task[]; planningWindowStart?: string; planningWindowEnd?: string }
  | { type: 'agent'; agent?: Agent | null; isNew?: boolean }
  | { type: 'bulk_publish_day'; date: string; outcomes: { timeline: Timeline; agent?: Agent; status: 'ready' | 'blocked' | 'already_published'; reason?: string; taskCount: number }[] }
  | { type: 'publish_confirm'; timeline: Timeline; agentName: string };
