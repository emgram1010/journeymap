import assert from 'node:assert/strict';
import test from 'node:test';
import {
  MAX_PERIODS,
  validatePeriodCount,
  runPeriods,
  outcomeCounts,
  outcomeLine,
  repeatedFromText,
  repeatedToLine,
  type RepeatPeriod,
  type CreateOne,
} from './repeatPeriodsModel';

// REPEAT-1 story 06. The server (repeat/list_periods, POST workspace/{id}/repeat-periods) decides
// the dates and names of every period and which already exist. This model only runs them one at a
// time, as separate requests, and reports each one plainly. Every period is its own all-or-nothing
// write on the server, so a failure here never undoes a period that was already made.

const period = (n: number, over: Partial<RepeatPeriod> = {}): RepeatPeriod => ({
  n,
  start_date: `2027-04-${String(5 + (n - 1) * 7).padStart(2, '0')}`,
  end_date: `2027-04-${String(9 + (n - 1) * 7).padStart(2, '0')}`,
  shift_days: 7 * n,
  weekdays_align: true,
  name: `Week 12 (period ${n})`,
  exists: false,
  existing_workspace_id: 0,
  ...over,
});

const created = (id: number) => async () => ({outcome: 'created' as const, workspace_id: id, existing_workspace_id: 0});

test('T-REPEAT-06-2: the limit is 1 to 8 whole periods, and the message names it', () => {
  assert.equal(MAX_PERIODS, 8);
  for (const n of [1, 4, 8]) assert.deepEqual(validatePeriodCount(n), {ok: true});
  for (const n of [0, -1, 9, 100, 2.5, Number.NaN]) {
    const r = validatePeriodCount(n);
    assert.equal(r.ok, false);
    if (r.ok === false) {
      assert.equal(r.code, 'E-REPEAT-010');
      assert.ok(r.message.includes('1 to 8'), r.message);
    }
  }
});

test('T-REPEAT-06-1: every period is made, in order, each one from the same source (never from the copy before)', async () => {
  const seen: number[] = [];
  const periods = [period(1), period(2), period(3), period(4)];
  const create: CreateOne = async p => {
    seen.push(p.n);
    return {outcome: 'created', workspace_id: 100 + p.n, existing_workspace_id: 0};
  };
  const out = await runPeriods(periods, create);
  assert.deepEqual(seen, [1, 2, 3, 4]);
  assert.deepEqual(out.map(o => o.status), ['created', 'created', 'created', 'created']);
  assert.deepEqual(out.map(o => o.workspace_id), [101, 102, 103, 104]);
  // The list handed in is never changed by the run.
  assert.equal(periods[1].start_date, '2027-04-12');
});

test('T-REPEAT-06-3: a period that already exists is skipped and named, and the others are made', async () => {
  let calls = 0;
  const create: CreateOne = async p => {
    calls++;
    return {outcome: 'created', workspace_id: 100 + p.n, existing_workspace_id: 0};
  };
  const out = await runPeriods([period(1), period(2, {exists: true, existing_workspace_id: 55}), period(3)], create);
  assert.equal(calls, 2, 'the existing period is never asked for again');
  assert.deepEqual(out.map(o => o.status), ['created', 'skipped', 'created']);
  assert.equal(out[1].workspace_id, 55);
  assert.ok(outcomeLine(out[1]).includes('Week 12 (period 2)'));
  assert.ok(outcomeLine(out[1]).includes('already'));
});

test('a confirm that lost a race (the server answers "exists") is a skip, not a failure', async () => {
  const create: CreateOne = async () => ({outcome: 'exists', workspace_id: 0, existing_workspace_id: 77});
  const out = await runPeriods([period(1)], create);
  assert.equal(out[0].status, 'skipped');
  assert.equal(out[0].workspace_id, 77);
});

test('T-REPEAT-06-4: a failure on period 3 keeps 1 and 2, reports 3, and does not try 4', async () => {
  let calls = 0;
  const create: CreateOne = async p => {
    calls++;
    if (p.n === 3) throw new Error("The new plan couldn't be created. Nothing was saved. Try again. (E-REPEAT-006)");
    return {outcome: 'created', workspace_id: 100 + p.n, existing_workspace_id: 0};
  };
  const out = await runPeriods([period(1), period(2), period(3), period(4)], create);
  assert.equal(calls, 3);
  assert.deepEqual(out.map(o => o.status), ['created', 'created', 'failed', 'not_attempted']);
  assert.ok(out[2].message?.includes('E-REPEAT-006'));
  assert.equal(out[2].workspace_id, undefined, 'a failed period leaves no plan to link to');
  const counts = outcomeCounts(out);
  assert.deepEqual(counts, {created: 2, skipped: 0, failed: 1, notAttempted: 1});
  assert.ok(outcomeLine(out[3]).includes('not tried'));
});

test('a failure that is not an Error still gets plain words, never a raw object', async () => {
  const create: CreateOne = async () => {
    throw {weird: true};
  };
  const out = await runPeriods([period(1)], create);
  assert.equal(out[0].status, 'failed');
  assert.ok((out[0].message ?? '').length > 10);
  assert.ok(!(out[0].message ?? '').includes('[object'));
});

test('T-REPEAT-06-5: "repeated from" and "repeated to" wording, including a source that no longer exists', () => {
  assert.equal(repeatedFromText(null), '');
  assert.equal(repeatedFromText({workspace_id: 5, name: 'Week 12', exists: true}), 'Repeated from Week 12');
  assert.equal(
    repeatedFromText({workspace_id: 5, name: '', exists: false}),
    'Repeated from a plan that no longer exists',
  );
  assert.equal(
    repeatedToLine({workspace_id: 9, name: 'Week 13', start_date: '2027-04-12', end_date: '2027-04-16', needs_review: 3}),
    'Week 13 · 2027-04-12 to 2027-04-16 · 3 to review',
  );
  assert.equal(
    repeatedToLine({workspace_id: 9, name: 'Week 13', start_date: '2027-04-12', end_date: '2027-04-16', needs_review: 0}),
    'Week 13 · 2027-04-12 to 2027-04-16',
  );
});
