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
