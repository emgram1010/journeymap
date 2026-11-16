import {getCatalogEntry} from '../ops/errorCatalog';
import type {OpsToolCallRefusal, OpsToolCallsResponse} from '../xano';

/**
 * COP-1 story 04 - plain words for the Health page "AI tool calls" panel. Kept out of the
 * component so it can be tested without a browser.
 */
export function toolCallsSummary(r: Pick<OpsToolCallsResponse, 'total' | 'allowed' | 'refused' | 'outside' | 'since_hours'>): string {
  if (r.total === 0) return `No AI tool calls in the last ${r.since_hours} hours.`;
  const calls = r.total === 1 ? '1 AI tool call' : `${r.total} AI tool calls`;
  const outside = r.outside > 0 ? `, ${r.outside} from an outside assistant` : '';
  return `${calls} in the last ${r.since_hours} hours${outside}: ${r.allowed} allowed, ${r.refused} refused.`;
}

/** What a refusal means, from the error catalog; the code itself if it is not catalogued. */
export function refusalMeaning(row: Pick<OpsToolCallRefusal, 'code'>): string {
  if (!row.code) return 'Refused (no reason code recorded).';
  return getCatalogEntry(row.code)?.user_message ?? row.code;
}

export function refusalWho(row: Pick<OpsToolCallRefusal, 'user_id' | 'account_id' | 'context'>): string {
  const where = row.context === 'outside' ? 'outside assistant' : 'inside Emgram';
  if (!row.user_id) return `Unknown caller, ${where}`;
  return `User ${row.user_id}, account ${row.account_id}, ${where}`;
}
