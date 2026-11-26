import assert from 'node:assert/strict';
import test from 'node:test';
import {
  reviewByTask,
  markedOnDay,
  totalMarked,
  publishReviewNotice,
  reviewReasonText,
  type RawReview,
} from './reviewModel';

// REPEAT-1 story 05. The server (planner_task_review, the board's `reviews[]`) says which slots
// need a second look and why. This model only turns that into what the screen shows: a sign and a
// reason on each slot, a count on each day, a total for the plan, and one plain sentence at
// Publish to live. Nothing here decides what needs review.

const r = (task: number, code = 'copied', text = 'copied from Week 12'): RawReview => ({
  planner_task_id: task,
  reason_code: code,
  reason_text: text,
});

test('T-REPEAT-05-1: each marked slot gets its reason; an unmarked slot gets nothing', () => {
  const map = reviewByTask([r(10), r(11, 'person_left_off', 'Old is no longer on the plan')]);
  assert.equal(map.get('10')?.text, 'copied from Week 12');
  assert.equal(map.get('11')?.code, 'person_left_off');
  assert.equal(map.get('12'), undefined);
  assert.equal(reviewByTask([]).size, 0);
});

test('T-REPEAT-05-1: counts per day and for the plan; backlog marks count for the plan, not for a day', () => {
  const mark = {code: 'copied', text: 'copied from Week 12'};
  const tasks = [
    {timelineId: '5', review: mark},
    {timelineId: '5', review: mark},
    {timelineId: '6', review: mark},
    {timelineId: null, review: mark},
    {timelineId: '6'},
  ];
  assert.equal(markedOnDay(tasks, '5'), 2);
  assert.equal(markedOnDay(tasks, '6'), 1);
  assert.equal(markedOnDay(tasks, '7'), 0);
  assert.equal(totalMarked(tasks), 4);
});

test('a plan with no marks shows nothing new', () => {
  const tasks = [{timelineId: '5'}];
  assert.equal(totalMarked(tasks), 0);
  assert.equal(markedOnDay(tasks, '5'), 0);
  assert.equal(publishReviewNotice(0), '');
});

test('T-REPEAT-05-4: the publish notice names the count in plain words, singular and plural', () => {
  assert.equal(publishReviewNotice(4), '4 items were copied and not yet reviewed. Publish anyway?');
  assert.equal(publishReviewNotice(1), '1 item was copied and not yet reviewed. Publish anyway?');
  assert.equal(publishReviewNotice(-3), '');
});

test('every reason has plain wording and an unknown one never shows its raw code', () => {
  for (const code of ['copied', 'person_left_off', 'new_step']) {
    const text = reviewReasonText(code, '');
    assert.ok(text.length > 10, code);
    assert.ok(!text.includes('_'), code);
  }
  assert.ok(!reviewReasonText('something_new', '').includes('_'));
  // The server's own sentence wins when it has one (it names the plan or the person).
  assert.equal(reviewReasonText('copied', 'copied from Week 12'), 'copied from Week 12');
});
