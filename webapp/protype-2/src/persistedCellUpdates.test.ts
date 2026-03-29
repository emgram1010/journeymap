import assert from 'node:assert/strict';
import test from 'node:test';
import {mergePersistedCellUpdates} from './persistedCellUpdates';
import type {Lens, MatrixCell, Stage} from './types';

const stages: Stage[] = [{id: 'stage-a', xanoId: 11, label: 'Stage A'}];
const lenses: Lens[] = [{id: 'lens-a', xanoId: 21, label: 'Lens A'}];

test('chat-mode style empty updates leave cells unchanged', () => {
  const cells: MatrixCell[] = [{id: 'cell-1', stageId: 'stage-a', lensId: 'lens-a', content: 'Existing', status: 'open', isLocked: false}];

  const result = mergePersistedCellUpdates(cells, [], stages, lenses);

  assert.equal(result, cells);
});

test('interview updates merge by journey cell id', () => {
  const cells: MatrixCell[] = [{id: 'cell-1', xanoId: 101, stageId: 'stage-a', lensId: 'lens-a', content: '', status: 'open', isLocked: false}];

  const [updatedCell] = mergePersistedCellUpdates(
    cells,
    [{journeyCellId: 101, content: 'AI draft', status: 'draft', isLocked: true, skipped: false, updatedAt: '2026-03-28T12:00:00.000Z'}],
    stages,
    lenses,
  );

  assert.notEqual(updatedCell, cells[0]);
  assert.equal(updatedCell?.content, 'AI draft');
  assert.equal(updatedCell?.status, 'draft');
  assert.equal(updatedCell?.isLocked, true);
  assert.equal(updatedCell?.lastUpdated?.toISOString(), '2026-03-28T12:00:00.000Z');
});

test('interview updates fall back to stage/lens mapping for local cells', () => {
  const cells: MatrixCell[] = [{id: 'local-cell', stageId: 'stage-a', lensId: 'lens-a', content: '', status: 'open', isLocked: false}];

  const [updatedCell] = mergePersistedCellUpdates(
    cells,
    [{journeyCellId: 303, stageId: 11, lensId: 21, content: 'Mapped update', status: 'confirmed', isLocked: false, skipped: false, lastUpdatedAt: '2026-03-28T15:30:00.000Z'}],
    stages,
    lenses,
  );

  assert.equal(updatedCell?.xanoId, 303);
  assert.equal(updatedCell?.content, 'Mapped update');
  assert.equal(updatedCell?.status, 'confirmed');
  assert.equal(updatedCell?.lastUpdated?.toISOString(), '2026-03-28T15:30:00.000Z');
});