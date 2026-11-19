import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {dayLabel, stepUpsSummary, stepUpRowText} from './stepUpsModel';

// COP-13 story 05 (Health part) - step-ups per day per business, and how many were approved,
// declined, expired and refused by the cap. Read-only, platform admins only, last 7 days.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

test('UT-COP-13-05-01: the panel data comes from ONE read-only function behind the platform-admin check', () => {
  const ep = read('apis/ops/670_ops_step_ups_GET.xs');
  assert.match(ep, /query "ops\/step_ups" verb=GET/);
  assert.match(ep, /api_group = "Ops"/);
  assert.match(ep, /function\.run "ops\/require_platform_admin"/);
  assert.match(ep, /function\.run "ops\/step_ups_panel"/);
  const fn = read('functions/ops/step_ups_panel.xs');
  assert.ok(!/db\.(add|patch|del)\b/.test(fn), 'it only reads');
  for (const step of ['copilot.step_up.requested', 'copilot.step_up.capped', 'copilot.step_up.granted', 'copilot.step_up.ran']) assert.ok(fn.includes(`"${step}"`), step);
  assert.match(fn, /action_type == "step_up_model"/, 'approved / declined / expired come from the approval items');
  const literals = [...fn.replace(/\/\/.*$/gm, '').matchAll(/"([^"\r\n]*)"/g)].map((m) => m[1]);
  assert.deepEqual(literals.filter((l) => l.includes('|')), [], 'no | inside a string literal (it breaks the parser)');
  assert.match(fn, /not in \$|in \$conv_ids/, 'businesses are found by constraining a query, not an if in a loop');
});

test('UT-COP-13-05-02: a day index is shown as a plain date', () => {
  assert.equal(dayLabel(20776), 'Thu 19 Nov');
  assert.equal(dayLabel(0), 'Thu 1 Jan');
});

test('UT-COP-13-05-03: the summary counts the week in plain words', () => {
  assert.equal(stepUpsSummary({days: 7, rows: []}), 'No requests to use the stronger model in the last 7 days.');
  const s = stepUpsSummary({days: 7, rows: [
    {day: 1, journey_architecture_id: 49, business: 'A', requested: 3, capped: 1, granted: 2, ran: 2, approved: 1, declined: 1, expired: 0, waiting: 0},
    {day: 2, journey_architecture_id: 48, business: 'B', requested: 1, capped: 0, granted: 0, ran: 0, approved: 0, declined: 0, expired: 0, waiting: 1},
  ]});
  assert.equal(s, '4 requests to use the stronger model in the last 7 days: 1 approved, 1 declined, 1 refused by the daily limit, 1 still waiting. 2 re-done on the stronger model.');
});

test('UT-COP-13-05-04: one row reads as one line, naming the business and leaving out zeroes', () => {
  const t = stepUpRowText({day: 20776, journey_architecture_id: 49, business: 'Bike repairs', requested: 2, capped: 0, granted: 1, ran: 1, approved: 1, declined: 1, expired: 0, waiting: 0});
  assert.equal(t, 'Thu 19 Nov - Bike repairs: 2 asked, 1 approved, 1 declined, 1 re-done');
  const u = stepUpRowText({day: 20776, journey_architecture_id: 0, business: '', requested: 1, capped: 1, granted: 0, ran: 0, approved: 0, declined: 0, expired: 0, waiting: 0});
  assert.equal(u, 'Thu 19 Nov - Unknown business: 1 asked, 1 refused by the daily limit');
});
