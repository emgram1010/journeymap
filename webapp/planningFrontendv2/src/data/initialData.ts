import { Workspace, Timeline, Task, Agent, AppSettings, ModelPricing } from '../types';

/**
 * Seed model catalog. Rates are USD per 1M tokens as published by the
 * provider; every field is editable in Settings, and users can add their
 * own entries for models not listed here.
 */
export const DEFAULT_MODELS: ModelPricing[] = [
  { id: 'claude-fable-5-1', label: 'Claude Fable 5.1', inputPer1M: 10, outputPer1M: 50 },
  { id: 'claude-opus-5', label: 'Claude Opus 5', inputPer1M: 5, outputPer1M: 25 },
  { id: 'claude-sonnet-5', label: 'Claude Sonnet 5', inputPer1M: 2, outputPer1M: 10 },
  { id: 'claude-haiku-4-5', label: 'Claude Haiku 4.5', inputPer1M: 1, outputPer1M: 5 },
];

export const DEFAULT_SETTINGS: AppSettings = {
  currencySymbol: '$',
  // Left at 0 so the app never shows an invented rate as if it were real —
  // Plan Health prompts to set it.
  humanHourlyRate: 0,
  models: DEFAULT_MODELS,
};

// Throughput defaults for a workspace that doesn't specify its own.
export const DEFAULT_INPUT_TOKENS_PER_MINUTE = 2000;
export const DEFAULT_OUTPUT_TOKENS_PER_MINUTE = 500;

export const AGENT_PALETTE = [
  { id: 'slate', name: 'Slate Gray', hex: '#475569', lightBg: '#f1f5f9' },
  { id: 'teal', name: 'Sage Teal', hex: '#0d9488', lightBg: '#f0fdfa' },
  { id: 'terracotta', name: 'Terracotta', hex: '#c2410c', lightBg: '#fff7ed' },
  { id: 'amber', name: 'Ochre Bronze', hex: '#b45309', lightBg: '#fffbeb' },
  { id: 'violet', name: 'Heather Violet', hex: '#7c3aed', lightBg: '#f5f3ff' },
  { id: 'emerald', name: 'Forest Moss', hex: '#059669', lightBg: '#ecfdf5' },
  { id: 'sky', name: 'Steel Blue', hex: '#0284c7', lightBg: '#f0f9ff' },
  { id: 'rosewood', name: 'Rosewood Plum', hex: '#9f1239', lightBg: '#fff1f2' },
];

export const INITIAL_AGENTS: Agent[] = [
  {
    id: 'agent-marcus',
    workspaceId: 'ws-apex',
    name: 'Marcus Vance',
    kind: 'person',
    color: '#0284c7', // Steel Blue
    dailyCapacityHours: 8,
    isVisible: true,
  },
  {
    id: 'agent-kavita',
    workspaceId: 'ws-apex',
    name: 'Kavita Patel',
    kind: 'person',
    color: '#0d9488', // Sage Teal
    dailyCapacityHours: 8,
    isVisible: true,
  },
  {
    id: 'agent-intake',
    workspaceId: 'ws-apex',
    name: 'Intake bot',
    kind: 'ai',
    color: '#7c3aed', // Heather Violet
    dailyCapacityHours: 8,
    isVisible: true,
  },
  {
    id: 'agent-elena',
    workspaceId: 'ws-apex',
    name: 'Elena Rostova',
    kind: 'person',
    color: '#c2410c', // Terracotta
    dailyCapacityHours: 8,
    isVisible: true,
  },
  {
    id: 'agent-batch',
    workspaceId: 'ws-apex',
    name: 'Batch reconciler',
    kind: 'ai',
    color: '#b45309', // Ochre Bronze
    dailyCapacityHours: 8,
    isVisible: true,
  },
  {
    id: 'agent-tariq',
    workspaceId: 'ws-apex',
    name: 'Tariq Al-Mansoor',
    kind: 'person',
    color: '#059669', // Forest Moss
    dailyCapacityHours: 8,
    isVisible: true,
  },
  {
    id: 'agent-sophie',
    workspaceId: 'ws-apex',
    name: 'Sophie Laurent',
    kind: 'person',
    color: '#9f1239', // Rosewood Plum
    dailyCapacityHours: 8,
    isVisible: true,
  },
  {
    id: 'agent-validator',
    workspaceId: 'ws-apex',
    name: 'Data validator bot',
    kind: 'ai',
    color: '#475569', // Slate Gray
    dailyCapacityHours: 8,
    isVisible: true,
  },
  {
    id: 'agent-samira',
    workspaceId: 'ws-apex',
    name: 'Samira Khan',
    kind: 'person',
    color: '#0284c7', // Steel Blue
    dailyCapacityHours: 8,
    isVisible: true,
  },
  {
    id: 'agent-audit',
    workspaceId: 'ws-apex',
    name: 'Compliance audit bot',
    kind: 'ai',
    color: '#7c3aed', // Heather Violet
    dailyCapacityHours: 8,
    isVisible: true,
  },
  // Meridian agent
  {
    id: 'agent-david',
    workspaceId: 'ws-meridian',
    name: 'David Chen',
    kind: 'person',
    color: '#475569',
    dailyCapacityHours: 8,
    isVisible: true,
  },
];

export const INITIAL_WORKSPACES: Workspace[] = [
  {
    id: 'ws-apex',
    name: 'Apex Health Systems — Cutover',
    createdAt: '2026-09-15',
    planningWindowStart: '2026-10-12',
    planningWindowEnd: '2026-10-25',
    inputTokensPerMinute: 2000,
    outputTokensPerMinute: 500,
  },
  {
    id: 'ws-meridian',
    name: 'Meridian Global ERP Rollout',
    createdAt: '2026-09-18',
    planningWindowStart: '2026-11-01',
    planningWindowEnd: '2026-11-14',
    inputTokensPerMinute: 2000,
    outputTokensPerMinute: 500,
  },
  {
    id: 'ws-fintech',
    name: 'Northstar Settlement Migration',
    createdAt: '2026-09-19',
    planningWindowStart: '2026-10-15',
    planningWindowEnd: '2026-10-28',
    inputTokensPerMinute: 2000,
    outputTokensPerMinute: 500,
  },
];

export const INITIAL_TIMELINES: Timeline[] = [
  // Day 1 (2026-10-12) - Marcus Vance
  {
    id: 'tl-marcus-oct12',
    workspaceId: 'ws-apex',
    agentId: 'agent-marcus',
    name: 'Mon 12 — Marcus Vance',
    plannedDate: '2026-10-12',
    assignee: 'Marcus Vance',
    status: 'draft',
    startTime: '08:00',
  },
  // Day 2 (2026-10-13) - Marcus Vance (5h / 8h Draft)
  {
    id: 'tl-marcus-oct13',
    workspaceId: 'ws-apex',
    agentId: 'agent-marcus',
    name: 'Tue 13 — Marcus Vance',
    plannedDate: '2026-10-13',
    assignee: 'Marcus Vance',
    status: 'draft',
    startTime: '08:00',
  },
  // Day 2 (2026-10-13) - Kavita Patel (9h 30m / 8h ⚠ Over capacity + blocked)
  {
    id: 'tl-kavita-oct13',
    workspaceId: 'ws-apex',
    agentId: 'agent-kavita',
    name: 'Tue 13 — Kavita Patel',
    plannedDate: '2026-10-13',
    assignee: 'Kavita Patel',
    status: 'draft',
    startTime: '08:00',
  },
  // Day 2 (2026-10-13) - Intake bot (2h / 8h Published)
  {
    id: 'tl-intake-oct13',
    workspaceId: 'ws-apex',
    agentId: 'agent-intake',
    name: 'Tue 13 — Intake bot',
    plannedDate: '2026-10-13',
    assignee: 'Intake bot',
    status: 'published',
    startTime: '08:00',
  },
  // Day 2 (2026-10-13) - Elena Rostova (4h / 8h Draft)
  {
    id: 'tl-elena-oct13',
    workspaceId: 'ws-apex',
    agentId: 'agent-elena',
    name: 'Tue 13 — Elena Rostova',
    plannedDate: '2026-10-13',
    assignee: 'Elena Rostova',
    status: 'draft',
    startTime: '08:00',
  },
  // Day 2 (2026-10-13) - Batch reconciler (3h / 8h Draft)
  {
    id: 'tl-batch-oct13',
    workspaceId: 'ws-apex',
    agentId: 'agent-batch',
    name: 'Tue 13 — Batch reconciler',
    plannedDate: '2026-10-13',
    assignee: 'Batch reconciler',
    status: 'draft',
    startTime: '08:00',
  },
  // Day 2 (2026-10-13) - Tariq Al-Mansoor (5h / 8h Draft)
  {
    id: 'tl-tariq-oct13',
    workspaceId: 'ws-apex',
    agentId: 'agent-tariq',
    name: 'Tue 13 — Tariq Al-Mansoor',
    plannedDate: '2026-10-13',
    assignee: 'Tariq Al-Mansoor',
    status: 'draft',
    startTime: '08:00',
  },
  // Day 3 (2026-10-14) - Elena Rostova (Published)
  {
    id: 'tl-elena-oct14',
    workspaceId: 'ws-apex',
    agentId: 'agent-elena',
    name: 'Wed 14 — Elena Rostova',
    plannedDate: '2026-10-14',
    assignee: 'Elena Rostova',
    status: 'published',
    startTime: '08:00',
  },
  // Day 4 (2026-10-15) - Batch reconciler (Draft)
  {
    id: 'tl-batch-oct15',
    workspaceId: 'ws-apex',
    agentId: 'agent-batch',
    name: 'Thu 15 — Batch reconciler',
    plannedDate: '2026-10-15',
    assignee: 'Batch reconciler',
    status: 'draft',
    startTime: '08:00',
  },
  // Meridian timeline
  {
    id: 'tl-meridian-1',
    workspaceId: 'ws-meridian',
    agentId: 'agent-david',
    name: 'Mon 02 — David Chen',
    plannedDate: '2026-11-02',
    assignee: 'David Chen',
    status: 'draft',
    startTime: '08:00',
  },
];

export const INITIAL_TASKS: Task[] = [
  // Mon 12 - Marcus Vance (tl-marcus-oct12)
  {
    id: 'task-101',
    workspaceId: 'ws-apex',
    timelineId: 'tl-marcus-oct12',
    title: 'Initiate legacy database read-only snapshot lock',
    seq: 1,
    planned_start: '08:00',
    duration: 30,
    assignee: 'Marcus Vance',
    notes: 'Confirm all write connections are severed before verifying checksums.',
    status: 'planned',
  },
  {
    id: 'task-102',
    workspaceId: 'ws-apex',
    timelineId: 'tl-marcus-oct12',
    title: 'Extract cryptographic hash table & cross-check source schema',
    seq: 2,
    planned_start: '08:30',
    duration: 45,
    assignee: 'Marcus Vance',
    notes: 'Verify table partitions for patient ledger volume.',
    status: 'planned',
  },

  // Tue 13 - Marcus Vance (tl-marcus-oct13): 5h / 8h Draft (300 min)
  {
    id: 'task-m-201',
    workspaceId: 'ws-apex',
    timelineId: 'tl-marcus-oct13',
    title: 'Baseline schema compilation & foreign key verification',
    seq: 1,
    planned_start: '08:30',
    duration: 45,
    assignee: 'Marcus Vance',
    notes: 'Audit constraints on billing ledger tables.',
    status: 'planned',
  },
  {
    id: 'task-m-202',
    workspaceId: 'ws-apex',
    timelineId: 'tl-marcus-oct13',
    title: 'Mount mock webhook dispatchers for partner clearinghouses',
    seq: 2,
    planned_start: '09:15',
    duration: 60,
    assignee: 'Marcus Vance',
    notes: 'Ensure clearinghouse endpoints operate in sandbox mode.',
    status: 'planned',
  },
  {
    id: 'task-m-203',
    workspaceId: 'ws-apex',
    timelineId: 'tl-marcus-oct13',
    title: 'Execute baseline integrity audit across tenant rows',
    seq: 3,
    planned_start: '10:15',
    duration: 75,
    assignee: 'Marcus Vance',
    notes: 'Run automated checksum validator script against target schema.',
    status: 'planned',
  },
  {
    id: 'task-m-204',
    workspaceId: 'ws-apex',
    timelineId: 'tl-marcus-oct13',
    title: 'Run delta sync dry run against hot-standby replicas',
    seq: 4,
    planned_start: '11:30',
    duration: 120,
    assignee: 'Marcus Vance',
    notes: 'Measure write latency on replica shards.',
    status: 'planned',
  },

  // Tue 13 - Kavita Patel (tl-kavita-oct13): 9h 30m / 8h (570 min) ⚠ OVER CAPACITY + 1 BLOCKED TASK
  {
    id: 'task-k-201',
    workspaceId: 'ws-apex',
    timelineId: 'tl-kavita-oct13',
    title: 'Ingest staging payload into isolated staging cluster',
    seq: 1,
    planned_start: '09:00',
    duration: 90,
    assignee: 'Kavita Patel',
    notes: 'Requires staging cluster node provisioning confirmation from infrastructure team.',
    status: 'needs_info',
    needsInfoReason: 'Awaiting staging node sizing specs from infra team',
  },
  {
    id: 'task-k-202',
    workspaceId: 'ws-apex',
    timelineId: 'tl-kavita-oct13',
    title: 'Simulate high-throughput 5,000 tx/sec reconciliation load',
    seq: 2,
    planned_start: '10:30',
    duration: 180,
    assignee: 'Kavita Patel',
    notes: 'Stress test partition buffers and queue backlog tolerance.',
    status: 'planned',
  },
  {
    id: 'task-k-203',
    workspaceId: 'ws-apex',
    timelineId: 'tl-kavita-oct13',
    title: 'Run end-to-end failover drill on primary Redis sentinel nodes',
    seq: 3,
    planned_start: '13:30',
    duration: 180,
    assignee: 'Kavita Patel',
    notes: 'Trigger controlled node failure and benchmark cluster election.',
    status: 'planned',
  },
  {
    id: 'task-k-204',
    workspaceId: 'ws-apex',
    timelineId: 'tl-kavita-oct13',
    title: 'Compile post-drill latency reports and SLA variance tables',
    seq: 4,
    planned_start: '16:30',
    duration: 120,
    assignee: 'Kavita Patel',
    notes: 'Export P99 response telemetry.',
    status: 'planned',
  },

  // Tue 13 - Intake bot (tl-intake-oct13): 2h / 8h Published (120 min)
  {
    id: 'task-i-201',
    workspaceId: 'ws-apex',
    timelineId: 'tl-intake-oct13',
    title: 'Verify API token rotation across inbound webhooks',
    seq: 1,
    planned_start: '07:00',
    duration: 30,
    assignee: 'Intake bot',
    notes: 'Automated secret verification sequence.',
    status: 'planned',
  },
  {
    id: 'task-i-202',
    workspaceId: 'ws-apex',
    timelineId: 'tl-intake-oct13',
    title: 'Pre-warm cache pools for partner insurance endpoints',
    seq: 2,
    planned_start: '07:30',
    duration: 90,
    assignee: 'Intake bot',
    notes: 'Cold cache mitigation sequence.',
    status: 'planned',
  },

  // Tue 13 - Elena Rostova (tl-elena-oct13): 4h / 8h Draft (240 min)
  {
    id: 'task-e-201',
    workspaceId: 'ws-apex',
    timelineId: 'tl-elena-oct13',
    title: 'Validate patient record encryption certificates',
    seq: 1,
    planned_start: '09:00',
    duration: 120,
    assignee: 'Elena Rostova',
    notes: 'Ensure TLS 1.3 compliance on all patient-facing ports.',
    status: 'planned',
  },
  {
    id: 'task-e-202',
    workspaceId: 'ws-apex',
    timelineId: 'tl-elena-oct13',
    title: 'Conduct HIPAA compliance audit on intermediate tables',
    seq: 2,
    planned_start: '11:00',
    duration: 120,
    assignee: 'Elena Rostova',
    notes: 'Verify PII redaction rules.',
    status: 'planned',
  },

  // Tue 13 - Batch reconciler (tl-batch-oct13): 3h / 8h Draft (180 min)
  {
    id: 'task-b-201',
    workspaceId: 'ws-apex',
    timelineId: 'tl-batch-oct13',
    title: 'Execute shadow ledger transaction matching run',
    seq: 1,
    planned_start: '08:00',
    duration: 90,
    assignee: 'Batch reconciler',
    notes: 'Compare ledger entries against bank settlement reports.',
    status: 'planned',
  },
  {
    id: 'task-b-202',
    workspaceId: 'ws-apex',
    timelineId: 'tl-batch-oct13',
    title: 'Generate discrepancy audit delta summary',
    seq: 2,
    planned_start: '09:30',
    duration: 90,
    assignee: 'Batch reconciler',
    notes: 'Format mismatch breakdown for finance team review.',
    status: 'planned',
  },

  // Tue 13 - Tariq Al-Mansoor (tl-tariq-oct13): 5h / 8h Draft (300 min)
  {
    id: 'task-t-201',
    workspaceId: 'ws-apex',
    timelineId: 'tl-tariq-oct13',
    title: 'Configure border gateway protocol routing rules',
    seq: 1,
    planned_start: '08:30',
    duration: 150,
    assignee: 'Tariq Al-Mansoor',
    notes: 'Prepare multi-homed egress route failover tables.',
    status: 'planned',
  },
  {
    id: 'task-t-202',
    workspaceId: 'ws-apex',
    timelineId: 'tl-tariq-oct13',
    title: 'Verify redundant uplink switch heartbeats',
    seq: 2,
    planned_start: '11:00',
    duration: 150,
    assignee: 'Tariq Al-Mansoor',
    notes: 'Test dual power supply switchovers under artificial load.',
    status: 'planned',
  },

  // Wed 14 - Elena Rostova (tl-elena-oct14): Published
  {
    id: 'task-301',
    workspaceId: 'ws-apex',
    timelineId: 'tl-elena-oct14',
    title: 'Conduct executive stakeholders readiness walkthrough',
    seq: 1,
    planned_start: '13:00',
    duration: 45,
    assignee: 'Elena Rostova',
    notes: 'Review runbook signoffs with VP Operations.',
    status: 'planned',
  },
  {
    id: 'task-302',
    workspaceId: 'ws-apex',
    timelineId: 'tl-elena-oct14',
    title: 'Issue final production DNS cutover instruction',
    seq: 2,
    planned_start: '14:00',
    duration: 30,
    assignee: 'Elena Rostova',
    notes: 'Execute TTL switch down to 60 seconds.',
    status: 'planned',
  },

  // Thu 15 - Batch reconciler (tl-batch-oct15): Draft
  {
    id: 'task-401',
    workspaceId: 'ws-apex',
    timelineId: 'tl-batch-oct15',
    title: 'Automated ledger balance checksum verification cycle',
    seq: 1,
    planned_start: '02:00',
    duration: 60,
    assignee: 'Batch reconciler',
    notes: 'Verify 0 balance discrepancies across merchant sub-ledgers.',
    status: 'planned',
  },

  // Backlog tasks for ws-apex (timelineId: null)
  {
    id: 'task-b1',
    workspaceId: 'ws-apex',
    timelineId: null,
    title: 'Secondary cold-standby replication synchronization',
    seq: 1,
    planned_start: '',
    duration: 45,
    assignee: 'Kavita Patel',
    notes: 'Unassigned run step. Pull into Day 1 or Day 2 once storage pool is allocated.',
    status: 'planned',
  },
  {
    id: 'task-b2',
    workspaceId: 'ws-apex',
    timelineId: null,
    title: 'Legacy audit archive tarball upload to immutable glacier',
    seq: 2,
    planned_start: '',
    duration: 60,
    assignee: '',
    notes: 'Pending compliance retention window confirmation.',
    status: 'planned',
  },
  {
    id: 'task-b3',
    workspaceId: 'ws-apex',
    timelineId: null,
    title: 'Decommissioning checklist distribution for legacy hosts',
    seq: 3,
    planned_start: '',
    duration: 30,
    assignee: 'Marcus Vance',
    notes: 'Post-launch cleanup step.',
    status: 'planned',
  },
  {
    id: 'task-b4',
    workspaceId: 'ws-apex',
    timelineId: null,
    title: 'Third-party clearinghouse credential rollover verification',
    seq: 4,
    planned_start: '',
    duration: 45,
    assignee: '',
    notes: 'Can be scheduled during integration dry-run.',
    status: 'planned',
  },

  // Meridian tasks
  {
    id: 'task-m1',
    workspaceId: 'ws-meridian',
    timelineId: 'tl-meridian-1',
    title: 'Compare chart-of-accounts balance definitions against legacy SAP',
    seq: 1,
    planned_start: '09:00',
    duration: 60,
    assignee: 'David Chen',
    notes: 'Double check multi-currency consolidation rules.',
    status: 'planned',
  },
];

const STORAGE_KEYS = {
  WORKSPACES: 'emgram_workspaces_v3',
  AGENTS: 'emgram_agents_v3',
  TIMELINES: 'emgram_timelines_v3',
  TASKS: 'emgram_tasks_v3',
  SETTINGS: 'emgram_settings_v1',
};

export function loadStoredData(): {
  workspaces: Workspace[];
  agents: Agent[];
  timelines: Timeline[];
  tasks: Task[];
  settings: AppSettings;
} {
  try {
    const rawWs = localStorage.getItem(STORAGE_KEYS.WORKSPACES);
    const rawAgents = localStorage.getItem(STORAGE_KEYS.AGENTS);
    const rawTl = localStorage.getItem(STORAGE_KEYS.TIMELINES);
    const rawTasks = localStorage.getItem(STORAGE_KEYS.TASKS);
    const rawSettings = localStorage.getItem(STORAGE_KEYS.SETTINGS);

    const loadedWorkspaces: Workspace[] = rawWs ? JSON.parse(rawWs) : INITIAL_WORKSPACES;
    const loadedAgents: Agent[] = rawAgents ? JSON.parse(rawAgents) : INITIAL_AGENTS;
    const loadedTimelines: Timeline[] = rawTl ? JSON.parse(rawTl) : INITIAL_TIMELINES;
    const loadedTasks: Task[] = rawTasks ? JSON.parse(rawTasks) : INITIAL_TASKS;

    // Merge stored settings over defaults so new fields added later are
    // backfilled rather than coming back undefined from an old payload.
    const storedSettings = rawSettings ? JSON.parse(rawSettings) : null;
    const settings: AppSettings = {
      currencySymbol: storedSettings?.currencySymbol ?? DEFAULT_SETTINGS.currencySymbol,
      humanHourlyRate: storedSettings?.humanHourlyRate ?? DEFAULT_SETTINGS.humanHourlyRate,
      models: storedSettings?.models?.length ? storedSettings.models : DEFAULT_MODELS,
    };

    // Backfill planningWindow, and migrate throughput from the old global
    // settings payload (where it used to live) onto each workspace.
    const sanitizedWorkspaces = loadedWorkspaces.map(ws => ({
      ...ws,
      planningWindowStart: ws.planningWindowStart || '2026-10-12',
      planningWindowEnd: ws.planningWindowEnd || '2026-10-25',
      inputTokensPerMinute:
        ws.inputTokensPerMinute ??
        storedSettings?.inputTokensPerMinute ??
        DEFAULT_INPUT_TOKENS_PER_MINUTE,
      outputTokensPerMinute:
        ws.outputTokensPerMinute ??
        storedSettings?.outputTokensPerMinute ??
        DEFAULT_OUTPUT_TOKENS_PER_MINUTE,
    }));

    return {
      workspaces: sanitizedWorkspaces,
      agents: loadedAgents,
      timelines: loadedTimelines,
      tasks: loadedTasks,
      settings,
    };
  } catch {
    return {
      workspaces: INITIAL_WORKSPACES,
      agents: INITIAL_AGENTS,
      timelines: INITIAL_TIMELINES,
      tasks: INITIAL_TASKS,
      settings: DEFAULT_SETTINGS,
    };
  }
}

export function saveStoredData(
  workspaces: Workspace[],
  agents: Agent[],
  timelines: Timeline[],
  tasks: Task[],
  settings?: AppSettings
) {
  try {
    localStorage.setItem(STORAGE_KEYS.WORKSPACES, JSON.stringify(workspaces));
    localStorage.setItem(STORAGE_KEYS.AGENTS, JSON.stringify(agents));
    localStorage.setItem(STORAGE_KEYS.TIMELINES, JSON.stringify(timelines));
    localStorage.setItem(STORAGE_KEYS.TASKS, JSON.stringify(tasks));
    if (settings) {
      localStorage.setItem(STORAGE_KEYS.SETTINGS, JSON.stringify(settings));
    }
  } catch (err) {
    console.error('Failed to persist to localStorage:', err);
  }
}
