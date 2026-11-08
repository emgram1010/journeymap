import assert from 'node:assert/strict';
import test from 'node:test';
import {jobPlacements, jobPlanStatus, placementsByJob, type PlacementTask, type PlacementTimeline, type PlacementAgent} from './jobScheduleModel';

const agents: PlacementAgent[] = [
  {id: '50', name: 'Jav'},
  {id: '21', name: 'Rochelle'},
];
const timelines: PlacementTimeline[] = [
  {id: '48', plannedDate: '2026-11-04', agentId: '50', status: 'published'},
  {id: '47', plannedDate: '2026-11-01', agentId: '50', status: 'draft'},
  {id: '29', plannedDate: '2026-11-01', agentId: '21', status: 'draft'},
];
const t = (over: Partial<PlacementTask>): PlacementTask => ({
  timelineId: '47',
  workItemId: '140',
  jobStepCount: 1,
  planned_start: '08:00',
  ...over,
});

test('UT-PUX-1-01a: groups a job\'s slots by day and person, earliest first', () => {
  const tasks = [
    t({timelineId: '48', planned_start: '09:00', jobStepCount: 3}),
    t({timelineId: '47', planned_start: '10:00', jobStepCount: 2}),
    t({timelineId: '47', planned_start: '08:30', jobStepCount: 1}),
    t({timelineId: '29', workItemId: '999'}),
  ];
  assert.deepEqual(jobPlacements('140', tasks, timelines, agents), [
    {timelineId: '47', date: '2026-11-01', agentName: 'Jav', start: '08:30', steps: 3, published: false},
    {timelineId: '48', date: '2026-11-04', agentName: 'Jav', start: '09:00', steps: 3, published: true},
  ]);
});

test('UT-PUX-1-01b: backlog slots and other jobs are ignored; nothing placed = empty', () => {
  const tasks = [t({timelineId: null}), t({workItemId: '999'})];
  assert.deepEqual(jobPlacements('140', tasks, timelines, agents), []);
});

test('UT-PUX-1-01c: a slot with no step count counts as one step; an unknown agent reads "Unassigned"', () => {
  const tasks = [t({jobStepCount: undefined, timelineId: '77'})];
  const tls = [...timelines, {id: '77', plannedDate: '2026-11-02', agentId: '0', status: 'draft' as const}];
  assert.deepEqual(jobPlacements('140', tasks, tls, agents), [
    {timelineId: '77', date: '2026-11-02', agentName: 'Unassigned', start: '08:00', steps: 1, published: false},
  ]);
});

test('UT-PUX-4-02: jobPlanStatus — every row of the epic table', () => {
  const draft = [{timelineId: '47', date: '2026-11-01', agentName: 'Jav', start: '08:00', steps: 8, published: false}];
  const live = [{timelineId: '48', date: '2026-11-04', agentName: 'Jav', start: '08:00', steps: 8, published: true}];
  const half = [{timelineId: '47', date: '2026-11-01', agentName: 'Jav', start: '08:00', steps: 5, published: false}];
  assert.deepEqual(jobPlanStatus({status: 'open', totalSteps: 8}, []), {kind: 'unscheduled', label: 'Unscheduled', left: 8});
  assert.deepEqual(jobPlanStatus({status: 'open', totalSteps: 8}, half), {kind: 'partly', label: 'Partly · 3 left', left: 3});
  assert.deepEqual(jobPlanStatus({status: 'open', totalSteps: 8}, draft), {kind: 'scheduled', label: 'Scheduled', left: 0});
  assert.deepEqual(jobPlanStatus({status: 'in_progress', totalSteps: 8}, live), {kind: 'live', label: 'Live', left: 0});
  assert.deepEqual(jobPlanStatus({status: 'completed', totalSteps: 8}, []), {kind: 'done', label: 'Done', left: 0});
  assert.deepEqual(jobPlanStatus({status: 'cancelled', totalSteps: 8}, half), {kind: 'cancelled', label: 'Cancelled', left: 0});
});

test('UT-PUX-4-02b: a job with mixed live and draft days is "Scheduled", not "Live"', () => {
  const mixed = [
    {timelineId: '47', date: '2026-11-01', agentName: 'Jav', start: '08:00', steps: 4, published: false},
    {timelineId: '48', date: '2026-11-04', agentName: 'Jav', start: '08:00', steps: 4, published: true},
  ];
  assert.equal(jobPlanStatus({status: 'open', totalSteps: 8}, mixed).kind, 'scheduled');
});

test('UT-PUX-4-02c: more steps placed than the job reports (stale counts) never goes negative', () => {
  const over = [{timelineId: '47', date: '2026-11-01', agentName: 'Jav', start: '08:00', steps: 9, published: false}];
  assert.deepEqual(jobPlanStatus({status: 'open', totalSteps: 8}, over), {kind: 'scheduled', label: 'Scheduled', left: 0});
});

test('UT-PUX-1-01d: placementsByJob gives the same answer as jobPlacements, for every job at once', () => {
  const tasks = [
    t({timelineId: '48', planned_start: '09:00', jobStepCount: 3}),
    t({timelineId: '29', workItemId: '999', jobStepCount: 2}),
    t({timelineId: null, workItemId: '777'}),
    {timelineId: '47', planned_start: '08:00'},
  ];
  const all = placementsByJob(tasks, timelines, agents);
  assert.deepEqual([...all.keys()].sort(), ['140', '999']);
  assert.deepEqual(all.get('140'), jobPlacements('140', tasks, timelines, agents));
  assert.deepEqual(all.get('999'), jobPlacements('999', tasks, timelines, agents));
});
