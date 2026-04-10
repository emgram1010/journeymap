import assert from 'node:assert/strict';
import test from 'node:test';
import {buildCellReferenceLabel, buildCellShorthand, buildCellUpdateSummaries, buildSelectedCellContext, resolveCellReference, resolveLensKey, resolveStageKey} from './cellIdentifiers';
import type {Lens, MatrixCell, Stage} from './types';

const stages: Stage[] = [
  {id: 's1', key: 's1', xanoId: 11, label: 'Booking'},
  {id: 's2', key: 's2', xanoId: 12, label: 'Fulfillment'},
];

const lenses: Lens[] = [
  {id: 'customer', key: 'customer', xanoId: 21, label: 'Customer'},
  {id: 'notifications', key: 'notifications', xanoId: 22, label: 'Notifications'},
];

test('resolveStageKey prefers explicit stable keys', () => {
  assert.equal(resolveStageKey({id: 'stage-a', key: 'booking'}), 'booking');
  assert.equal(resolveStageKey({id: 'stage-b'}), 'stage-b');
});

test('resolveLensKey prefers explicit stable keys', () => {
  assert.equal(resolveLensKey({id: 'lens-a', key: 'notifications'}), 'notifications');
  assert.equal(resolveLensKey({id: 'lens-b'}), 'lens-b');
});

test('buildCellReferenceLabel returns Stage × Lens format', () => {
  assert.equal(buildCellReferenceLabel('Booking', 'Customer'), 'Booking × Customer');
});

test('buildCellReferenceLabel returns null when either label is missing', () => {
  assert.equal(buildCellReferenceLabel('Booking', null), null);
  assert.equal(buildCellReferenceLabel(null, 'Customer'), null);
  assert.equal(buildCellReferenceLabel(null, null), null);
});

test('buildCellShorthand returns positional shorthand like S1-L2', () => {
  assert.equal(buildCellShorthand({stageId: 's1', lensId: 'notifications'} as MatrixCell, stages, lenses), 'S1-L2');
  assert.equal(buildCellShorthand({stageId: 's2', lensId: 'customer'} as MatrixCell, stages, lenses), 'S2-L1');
});

test('buildCellShorthand returns null for unknown stage or lens', () => {
  assert.equal(buildCellShorthand({stageId: 'missing', lensId: 'customer'} as MatrixCell, stages, lenses), null);
  assert.equal(buildCellShorthand(null, stages, lenses), null);
});

test('buildSelectedCellContext assembles full context for a persisted cell', () => {
  const cell: MatrixCell = {
    id: 'cell-1',
    xanoId: 100,
    journeyCellId: 100,
    journeyMapId: 42,
    stageId: 's2',
    stageKey: 's2',
    stageXanoId: 12,
    lensId: 'notifications',
    lensKey: 'notifications',
    lensXanoId: 22,
    content: 'test',
    status: 'draft',
    isLocked: false,
  };

  const result = buildSelectedCellContext({cell, stages, lenses, journeyMapId: 42});

  assert.deepEqual(result, {
    reference: 'Fulfillment × Notifications',
    shorthand: 'S2-L2',
    journeyMapId: 42,
    journeyCellId: 100,
    stageId: 12,
    stageKey: 's2',
    stageLabel: 'Fulfillment',
    lensId: 22,
    lensKey: 'notifications',
    lensLabel: 'Notifications',
  });
});

test('buildSelectedCellContext returns null when no cell is selected', () => {
  assert.equal(buildSelectedCellContext({cell: null, stages, lenses}), null);
  assert.equal(buildSelectedCellContext({cell: undefined, stages, lenses}), null);
});

test('buildCellUpdateSummaries returns applied and skipped entries', () => {
  const applied = [{stageLabel: 'Booking', lensLabel: 'Customer'}];
  const skipped = [{stageLabel: 'Fulfillment', lensLabel: 'Notifications', skipReason: 'locked'}];

  const result = buildCellUpdateSummaries(applied, skipped);

  assert.equal(result.length, 2);
  assert.deepEqual(result[0], {reference: 'Booking × Customer', status: 'applied'});
  assert.deepEqual(result[1], {reference: 'Fulfillment × Notifications', status: 'skipped', reason: 'cell is locked'});
});

test('buildCellUpdateSummaries handles missing labels gracefully', () => {
  const applied = [{stageLabel: null, lensLabel: null}];
  const skipped: {stageLabel?: string | null; lensLabel?: string | null; skipReason?: string | null}[] = [];

  const result = buildCellUpdateSummaries(applied, skipped);

  assert.equal(result.length, 1);
  assert.equal(result[0]?.reference, 'Unknown cell');
  assert.equal(result[0]?.status, 'applied');
});

test('buildCellUpdateSummaries returns empty array when no updates', () => {
  assert.deepEqual(buildCellUpdateSummaries([], []), []);
});

// --- resolveCellReference ---

const cells: MatrixCell[] = [
  {id: 'c1', xanoId: 100, journeyCellId: 100, stageId: 's1', stageKey: 's1', lensId: 'customer', lensKey: 'customer', content: '', status: 'open', isLocked: false},
  {id: 'c2', xanoId: 200, journeyCellId: 200, stageId: 's2', stageKey: 's2', lensId: 'notifications', lensKey: 'notifications', content: '', status: 'draft', isLocked: false},
  {id: 'c3', xanoId: 300, journeyCellId: 300, stageId: 's1', stageKey: 's1', lensId: 'notifications', lensKey: 'notifications', content: '', status: 'open', isLocked: false},
];

test('resolveCellReference resolves by canonical cell ID', () => {
  const result = resolveCellReference('200', cells, stages, lenses);
  assert.equal(result.status, 'matched');
  if (result.status === 'matched') assert.equal(result.cell.id, 'c2');
});

test('resolveCellReference resolves by shorthand S1-L2', () => {
  const result = resolveCellReference('S1-L2', cells, stages, lenses);
  assert.equal(result.status, 'matched');
  if (result.status === 'matched') assert.equal(result.cell.id, 'c3');
});

test('resolveCellReference resolves by human-readable label reference', () => {
  const result = resolveCellReference('Fulfillment × Notifications', cells, stages, lenses);
  assert.equal(result.status, 'matched');
  if (result.status === 'matched') assert.equal(result.cell.id, 'c2');
});

test('resolveCellReference resolves by label reference case-insensitively', () => {
  const result = resolveCellReference('booking × customer', cells, stages, lenses);
  assert.equal(result.status, 'matched');
  if (result.status === 'matched') assert.equal(result.cell.id, 'c1');
});

test('resolveCellReference resolves by stable key pair', () => {
  const result = resolveCellReference('s2 × notifications', cells, stages, lenses);
  assert.equal(result.status, 'matched');
  if (result.status === 'matched') assert.equal(result.cell.id, 'c2');
});

test('resolveCellReference returns not_found for unknown reference', () => {
  const result = resolveCellReference('Unknown × Missing', cells, stages, lenses);
  assert.equal(result.status, 'not_found');
});

test('resolveCellReference returns not_found for empty string', () => {
  const result = resolveCellReference('', cells, stages, lenses);
  assert.equal(result.status, 'not_found');
});

test('resolveCellReference returns not_found for out-of-range shorthand', () => {
  const result = resolveCellReference('S99-L99', cells, stages, lenses);
  assert.equal(result.status, 'not_found');
});

// --- US-CI-08: rename resilience, stale target, locked + reference scenarios ---

test('buildCellReferenceLabel works after a stage rename (label changes, key stays)', () => {
  // Simulates a rename: the stage label changes but the stage object's key is preserved.
  const renamedStages: Stage[] = [
    {id: 's1', key: 's1', xanoId: 11, label: 'Onboarding'},
    ...stages.slice(1),
  ];
  const cellAfterRename: MatrixCell = {...cells[0]!, stageId: 's1', stageKey: 's1'};
  const ctx = buildSelectedCellContext({cell: cellAfterRename, stages: renamedStages, lenses});
  assert.equal(ctx?.reference, 'Onboarding × Customer');
  assert.equal(ctx?.stageKey, 's1');
});

test('buildCellShorthand stays correct after a stage is added', () => {
  const extendedStages: Stage[] = [...stages, {id: 's3', key: 's3', xanoId: 13, label: 'Support'}];
  // c2 is still at s2 so its shorthand should remain S2-L2.
  assert.equal(buildCellShorthand(cells[1]!, extendedStages, lenses), 'S2-L2');
});

test('buildCellUpdateSummaries formats stale_target skip reason', () => {
  const skipped = [{stageLabel: null, lensLabel: null, skipReason: 'stale_target'}];
  const result = buildCellUpdateSummaries([], skipped);
  assert.equal(result.length, 1);
  assert.equal(result[0]?.status, 'skipped');
  assert.equal(result[0]?.reason, 'stage or lens was deleted');
});

test('resolveCellReference resolves locked cell the same as unlocked', () => {
  const lockedCells: MatrixCell[] = [
    {...cells[0]!, isLocked: true},
    ...cells.slice(1),
  ];
  const result = resolveCellReference('Booking × Customer', lockedCells, stages, lenses);
  assert.equal(result.status, 'matched');
  if (result.status === 'matched') {
    assert.equal(result.cell.id, 'c1');
    assert.equal(result.cell.isLocked, true);
  }
});