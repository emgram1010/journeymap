import assert from 'node:assert/strict';
import test from 'node:test';
import {cloneCellSnapshot, hasPendingCellChanges, resolveCellPersistenceBaseline} from './cellPersistence';
import type {MatrixCell} from './types';

const persistedCell: MatrixCell = {
  id: 'cell-1',
  xanoId: 101,
  stageId: 'stage-a',
  lensId: 'lens-a',
  content: 'Persisted',
  status: 'confirmed',
  isLocked: false,
};

test('resolveCellPersistenceBaseline prefers explicit rollback snapshots over selected cell snapshots', () => {
  const rollbackCell: MatrixCell = {...persistedCell, content: 'Rollback target', status: 'draft'};
  const selectedSnapshot: MatrixCell = {...persistedCell, content: 'Selected snapshot'};

  const result = resolveCellPersistenceBaseline(rollbackCell, selectedSnapshot);

  assert.equal(result, rollbackCell);
});

test('resolveCellPersistenceBaseline falls back to the selected cell snapshot when no rollback snapshot is provided', () => {
  const selectedSnapshot: MatrixCell = {...persistedCell, content: 'Selected snapshot'};

  const result = resolveCellPersistenceBaseline(null, selectedSnapshot);

  assert.equal(result, selectedSnapshot);
});

test('cloneCellSnapshot returns a detached copy for later rollback comparisons', () => {
  const snapshot = cloneCellSnapshot(persistedCell);

  assert.notEqual(snapshot, persistedCell);
  assert.deepEqual(snapshot, persistedCell);
});

test('hasPendingCellChanges detects content, status, and lock differences', () => {
  assert.equal(hasPendingCellChanges({...persistedCell, content: 'Edited'}, persistedCell), true);
  assert.equal(hasPendingCellChanges({...persistedCell, status: 'draft'}, persistedCell), true);
  assert.equal(hasPendingCellChanges({...persistedCell, isLocked: true}, persistedCell), true);
  assert.equal(hasPendingCellChanges({...persistedCell}, persistedCell), false);
});