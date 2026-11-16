import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {COPILOT_OFF_MESSAGE} from '../planner/aiAgentModel';

// Handoff 4-A - two server rules that used to live only in the screen or in "no tool exists".
// Static checks over the XanoScript; live proof is in the tracker.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');
const catalog = JSON.parse(read('webapp/protype-2/src/ops/errorCatalog.json'));

test('4-A rule 1: Publish to live refuses an AI identity, from one shared function', () => {
  const fn = read('functions/copilot/assert_person_only.xs');
  assert.ok(fn.includes('function.run "copilot/identity_for_user"'), 'it asks the one identity lookup');
  assert.ok(fn.includes('Only a person can do this. It is ready for the owner to do themselves. (E-COP-025)'), 'same words as the approval gate');
  assert.ok(fn.includes('outcome    : "rejected"') || fn.includes('outcome: "rejected"'), 'a refusal is logged');
  const ep = read('apis/planner/562_timeline_timeline_id_publish_POST.xs');
  const actorAt = ep.indexOf('} as $actor');
  const checkAt = ep.indexOf('function.run "copilot/assert_person_only"');
  assert.ok(checkAt > actorAt && actorAt > 0, 'checked right after the caller is known');
  assert.ok(checkAt < ep.indexOf('db.transaction {'), 'checked before anything is written');
});

test('4-A rule 2: a switched-off copilot column cannot be given new work, from one shared function', () => {
  const fn = read('functions/planner_ops/assert_agent_assignable.xs');
  assert.ok(fn.includes('E-COP-059'), 'its own code');
  assert.ok(fn.includes(COPILOT_OFF_MESSAGE), 'the same sentence as the screen');
  const entry = (catalog as Record<string, {user_message: string}>)['E-COP-059'];
  assert.ok(entry, 'E-COP-059 is in the catalog');
  assert.equal(entry.user_message, COPILOT_OFF_MESSAGE);
  for (const path of ['functions/planner_ops/create_timeline.xs', 'functions/planner_ops/schedule_work_task.xs']) {
    assert.ok(read(path).includes('function.run "planner_ops/assert_agent_assignable"'), `${path} obeys it`);
  }
});
