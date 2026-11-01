// Date utilities for Emgram Planner planning window and schedule

export function formatShortDate(dateStr: string): string {
  if (!dateStr) return '';
  try {
    const parts = dateStr.split('-').map(Number);
    if (parts.length < 3) return dateStr;
    const [year, month, day] = parts;
    const date = new Date(year, month - 1, day);
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  } catch {
    return dateStr;
  }
}

export function formatMonthDayYear(dateStr: string): string {
  if (!dateStr) return '';
  try {
    const parts = dateStr.split('-').map(Number);
    if (parts.length < 3) return dateStr;
    const [year, month, day] = parts;
    const date = new Date(year, month - 1, day);
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  } catch {
    return dateStr;
  }
}

export function getDaysDifference(startStr: string, endStr: string): number {
  if (!startStr || !endStr) return 0;
  try {
    const d1 = new Date(startStr);
    const d2 = new Date(endStr);
    const diffTime = d2.getTime() - d1.getTime();
    const diffDays = Math.round(diffTime / (1000 * 60 * 60 * 24)) + 1;
    return Math.max(1, diffDays);
  } catch {
    return 1;
  }
}

export function isDateOutOfWindow(dateStr: string, windowStart: string, windowEnd: string): boolean {
  if (!dateStr || !windowStart || !windowEnd) return false;
  return dateStr < windowStart || dateStr > windowEnd;
}

// WIN-1 (US-WIN-1-02): the plan's planning window, as day columns and as
// date-picker bounds. Before this, the Schedule grid rendered a fixed
// spanWeeks * 7 days from the window start and the pickers had no min/max
// at all, so a 3-day plan still offered a droppable fortnight. Both ends
// of a window are inclusive (D-6).

/** Every day in the window, inclusive of both ends. `[]` if either end is missing. */
export function getWindowDays(windowStart: string, windowEnd: string): string[] {
  if (!windowStart || !windowEnd) return [];
  // A backwards window degrades to its start day: getDaysDifference
  // floors at 1, so this is one column rather than none.
  return generateDaysList(windowStart, getDaysDifference(windowStart, windowEnd));
}

export interface WindowPage {
  days: string[];
  rangeStart: string;
  rangeEnd: string;
  canPagePrev: boolean;
  canPageNext: boolean;
}

/**
 * One page of day columns, clamped to the window. `pageOffsetDays` is
 * clamped too — the grid holds it in component state, so it can outlive
 * the window it was measured against.
 */
export function getWindowPage(
  windowStart: string,
  windowEnd: string,
  pageSizeDays: number,
  pageOffsetDays: number
): WindowPage {
  const all = getWindowDays(windowStart, windowEnd);
  if (all.length === 0) {
    return { days: [], rangeStart: '', rangeEnd: '', canPagePrev: false, canPageNext: false };
  }
  const size = Math.max(1, Math.floor(pageSizeDays) || 1);
  const offset = Math.min(Math.max(0, Math.floor(pageOffsetDays) || 0), all.length - 1);
  const days = all.slice(offset, offset + size);
  return {
    days,
    rangeStart: days[0],
    rangeEnd: days[days.length - 1],
    canPagePrev: offset > 0,
    canPageNext: offset + days.length < all.length,
  };
}

/**
 * `min`/`max` for an `<input type="date">` that writes a planned date.
 * Both ends or neither: a half-bounded picker would refuse valid days on
 * the unbounded side. The server stays the authority (D-5).
 */
export function getWindowBounds(
  windowStart?: string | null,
  windowEnd?: string | null
): { min?: string; max?: string } {
  if (!windowStart || !windowEnd) return {};
  return { min: windowStart, max: windowEnd };
}

export function generateDaysList(startStr: string, daysCount: number): string[] {
  const days: string[] = [];
  try {
    const [y, m, d] = startStr.split('-').map(Number);
    const current = new Date(y, m - 1, d);
    for (let i = 0; i < daysCount; i++) {
      const year = current.getFullYear();
      const month = String(current.getMonth() + 1).padStart(2, '0');
      const day = String(current.getDate()).padStart(2, '0');
      days.push(`${year}-${month}-${day}`);
      current.setDate(current.getDate() + 1);
    }
  } catch (err) {
    console.error('Error generating days list:', err);
  }
  return days;
}
