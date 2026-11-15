import assert from 'node:assert/strict';
import test from 'node:test';
import {
  NOTE_MAX,
  goalStatusLabel,
  isSafeUrl,
  mapLabelChips,
  noteProblem,
  profileByMap,
  safeSources,
  testedSinceText,
} from './copilotMemoryModel';

test('no profile gives no label and no warning', () => {
  assert.deepEqual(mapLabelChips(undefined), []);
  assert.deepEqual(mapLabelChips(null), []);
});

test('kind labels', () => {
  assert.equal(mapLabelChips({journey_map_id: 1, kind: 'insight', made_by: '', tested_since: 0})[0].text, 'Insight');
  assert.equal(mapLabelChips({journey_map_id: 1, kind: 'runnable', made_by: '', tested_since: 0})[0].text, 'Runnable');
});

test('tested wins; copilot-made but untested is flagged; people-made is quiet', () => {
  const t = 1_800_000_000_000;
  const tested = mapLabelChips({journey_map_id: 1, kind: 'insight', made_by: 'copilot_research', tested_since: t});
  assert.ok(tested.some((c) => c.text.startsWith('Tested since ')));
  assert.ok(!tested.some((c) => c.text === 'Researched, not tested'));
  const untested = mapLabelChips({journey_map_id: 1, kind: 'insight', made_by: 'copilot_draft', tested_since: 0});
  assert.ok(untested.some((c) => c.text === 'Researched, not tested'));
  const person = mapLabelChips({journey_map_id: 1, kind: 'runnable', made_by: 'person', tested_since: 0});
  assert.equal(person.length, 1);
  assert.equal(testedSinceText(0), '');
});

test('goal status labels', () => {
  assert.equal(goalStatusLabel('proposed'), 'Proposed by the copilot');
  assert.equal(goalStatusLabel('confirmed'), 'Confirmed');
  assert.equal(goalStatusLabel('done'), 'Done');
  assert.equal(goalStatusLabel('dropped'), 'Dropped');
  assert.equal(goalStatusLabel('weird'), 'weird');
});

test('note validation', () => {
  assert.notEqual(noteProblem('   '), null);
  assert.equal(noteProblem('ok'), null);
  assert.equal(noteProblem('a'.repeat(NOTE_MAX)), null);
  assert.notEqual(noteProblem('a'.repeat(NOTE_MAX + 1)), null);
});

test('only http and https sources open as links', () => {
  assert.equal(isSafeUrl('https://a.com/x'), true);
  assert.equal(isSafeUrl('http://a.com'), true);
  assert.equal(isSafeUrl('javascript:alert(1)'), false);
  assert.equal(isSafeUrl('data:text/html,hi'), false);
  assert.equal(isSafeUrl('not a url'), false);
  const s = safeSources([{title: 'A', url: 'https://a.com'}, {title: 'B', url: 'javascript:x'}, null as never]);
  assert.equal(s.length, 2);
  assert.equal(s[0].safe, true);
  assert.equal(s[1].safe, false);
  assert.deepEqual(safeSources(undefined), []);
});

test('profileByMap indexes by map id', () => {
  const m = profileByMap([{journey_map_id: 5, kind: 'insight', made_by: '', tested_since: 0}]);
  assert.ok(m.get(5));
  assert.equal(m.get(6), undefined);
});
