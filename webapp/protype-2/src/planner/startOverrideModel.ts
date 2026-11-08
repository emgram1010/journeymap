// SCHED-2 (US-SCHED-2-03) — what saving the "Planned Start" field means.
// Pure, no imports. The server re-checks every rule (planner_task/{id}/start-override).

export const START_OVERRIDE_FORMAT_MESSAGE = 'Enter the start time as two digits each, like 09:00.';

const HHMM = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;

export type StartOverrideChange =
  | {kind: 'none'}
  | {kind: 'set'; value: string}
  | {kind: 'clear'}
  | {kind: 'invalid'; message: string};

/**
 * `original` is the step as loaded; `draft` is what the field holds now;
 * `useComputed` is the "Use computed time" choice. A backlog step has no
 * day and so no start to change.
 */
export function startOverrideChange(
  original: {planned_start: string; startOverride?: string},
  draft: string,
  useComputed: boolean,
  isBacklog: boolean,
): StartOverrideChange {
  if (isBacklog) return {kind: 'none'};
  const hasOverride = !!original.startOverride;
  if (useComputed) return hasOverride ? {kind: 'clear'} : {kind: 'none'};
  const value = draft.trim();
  if (value === (original.planned_start || '')) return {kind: 'none'};
  if (!HHMM.test(value)) return {kind: 'invalid', message: START_OVERRIDE_FORMAT_MESSAGE};
  return {kind: 'set', value};
}
