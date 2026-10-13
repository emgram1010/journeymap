import assert from 'node:assert/strict';
import test from 'node:test';
import {resolveOwner, doesPlannedWork} from './stageOwnerModel';

const lenses = [
  {key: 'lens-2', xanoId: 1003},
  {key: 'lens-3', xanoId: 1004},
];

test('UT-STAGE-1-01: resolveOwner with a matching key returns the lens id', () => {
  assert.deepEqual(resolveOwner('lens-2', lenses), {resolved: true, ownerLensId: 1003});
  assert.deepEqual(resolveOwner('lens-3', lenses), {resolved: true, ownerLensId: 1004});
});

test('UT-STAGE-1-02: resolveOwner with a key matching nothing / empty / null never throws', () => {
  assert.deepEqual(resolveOwner('does-not-exist', lenses), {
    resolved: false,
    reason: "no lens in this map matches key 'does-not-exist'",
  });
  assert.deepEqual(resolveOwner('', lenses), {resolved: true, ownerLensId: null});
  assert.deepEqual(resolveOwner(null, lenses), {resolved: true, ownerLensId: null});
  assert.deepEqual(resolveOwner(undefined, lenses), {resolved: true, ownerLensId: null});
});

test('UT-STAGE-1-05: doesPlannedWork defaults by actor_type, override wins', () => {
  assert.equal(doesPlannedWork('customer', null), false);
  assert.equal(doesPlannedWork('internal', null), true);
  assert.equal(doesPlannedWork('ai_agent', null), true);
  assert.equal(doesPlannedWork('vendor', undefined), false);
  // explicit override always wins over the type default
  assert.equal(doesPlannedWork('customer', true), true);
  assert.equal(doesPlannedWork('internal', false), false);
});

test('doesPlannedWork with no actor_type and no override defaults to false', () => {
  assert.equal(doesPlannedWork(null, null), false);
  assert.equal(doesPlannedWork(undefined, undefined), false);
});
