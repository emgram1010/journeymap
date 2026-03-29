import assert from 'node:assert/strict';
import test from 'node:test';
import {
  cancelScheduledAnimationFrame,
  scheduleAnimationFrame,
  type AnimationFrameScheduler,
} from './frameScheduler';

const createScheduler = () => {
  let nextHandle = 1;
  const cancelled: number[] = [];
  const queued = new Map<number, () => void>();

  const scheduler: AnimationFrameScheduler = {
    requestAnimationFrame(callback) {
      const handle = nextHandle++;
      queued.set(handle, callback);
      return handle;
    },
    cancelAnimationFrame(handle) {
      cancelled.push(handle);
      queued.delete(handle);
    },
  };

  return {scheduler, cancelled, queued};
};

test('scheduleAnimationFrame defers callback execution until the scheduled frame runs', () => {
  const {scheduler, queued} = createScheduler();
  let didRun = false;

  const handle = scheduleAnimationFrame(scheduler, null, () => {
    didRun = true;
  });

  assert.equal(didRun, false);
  queued.get(handle)?.();
  assert.equal(didRun, true);
});

test('scheduleAnimationFrame cancels the previous pending frame before replacing it', () => {
  const {scheduler, cancelled, queued} = createScheduler();

  const firstHandle = scheduleAnimationFrame(scheduler, null, () => {});
  const secondHandle = scheduleAnimationFrame(scheduler, firstHandle, () => {});

  assert.deepEqual(cancelled, [firstHandle]);
  assert.equal(queued.has(firstHandle), false);
  assert.equal(queued.has(secondHandle), true);
});

test('cancelScheduledAnimationFrame is a no-op for null and clears pending handles', () => {
  const {scheduler, cancelled, queued} = createScheduler();

  assert.equal(cancelScheduledAnimationFrame(scheduler, null), null);
  assert.deepEqual(cancelled, []);

  const handle = scheduleAnimationFrame(scheduler, null, () => {});
  assert.equal(cancelScheduledAnimationFrame(scheduler, handle), null);
  assert.deepEqual(cancelled, [handle]);
  assert.equal(queued.has(handle), false);
});