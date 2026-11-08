// EXEC-1 (US-EXEC-1-01) — one status pill, used by Today, the job screen and
// the step screen. Always shows an icon AND the word, never color alone
// (accessibility rule from the design prompt).
import {STATUS_CONFIG} from './statusConfig';
import type {TaskStatus} from '../performerView';

export type StatusPillSize = 'sm' | 'md';

const SIZE_CLASSES: Record<StatusPillSize, string> = {
  sm: 'text-[11px] py-1 px-2 gap-1',
  md: 'text-xs py-1.5 px-3 gap-1.5',
};

const ICON_SIZES: Record<StatusPillSize, string> = {
  sm: 'w-3 h-3',
  md: 'w-3.5 h-3.5',
};

export default function StatusPill({
  status,
  size = 'md',
  className = '',
  labelOverride,
}: {
  status: TaskStatus;
  size?: StatusPillSize;
  className?: string;
  /** e.g. "Next" on the step that's highlighted — same icon/color as its real status, different word. The `aria-label` still announces the real status, so screen readers aren't told a highlighted step is a new status. */
  labelOverride?: string;
}) {
  const config = STATUS_CONFIG[status];
  const Icon = config.icon;
  return (
    <span
      role="status"
      aria-label={`Status: ${config.label}`}
      className={`inline-flex shrink-0 items-center justify-center rounded-full font-medium whitespace-nowrap ${config.pillClassName} ${SIZE_CLASSES[size]} ${className}`}
    >
      <Icon className={`${ICON_SIZES[size]} shrink-0`} aria-hidden="true" />
      <span>{labelOverride ?? config.label}</span>
    </span>
  );
}
