// EXC-1 (US-EXC-1-07) — Plain-language sentences for the Health page
// Exceptions panel, kept pure so they're tested without a browser. The
// reader is the product manager at 11pm, not an engineer.
import {REASON_LABELS} from './exceptionSheet';

export function ageWords(days: number): string {
  if (days <= 0) return 'today';
  return days === 1 ? '1 day ago' : `${days} days ago`;
}

export function reasonWords(code: string): string {
  return (REASON_LABELS as Record<string, string>)[code] ?? code.replace(/_/g, ' ');
}

export function openChildSentence(r: {
  child_work_item_id: number;
  parent_work_item_id: number;
  parent_title: string;
  stage_label: string;
  target_map_title: string;
  moved_count: number;
  age_days: number;
  depth: number;
}): string {
  const what = r.moved_count > 0 ? `${r.moved_count} items` : 'work';
  const depth = r.depth > 1 ? ' (a child of a child)' : '';
  return `${r.parent_title} (#${r.parent_work_item_id}) sent ${what} to ${r.target_map_title} (#${r.child_work_item_id}) at ${r.stage_label}, ${ageWords(r.age_days)} — still open.${depth}`;
}
