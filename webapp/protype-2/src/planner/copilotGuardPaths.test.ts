import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// Final review R12 - every planner path that hands work to a column checks for a switched-off
// copilot first. Reads PlannerApp.tsx, so a new path that forgets fails here.

const src = readFileSync(fileURLToPath(new URL('./PlannerApp.tsx', import.meta.url)), 'utf8');
const body = (name: string) => {
  const at = src.indexOf(`const ${name} =`);
  assert.ok(at > 0, `${name} exists`);
  return src.slice(at, at + 1600);
};

test('R12: assigning a task to someone on task save checks the copilot', () => {
  const b = body('handleSaveTaskFromModal');
  assert.ok(b.indexOf('refuseCopilotOff(match.id)') < b.indexOf('await updateTask('), 'checked before saving');
});

test('R12: a backlog task for someone checks the copilot', () => {
  const b = body('handleCreateBacklogTask');
  assert.ok(b.indexOf('refuseCopilotOff(agentOverride.id)') < b.indexOf('createTask('), 'checked before creating');
});

test('R12: Publish to live and republish check the copilot; publish day leaves its day out', () => {
  assert.ok(body('handlePublishTimeline').includes('refuseCopilotOff(tl.agentId)'));
  assert.ok(body('handleRepublishTimeline').includes('refuseCopilotOff(tl.agentId)'));
  const bulk = body('handleConfirmBulkPublish');
  assert.ok(bulk.includes('isSwitchedOffCopilot(agent, accountCopilot)'));
  assert.ok(bulk.indexOf('.filter(id => !offDay(id))') < bulk.indexOf('Promise.allSettled('));
});

test('R12: moving a copilot\'s own day to another date is allowed; moving a day onto it is not', () => {
  const b = body('handleMoveTimelineCell');
  assert.ok(b.includes('fromAgentId !== targetAgentId && refuseCopilotOff(targetAgentId)'));
});
