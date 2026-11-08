// PUX-4 (US-PUX-4-01) — "8h free ✓ / 2h free ⚠ / no time free ✗", shown only
// while a job is being dragged or placed. Advisory: nothing here blocks.
import {capacityFit, formatFree} from '../boardModel';

const STYLE = {
  fits: 'text-emerald-800 bg-emerald-50 border-emerald-200',
  over: 'text-amber-800 bg-amber-50 border-amber-200',
  full: 'text-red-700 bg-red-50 border-red-200',
} as const;

const MARK = {fits: '✓', over: '⚠', full: '✗'} as const;

export function CapacityHint({loadMinutes, capacityHours, addMinutes}: {loadMinutes: number; capacityHours: number; addMinutes: number}) {
  const fit = capacityFit(loadMinutes, capacityHours, addMinutes);
  return (
    <span
      data-testid="capacity-hint"
      data-state={fit.state}
      title={`${formatFree(fit.freeMinutes)} of ${capacityHours}h — this job needs ${addMinutes} min`}
      className={`inline-flex items-center gap-0.5 rounded border px-1 py-0.5 text-[9px] font-semibold ${STYLE[fit.state]}`}
    >
      {formatFree(fit.freeMinutes)} {MARK[fit.state]}
    </span>
  );
}
