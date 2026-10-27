import assert from 'node:assert/strict';
import test from 'node:test';
import {openChildSentence, ageWords, reasonWords} from './healthText';

const row = {
  child_work_item_id: 491,
  parent_work_item_id: 482,
  parent_title: 'Order 482',
  stage_label: 'Triage',
  target_map_title: 'Repair',
  moved_count: 2,
  age_days: 6,
  depth: 1,
};

test('US-EXC-1-07: the epic\'s own sentence, in plain language', () => {
  assert.equal(openChildSentence(row), 'Order 482 (#482) sent 2 items to Repair (#491) at Triage, 6 days ago — still open.');
});

test('a whole-job exception has no count; today and one day read naturally; depth shows when > 1', () => {
  assert.equal(
    openChildSentence({...row, moved_count: 0, age_days: 0, depth: 2}),
    'Order 482 (#482) sent work to Repair (#491) at Triage, today — still open. (a child of a child)',
  );
  assert.equal(ageWords(1), '1 day ago');
  assert.equal(ageWords(0), 'today');
});

test('reason codes read as words', () => {
  assert.equal(reasonWords('something_went_wrong'), 'Something went wrong');
  assert.equal(reasonWords('unknown_code'), 'unknown code');
});
