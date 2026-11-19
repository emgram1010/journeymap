import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {limitsProblem, trialProgress} from './skillsModel';

// COP-9 story 05 - trial before trust. Rule (founder, 2026-11-19): a trial item becomes trusted after
// trial_min_uses uses (default 5) in at least 2 different chats or runs, with no owner override; the owner
// undoing or editing it trial_max_overrides times (default 2) switches it off - kept, flagged, never
// deleted. The rule lives in ONE function on the server; these tests read its source.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');
const FN = 'functions/copilot/skill_trial_review.xs';

test('UT-COP-9-05-01: the thresholds are settings with defaults 5 and 2, not numbers buried in the rule', () => {
  const table = read('static/tables/166_copilot_library_setting.xs');
  assert.match(table, /trial_min_uses/);
  assert.match(table, /trial_max_overrides/);
  const fn = read(FN);
  assert.match(fn, /copilot_library_setting/);
  assert.match(fn, /trial_min_uses/);
  assert.match(fn, /trial_max_overrides/);
  assert.match(fn, /: 5\)/, 'default 5 uses');
  assert.match(fn, /: 2\)/, 'default 2 overrides');
});

test('UT-COP-9-05-02: promotion needs enough uses, at least 2 separate chats or runs, and no override', () => {
  const fn = read(FN);
  assert.match(fn, /\$ov_n == 0 && \$use_n >= \$min_uses && \$ctx_n >= 2/);
  assert.match(fn, /status\s*: "trusted"/);
});

test('UT-COP-9-05-03: overrides are owner edits and undos - never the owner pressing Lock or Unlock', () => {
  const fn = read(FN);
  assert.match(fn, /changed_by == "owner"/);
  assert.match(fn, /\["edit", "undo"\]/);
  assert.match(fn, /\["locked", "unlocked"\]/, 'lock changes are recorded as edits but are not overrides');
});

test('UT-COP-9-05-04: switching off retires (kept, undoable), never deletes, and an item the owner brought back is never switched off again', () => {
  const fn = read(FN);
  assert.match(fn, /status\s*: "retired"/);
  assert.ok(!/db\.del /.test(fn), 'nothing is deleted');
  assert.match(fn, /SWITCH_OFF_REASON|Trial rule: switched off/);
  assert.match(fn, /\$was_switched_off/, 'an item the rule already switched off once is exempt (no undo-retire loop)');
});

test('UT-COP-9-05-05: every promotion and switch-off writes a version and an event the digest can read', () => {
  const fn = read(FN);
  assert.match(fn, /db\.add copilot_skill_version/);
  assert.match(fn, /copilot\.skill\.trusted/);
  assert.match(fn, /copilot\.skill\.trial_switched_off/);
});

test('UT-COP-9-05-06: engine rules - no conditional inside the per-item loop, no |contains on arrays', () => {
  const fn = read(FN);
  const loop = fn.slice(fn.indexOf('foreach ($trials)'), fn.indexOf('// ── Phase 2'));
  assert.ok(loop.length > 100, 'the review loop exists');
  assert.ok(!/conditional \{/.test(loop), 'decisions in the loop are ternaries, never a conditional');
  assert.ok(!/\|contains:/.test(fn));
});

test('UT-COP-9-05-07: the nightly task reviews every account that has a copilot (plan allows 10 tasks, so it rides on task 19)', () => {
  const all = read('functions/copilot/skill_trial_review_all.xs');
  assert.match(all, /function\.run "copilot\/skill_trial_review"/);
  assert.match(all, /copilot_home/);
  const task = read('tasks/19_ops_integrity_audit.xs');
  assert.match(task, /function\.run "copilot\/skill_trial_review_all"/);
  assert.match(task, /try_catch/);
});

test('UT-COP-9-05-08: trial progress and the two new limits in plain words', () => {
  assert.equal(trialProgress(3, 5), 'Trial: 3 of 5 uses');
  assert.equal(trialProgress(7, 5), 'Trial: 5 of 5 uses');
  assert.equal(limitsProblem({max_active_items: 50, max_load_words: 4000, stale_after_days: 30, trial_min_uses: 5, trial_max_overrides: 2}), null);
  assert.match(limitsProblem({max_active_items: 50, max_load_words: 4000, stale_after_days: 30, trial_min_uses: 0, trial_max_overrides: 2}) ?? '', /1 and 50/);
  assert.match(limitsProblem({max_active_items: 50, max_load_words: 4000, stale_after_days: 30, trial_min_uses: 5, trial_max_overrides: 11}) ?? '', /1 and 10/);
});
