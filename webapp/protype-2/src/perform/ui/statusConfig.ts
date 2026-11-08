// EXEC-1 (US-EXEC-1-01) — the single source of truth for how a TaskStatus
// looks, everywhere in the performer app. Replaces three separate copies of
// STATUS_LABELS/STATUS_COLORS that used to live in TodayScreen, SessionScreen
// and StepScreen (confirmed identical before this file existed).
//
// Pure data, no React import, so it's testable on its own and safe for any
// screen (including non-visual code, like a notification subject line) to
// read a status's label without pulling in JSX.
import {Circle, PlayCircle, AlertOctagon, CheckCircle2, FastForward, type LucideIcon} from 'lucide-react';
import type {TaskStatus} from '../performerView';

export interface StatusConfig {
  label: string;
  icon: LucideIcon;
  /** Tailwind classes for a pill/badge background + text. */
  pillClassName: string;
  /** Hex color for non-Tailwind surfaces (e.g. an SVG progress ring stroke). */
  ringColor: string;
}

export const STATUS_CONFIG: Record<TaskStatus, StatusConfig> = {
  not_started: {
    label: 'Not started',
    icon: Circle,
    pillClassName: 'bg-zinc-100 text-zinc-600',
    ringColor: '#a1a1aa',
  },
  in_progress: {
    label: 'In progress',
    icon: PlayCircle,
    pillClassName: 'bg-blue-100 text-blue-800',
    ringColor: '#2563eb',
  },
  blocked: {
    label: 'Blocked',
    icon: AlertOctagon,
    pillClassName: 'bg-red-100 text-red-800',
    ringColor: '#dc2626',
  },
  done: {
    label: 'Done',
    icon: CheckCircle2,
    pillClassName: 'bg-emerald-100 text-emerald-800',
    ringColor: '#16a34a',
  },
  skipped: {
    label: 'Skipped',
    icon: FastForward,
    pillClassName: 'bg-zinc-200 text-zinc-500',
    ringColor: '#71717a',
  },
};

export const ALL_STATUSES: TaskStatus[] = ['not_started', 'in_progress', 'blocked', 'done', 'skipped'];
