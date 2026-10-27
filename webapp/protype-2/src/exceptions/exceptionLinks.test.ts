import assert from 'node:assert/strict';
import test from 'node:test';
import {exceptionLinksForStage, childTitle, CHILD_TITLE_MAX} from './exceptionLinks';

test('UT-EXC-1-05: only exception links for the stage, any lens, one per target', () => {
  const snapshot = {
    links: [
      {stage_key: 's2', lens_key: 'description', link_type: 'exception', target_map_id: 220},
      {stage_key: 's2', lens_key: 'items', link_type: 'exception', target_map_id: 220}, // duplicate target
      {stage_key: 's2', lens_key: 'lens-2', link_type: 'exception', target_map_id: 222},
      {stage_key: 's2', lens_key: 'items', link_type: 'sub_journey', target_map_id: 193}, // how-to, never a handoff
      {stage_key: 's1', lens_key: 'lens-2', link_type: 'exception', target_map_id: 300}, // other stage
      {stage_key: 's2', lens_key: 'lens-2', link_type: 'anti_journey', target_map_id: 301},
    ],
  };
  assert.deepEqual(exceptionLinksForStage(snapshot, 's2'), [
    {stage_key: 's2', lens_key: 'description', target_map_id: 220},
    {stage_key: 's2', lens_key: 'lens-2', target_map_id: 222},
  ]);
});

test('exceptionLinksForStage tolerates a v1 snapshot with no links and junk rows', () => {
  assert.deepEqual(exceptionLinksForStage({}, 's2'), []);
  assert.deepEqual(exceptionLinksForStage({links: null}, 's2'), []);
  assert.deepEqual(
    exceptionLinksForStage({links: [{stage_key: 's2', lens_key: 'x', link_type: 'exception', target_map_id: 0}]}, 's2'),
    [],
  );
});

test('UT-EXC-1-06a: no items moved — no suffix; the link label wins over the target title', () => {
  assert.equal(childTitle('Order 482', 'Repair', 'Repair map', []), 'Order 482 · Repair');
  assert.equal(childTitle('Order 482', '', 'Repair map', []), 'Order 482 · Repair map');
});

test('UT-EXC-1-06b: one item type — its count and label', () => {
  assert.equal(childTitle('Order 482', '', 'Repair', [{quantity: 2, label: 'tables'}]), 'Order 482 · Repair (2 tables)');
});

test('UT-EXC-1-06c: several item types — the total and "items"', () => {
  assert.equal(
    childTitle('Order 482', '', 'Repair', [
      {quantity: 2, label: 'tables'},
      {quantity: 3, label: 'chairs'},
    ]),
    'Order 482 · Repair (5 items)',
  );
});

test('UT-EXC-1-06d: over 120 characters — the base is cut so the count survives', () => {
  const long = 'x'.repeat(200);
  const title = childTitle(long, '', 'Repair', [{quantity: 2, label: 'tables'}]);
  assert.equal(title.length, CHILD_TITLE_MAX);
  assert.ok(title.endsWith(' (2 tables)'));
  const noSuffix = childTitle(long, '', 'Repair', []);
  assert.equal(noSuffix.length, CHILD_TITLE_MAX);
});

test('childTitle trims a cut that lands on a space', () => {
  const base = 'a'.repeat(110) + '          ' + 'b'.repeat(20);
  const title = childTitle(base, '', 'R', []);
  assert.ok(title.length <= CHILD_TITLE_MAX);
  assert.ok(!title.endsWith(' '));
});

import {stageExceptionTargets, LINK_TYPE_HELP} from './exceptionLinks';

test('EXC-1: stageExceptionTargets groups exception links by stage, de-duplicated, titles resolved', () => {
  const links = [
    {sourceCellId: 1, linkType: 'exception', targetMapId: 220},
    {sourceCellId: 2, linkType: 'exception', targetMapId: 220}, // same stage, same target
    {sourceCellId: 2, linkType: 'exception', targetMapId: 222},
    {sourceCellId: 3, linkType: 'sub_journey', targetMapId: 193}, // never a handoff
    {sourceCellId: 4, linkType: 'exception', targetMapId: 999}, // unknown title
    {sourceCellId: 99, linkType: 'exception', targetMapId: 220}, // cell not on this map
  ];
  const stageOfCell = new Map<number, string>([[1, 'st-a'], [2, 'st-a'], [3, 'st-b'], [4, 'st-c']]);
  const titles = new Map<number, string>([[220, 'Repair'], [222, 'Never published']]);
  assert.deepEqual(stageExceptionTargets(links, stageOfCell, titles), {
    'st-a': ['Repair', 'Never published'],
    'st-c': ['map #999'],
  });
});

test('EXC-1: the link picker explains each link type in one plain line', () => {
  assert.match(LINK_TYPE_HELP.exception, /leaves this journey/);
  assert.match(LINK_TYPE_HELP.sub_journey, /never starts a separate job/);
  assert.ok(LINK_TYPE_HELP.anti_journey.length > 0);
});
