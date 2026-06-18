import assert from 'node:assert/strict';
import test from 'node:test';
import {buildSelectedCellPayload} from './xano';

test('buildSelectedCellPayload returns null when there is no selected cell', () => {
  assert.equal(buildSelectedCellPayload(null), null);
});

test('buildSelectedCellPayload converts selected cell context to the AI payload shape', () => {
  const result = buildSelectedCellPayload({
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

  assert.deepEqual(result, {
    journey_map_id: 42,
    journey_cell_id: 100,
    stage_id: 12,
    stage_key: 's2',
    stage_label: 'Fulfillment',
    lens_id: 22,
    lens_key: 'notifications',
    lens_label: 'Notifications',
    reference: 'Fulfillment × Notifications',
    shorthand: 'S2-L2',
  });
});