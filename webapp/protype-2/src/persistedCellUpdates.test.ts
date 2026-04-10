import assert from 'node:assert/strict';
import test from 'node:test';
import {mergePersistedCellUpdates} from './persistedCellUpdates';
import type {Lens, MatrixCell, Stage} from './types';

const stages: Stage[] = [{id: 'stage-a', key: 'stage-key-a', xanoId: 11, label: 'Stage A'}];
const lenses: Lens[] = [{id: 'lens-a', key: 'lens-key-a', xanoId: 21, label: 'Lens A'}];

test('chat-mode style empty updates leave cells unchanged', () => {
  const cells: MatrixCell[] = [{id: 'cell-1', stageId: 'stage-a', lensId: 'lens-a', content: 'Existing', status: 'open', isLocked: false}];

  const result = mergePersistedCellUpdates(cells, [], stages, lenses);

  assert.equal(result, cells);
});

test('interview updates merge by journey cell id and preserve canonical metadata', () => {
  const cells: MatrixCell[] = [
    {
      id: 'cell-1',
      xanoId: 101,
      journeyCellId: 101,
      stageId: 'stage-a',
      stageKey: 'stage-key-a',
      lensId: 'lens-a',
      lensKey: 'lens-key-a',
      content: '',
      status: 'open',
      isLocked: false,
    },
  ];

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
  assert.equal(updatedCell?.journeyCellId, 101);
  assert.equal(updatedCell?.stageKey, 'stage-key-a');
  assert.equal(updatedCell?.lensKey, 'lens-key-a');
  assert.equal(updatedCell?.lastUpdated?.toISOString(), '2026-03-28T12:00:00.000Z');
});

test('interview updates fall back to stage/lens mapping for local cells', () => {
  const cells: MatrixCell[] = [
    {id: 'local-cell', stageId: 'stage-a', stageKey: 'stage-key-a', lensId: 'lens-a', lensKey: 'lens-key-a', content: '', status: 'open', isLocked: false},
  ];

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

test('interview updates can resolve by semantic stage and lens keys', () => {
  const cells: MatrixCell[] = [
    {id: 'local-keyed-cell', stageId: 'stage-a', stageKey: 'stage-key-a', lensId: 'lens-a', lensKey: 'lens-key-a', content: '', status: 'open', isLocked: false},
  ];

  const [updatedCell] = mergePersistedCellUpdates(
    cells,
    [{journeyCellId: 404, stageKey: 'stage-key-a', lensKey: 'lens-key-a', content: 'Semantic update', status: 'draft', isLocked: false, skipped: false}],
    stages,
    lenses,
  );

  assert.equal(updatedCell?.journeyCellId, 404);
  assert.equal(updatedCell?.content, 'Semantic update');
  assert.equal(updatedCell?.status, 'draft');
});

test('skipped updates do not modify cells', () => {
  const cells: MatrixCell[] = [
    {id: 'cell-1', xanoId: 101, journeyCellId: 101, stageId: 'stage-a', stageKey: 'stage-key-a', lensId: 'lens-a', lensKey: 'lens-key-a', content: 'Original', status: 'confirmed', isLocked: true},
  ];

  const [result] = mergePersistedCellUpdates(
    cells,
    [{journeyCellId: 101, content: 'Should not apply', status: 'draft', isLocked: false, skipped: true, skipReason: 'stale_target'}],
    stages,
    lenses,
  );

  // Skipped updates should leave the cell unchanged.
  assert.equal(result?.content, 'Original');
  assert.equal(result?.status, 'confirmed');
  assert.equal(result?.isLocked, true);
});