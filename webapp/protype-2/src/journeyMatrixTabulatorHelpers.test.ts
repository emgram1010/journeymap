import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyMatrixSearchFilter,
  findMatrixCellIdFromClickTarget,
  formatLensCellMarkup,
  formatMatrixCellMarkup,
  syncSelectedMatrixCellClasses,
} from './journeyMatrixTabulatorHelpers';
import type {MatrixCell, Stage} from './types';

const baseCell: MatrixCell = {
  id: 'cell-1',
  stageId: 'stage-a',
  lensId: 'lens-a',
  content: '',
  status: 'open',
  isLocked: false,
};

const searchStages: Stage[] = [
  {id: 'stage-a', label: 'Stage A'},
  {id: 'stage-b', label: 'Stage B'},
];

test('formatLensCellMarkup escapes editable lens labels', () => {
  const markup = formatLensCellMarkup('<Customer & Ops>');

  assert.ok(markup.includes('&lt;Customer &amp; Ops&gt;'));
  assert.ok(markup.includes('jm-lens-cell'));
});

test('formatMatrixCellMarkup renders selected confirmed cells with escaped content and data-cell-id', () => {
  const markup = formatMatrixCellMarkup({
    content: '<draft>',
    meta: {...baseCell, status: 'confirmed'},
    selectedCellId: 'cell-1',
  });

  assert.ok(markup.includes('jm-grid-cell is-selected'));
  assert.ok(markup.includes('data-cell-id="cell-1"'));
  assert.ok(markup.includes('&lt;draft&gt;'));
  assert.ok(markup.includes('jm-status-indicator confirmed'));
});

test('formatMatrixCellMarkup shows lock indicator for locked cells', () => {
  const markup = formatMatrixCellMarkup({
    content: '',
    meta: {...baseCell, isLocked: true, status: 'draft'},
    selectedCellId: null,
  });

  assert.ok(markup.includes('jm-status-indicator lock'));
  assert.ok(markup.includes('🔒'));
  assert.ok(markup.includes('No data'));
});

test('findMatrixCellIdFromClickTarget resolves delegated selection only within the matrix container', () => {
  const gridCell = {dataset: {cellId: 'cell-99'}};
  const target = {closest: (selector: string) => (selector === '.jm-grid-cell[data-cell-id]' ? gridCell : null)};
  const container = {contains: (node: unknown) => node === gridCell};

  assert.equal(findMatrixCellIdFromClickTarget(target as unknown as EventTarget, container), 'cell-99');
  assert.equal(findMatrixCellIdFromClickTarget(target as unknown as EventTarget, {contains: () => false}), null);
});

test('syncSelectedMatrixCellClasses toggles only matching data cells', () => {
  const selectedToggles: Array<{className: string; force?: boolean}> = [];
  const otherToggles: Array<{className: string; force?: boolean}> = [];

  const selectedGridCell = {
    classList: {toggle: (className: string, force?: boolean) => selectedToggles.push({className, force})},
  };
  const otherGridCell = {
    classList: {toggle: (className: string, force?: boolean) => otherToggles.push({className, force})},
  };

  syncSelectedMatrixCellClasses(
    {
      getRows: () => [
        {
          getData: () => ({id: 'lens-a'}),
          getCells: () => [
            {getField: () => 'lensLabel', getElement: () => ({querySelector: () => selectedGridCell})},
            {getField: () => 'stage-a', getElement: () => ({querySelector: () => selectedGridCell})},
            {getField: () => 'stage-b', getElement: () => ({querySelector: () => otherGridCell})},
          ],
        },
      ],
    },
    new Map([
      ['stage-a:lens-a', {...baseCell, id: 'cell-1'}],
      ['stage-b:lens-a', {...baseCell, id: 'cell-2', stageId: 'stage-b'}],
    ]),
    'cell-1',
  );

  assert.deepEqual(selectedToggles, [{className: 'is-selected', force: true}]);
  assert.deepEqual(otherToggles, [{className: 'is-selected', force: false}]);
});

test('applyMatrixSearchFilter clears existing filters for blank queries', () => {
  let clearCalls = 0;
  let setCalls = 0;

  applyMatrixSearchFilter(
    {
      clearFilter: () => {
        clearCalls += 1;
      },
      setFilter: () => {
        setCalls += 1;
      },
    },
    '   ',
    searchStages,
  );

  assert.equal(clearCalls, 1);
  assert.equal(setCalls, 0);
});

test('applyMatrixSearchFilter matches lens labels and stage cell content case-insensitively', () => {
  let predicate: ((rowData: Record<string, string>) => boolean) | null = null;

  applyMatrixSearchFilter(
    {
      clearFilter: () => {
        assert.fail('blank-query clearFilter path should not run');
      },
      setFilter: (nextPredicate) => {
        predicate = nextPredicate;
      },
    },
    ' Ops ',
    searchStages,
  );

  assert.ok(predicate);
  assert.equal(predicate?.({lensLabel: 'Customer Ops', 'stage-a': '', 'stage-b': ''}), true);
  assert.equal(predicate?.({lensLabel: 'Customer', 'stage-a': 'Needs OPS review', 'stage-b': ''}), true);
  assert.equal(predicate?.({lensLabel: 'Customer', 'stage-a': '', 'stage-b': 'No match'}), false);
});