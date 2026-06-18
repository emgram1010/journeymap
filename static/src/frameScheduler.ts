export type AnimationFrameScheduler = {
  requestAnimationFrame(callback: () => void): number;
  cancelAnimationFrame(handle: number): void;
};

export const cancelScheduledAnimationFrame = (
  scheduler: AnimationFrameScheduler,
  handle: number | null,
) => {
  if (handle !== null) {
    scheduler.cancelAnimationFrame(handle);
  }
  return null;
};

export const scheduleAnimationFrame = (
  scheduler: AnimationFrameScheduler,
  handle: number | null,
  callback: () => void,
) => {
  cancelScheduledAnimationFrame(scheduler, handle);
  return scheduler.requestAnimationFrame(callback);
};