// EXEC-1 (US-EXEC-1-04) — the Overview tab's progress ring. Pure
// display over `jobProgress`'s output; no job/session logic lives
// here. The arc's color is the shared "done" status color
// (`statusConfig.ts`), so it reads the same way the status pills do.
import {STATUS_CONFIG} from './statusConfig';
import type {JobProgress} from '../sessionModel';

export default function ProgressRing({
  progress,
  size = 64,
  strokeWidth = 6,
}: {
  progress: JobProgress;
  size?: number;
  strokeWidth?: number;
}) {
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const dashOffset = circumference - (progress.percent / 100) * circumference;

  return (
    <div className="flex items-center gap-3">
      <div className="relative shrink-0" style={{width: size, height: size}}>
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90" aria-hidden="true">
          <circle cx={size / 2} cy={size / 2} r={radius} stroke="currentColor" strokeWidth={strokeWidth} fill="none" className="text-zinc-100" />
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            stroke={STATUS_CONFIG.done.ringColor}
            strokeWidth={strokeWidth}
            strokeDasharray={circumference}
            strokeDashoffset={dashOffset}
            strokeLinecap="round"
            fill="none"
          />
        </svg>
        <span className="absolute inset-0 flex items-center justify-center text-sm font-bold text-zinc-900 tabular-nums">
          {progress.percent}%
        </span>
      </div>
      <div className="min-w-0">
        <p className="text-sm font-semibold text-zinc-900">
          {progress.doneCount} of {progress.totalCount} step{progress.totalCount === 1 ? '' : 's'} done
        </p>
        {(progress.blockedCount > 0 || progress.skippedCount > 0) && (
          <p className="mt-0.5 text-xs text-zinc-500">
            {progress.blockedCount > 0 && <span className="font-medium text-red-700">{progress.blockedCount} blocked</span>}
            {progress.blockedCount > 0 && progress.skippedCount > 0 && ' · '}
            {progress.skippedCount > 0 && <span className="font-medium text-zinc-500">{progress.skippedCount} skipped</span>}
          </p>
        )}
      </div>
    </div>
  );
}
