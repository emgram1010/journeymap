// ITEM-0 (US-ITEM-0-05) — Guard tests for the Items row.
//
// These exist to FAIL if a future change ever treats the Items row as an
// actor row. The Items row is a `journey_lens` with actor_type = "" and
// template_key = "items-v1" (PRD §2.4, D-IR-11, O-1). It must never do
// planned work, never own a stage, and never produce a task.
//
// Verified live against map 213 (a clone of 193) on 2026-10-24 — see
// EPIC-ITEM-0 Test Results. The backend twin is
// workflow_tests/28_items_row_guards.xs.

import assert from 'node:assert/strict';
import test from 'node:test';
import {doesPlannedWork, resolveOwner} from './stageOwnerModel';
import {tasksFromVersion} from './jobModel';

/** The Items row, exactly as ITEM-1 will create it. */
const ITEMS_ROW = {
  key: 'items',
  label: 'Items',
  actor_type: '' as const,
  template_key: 'items-v1',
  does_planned_work: false,
};

test('UT-ITEM-0-01: the Items row never does planned work, with or without an override', () => {
  // Its real shape: actor_type "" and no explicit override row.
  assert.equal(doesPlannedWork('' as never, null), false);
  assert.equal(doesPlannedWork('' as never, undefined), false);
  // ITEM-1 also writes an explicit false row; that must agree.
  assert.equal(doesPlannedWork('' as never, false), false);
});

test('UT-ITEM-0-02: actor rows are unaffected by the Items row guard', () => {
  assert.equal(doesPlannedWork('internal', null), true);
  assert.equal(doesPlannedWork('ai_agent', null), true);
  assert.equal(doesPlannedWork('customer', null), false);
});

test('UT-ITEM-0-03: an explicit TRUE override on the Items row is the one shape that would break it', () => {
  // Documented on purpose: doesPlannedWork honours any explicit override, so
  // nothing in the shared predicate stops someone writing `true` for the Items
  // row. ITEM-1 must reject that server-side (E-ITM-008) — this assertion
  // pins WHY that error code exists. If this ever returns false, the override
  // rule changed and E-ITM-008 may be redundant.
  assert.equal(doesPlannedWork('' as never, true), true);
});

test('UT-ITEM-0-04: the Items row produces no task, even when its cells hold rates', () => {
  const snapshot = {
    schema_version: 1,
    title: 'ITEM-0 guard fixture',
    stages: [
      {key: 's1', label: 'Receive', owner_lens_key: 'lens-2'},
      {key: 's8', label: 'Wash & Clean', owner_lens_key: 'lens-2'},
    ],
    lenses: [
      {key: 'lens-2', label: 'Warehouse Operations', actor_type: 'internal', does_planned_work: true},
      {...ITEMS_ROW},
    ],
    // A real snapshot never carries Items cells at all (build_map_snapshot
    // emits cells only for work rows). Including one here is deliberately
    // harsher than reality: even if one leaked in, it must not become a task.
    cells: [
      {stage_key: 's1', lens_key: 'lens-2', task: 'Count the load', done_when: 'Counted', duration_minutes: 60},
      {stage_key: 's8', lens_key: 'lens-2', task: 'Wash and clean', done_when: 'Clean', duration_minutes: 10},
      {stage_key: 's8', lens_key: 'items', task: 'per_unit', done_when: null, duration_minutes: 30},
    ],
    links: [],
  };

  const result = tasksFromVersion(snapshot as never);
  const itemsTasks = result.tasks.filter((t) => t.lens_key === 'items');

  assert.equal(itemsTasks.length, 0, 'the Items row must never produce a task');
  assert.equal(result.tasks.length, 2, 'only the two owner tasks');
  assert.deepEqual(result.skipped, [], 'and nothing is reported as skipped');
});

test('UT-ITEM-0-05: resolveOwner still resolves the Items row, so the ban must be enforced elsewhere', () => {
  // resolveOwner is a pure key lookup with no actor filter (confirmed by
  // reading functions/resolve_stage_owner.xs). It therefore WILL hand back
  // the Items row if a stage names it. That is why ITEM-1 adds E-ITM-007 at
  // the stage-owner write path rather than here.
  assert.deepEqual(resolveOwner('items', [{key: 'items', xanoId: 1248}]), {
    resolved: true,
    ownerLensId: 1248,
  });
});
