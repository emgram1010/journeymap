import type {OpsStepUpRow, OpsStepUpsResponse} from '../xano';

/**
 * COP-13 story 05 (Health part) - plain words for the "Stronger model" panel. Kept out of the
 * component so it can be tested without a browser. Days are UTC day numbers (days since 1970-01-01).
 */
const DAY_MS = 86_400_000;
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export function dayLabel(day: number): string {
  const d = new Date(day * DAY_MS);
  return `${WEEKDAYS[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

export function stepUpsSummary(r: Pick<OpsStepUpsResponse, 'days' | 'rows'>): string {
  const sum = (k: keyof OpsStepUpRow) => r.rows.reduce((a, x) => a + (Number(x[k]) || 0), 0);
  const asked = sum('requested');
  if (asked === 0) return `No requests to use the stronger model in the last ${r.days} days.`;
  const parts = [
    `${sum('approved')} approved`,
    `${sum('declined')} declined`,
    sum('expired') ? `${sum('expired')} expired` : '',
    sum('capped') ? `${sum('capped')} refused by the daily limit` : '',
    sum('waiting') ? `${sum('waiting')} still waiting` : '',
  ].filter(Boolean);
  return `${plural(asked, 'request', 'requests')} to use the stronger model in the last ${r.days} days: ${parts.join(', ')}. ${sum('ran')} re-done on the stronger model.`;
}

export function stepUpRowText(x: OpsStepUpRow): string {
  const bits = [
    `${x.requested} asked`,
    x.approved ? `${x.approved} approved` : '',
    x.declined ? `${x.declined} declined` : '',
    x.expired ? `${x.expired} expired` : '',
    x.capped ? `${x.capped} refused by the daily limit` : '',
    x.waiting ? `${x.waiting} waiting` : '',
    x.ran ? `${x.ran} re-done` : '',
  ].filter(Boolean);
  return `${dayLabel(x.day)} - ${x.business || 'Unknown business'}: ${bits.join(', ')}`;
}
