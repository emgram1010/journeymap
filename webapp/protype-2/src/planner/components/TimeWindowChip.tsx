// PUX-2 (US-PUX-2-01) — the one look for a job's time window, on every surface
// (Jobs column, Unscheduled, board cards, week view, job panel). Neutral when
// fine, amber when a slot sits outside it, nothing at all when there is none.
// One formatter (`formatWindow`) so the text never differs between screens.
import {Clock} from 'lucide-react';
import {formatWindow, windowChipState, type TimeWindow} from '../timeWindowModel';

interface TimeWindowChipProps {
  window: TimeWindow | null | undefined;
  /** Days this job's slots (or this one card) sit on; outside any → amber. */
  placedDays?: ReadonlyArray<string>;
  compact?: boolean;
  className?: string;
}

export function TimeWindowChip({window, placedDays = [], compact = false, className = ''}: TimeWindowChipProps) {
  const state = windowChipState(window, placedDays);
  if (state === 'none' || !window) return null;
  const outside = state === 'outside';
  return (
    <span
      // The amber state keeps TW-1's test id so its existing checks still find it.
      data-testid={outside ? 'dayboard-outside-window' : 'time-window-chip'}
      title={outside ? 'Scheduled outside its time window — soft limit, nothing is blocked' : 'When this job may happen'}
      className={`inline-flex items-center gap-1 rounded border px-1.5 py-0.5 font-medium ${compact ? 'text-[9px]' : 'text-[10px]'} ${
        outside ? 'text-amber-800 bg-amber-50 border-amber-200' : 'text-blue-800 bg-blue-50 border-blue-100'
      } ${className}`}
    >
      <Clock className="w-2.5 h-2.5 shrink-0" />
      <span className="truncate">
        {outside ? 'Outside window · ' : ''}
        {formatWindow(window)}
      </span>
    </span>
  );
}
