// APP-1 — The performer app's own tiny HTTP client, against the
// PLANNER api group (not the journey-map group `xano.ts` targets).
//
// A SEPARATE FILE, NOT A REUSE OF `xanoRequest`. Two different Xano
// API groups means two different base URLs; `xano.ts`'s client is
// hard-wired to the journey-map group. This client also needs to
// parse a REJECTION'S OWN JSON BODY to pull out the clean server
// message (LOG-1's endpoints already write a friendly sentence into
// it) — `xanoRequest` only ever exposes the whole wrapped response
// text, which is enough for a diagnostic log but not for showing a
// performer a clean sentence.
import {getAuthToken, XanoHttpError} from '../xano';
import {CORRELATION_HEADER, newCorrelationId} from '../ops/correlationId';

const DEFAULT_PLANNER_BASE_URL = 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:PE5iDldw';

function trimTrailingSlash(value: string): string {
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

export function getPlannerBaseUrl(): string {
  const configured = import.meta.env.VITE_XANO_PLANNER_BASE_URL?.trim();
  return trimTrailingSlash(configured || DEFAULT_PLANNER_BASE_URL);
}

// PLN-9 — the journey-map group, needed by the planner's "add a map to
// this plan" picker. Same group `xano.ts` targets; declared here too so
// a caller can pass it as `baseUrl` below without reaching into that
// much larger module. Same bearer token works across groups, since both
// check it against the same `user` table.
const DEFAULT_JOURNEY_MAP_BASE_URL = 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:ER4MRRWZ';

export function getJourneyMapBaseUrl(): string {
  const configured = import.meta.env.VITE_XANO_JOURNEY_MAP_BASE_URL?.trim();
  return trimTrailingSlash(configured || DEFAULT_JOURNEY_MAP_BASE_URL);
}

// PLAN-2 — the "Members & Accounts" group, needed to list an account's
// users as candidates for tagging as an agent. Same bearer token works
// across groups, same reasoning as the journey-map base URL above.
const DEFAULT_ACCOUNTS_BASE_URL = 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:Fcgmwc6Y';

export function getAccountsBaseUrl(): string {
  const configured = import.meta.env.VITE_XANO_ACCOUNTS_BASE_URL?.trim();
  return trimTrailingSlash(configured || DEFAULT_ACCOUNTS_BASE_URL);
}

export interface PerformRequestOptions {
  // DELETE added by PLN-9: the planner can now remove an agent or a day.
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  body?: Record<string, unknown>;
  signal?: AbortSignal;
  /** Defaults to the planner group; pass getJourneyMapBaseUrl() for a journey-map call. */
  baseUrl?: string;
}

/**
 * Thrown for both a network-level failure (no response at all — offline,
 * DNS, CORS) and a non-2xx response. `offline` distinguishes the two,
 * because the two need different E-APP codes (`mapActionError` reads
 * this field directly).
 */
export class PerformRequestError extends XanoHttpError {
  offline: boolean;

  constructor(status: number, message: string, reference: string, offline: boolean) {
    super(status, message, reference);
    this.name = 'PerformRequestError';
    this.offline = offline;
  }
}

/**
 * Parses a rejection's JSON body for its `message` field — this is
 * where LOG-1's already-friendly sentences live (e.g. "This step is
 * blocked. Unblock it first. (E-LOG-001)"). Falls back to the raw text
 * when the body isn't JSON or has no `message`, so a malformed error
 * response still surfaces something rather than throwing a second time.
 */
function extractServerMessage(responseText: string): string | null {
  if (!responseText) return null;
  try {
    const parsed = JSON.parse(responseText) as {message?: unknown};
    return typeof parsed.message === 'string' ? parsed.message : null;
  } catch {
    return null;
  }
}

export async function performRequest<T>(path: string, options: PerformRequestOptions = {}): Promise<T> {
  const {method = 'GET', body, signal, baseUrl} = options;
  const token = getAuthToken();
  const correlationId = newCorrelationId();
  const headers: Record<string, string> = {Accept: 'application/json', [CORRELATION_HEADER]: correlationId};
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (body) headers['Content-Type'] = 'application/json';

  let response: Response;
  try {
    response = await fetch(`${baseUrl ?? getPlannerBaseUrl()}${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
      signal,
    });
  } catch (err) {
    // fetch itself threw: no connection, DNS failure, CORS — there is
    // no HTTP response to read a status from at all. This is exactly
    // what E-APP-001 means, not E-APP-002.
    const message = err instanceof Error ? err.message : 'Network request failed.';
    throw new PerformRequestError(0, message, correlationId, true);
  }

  const responseText = await response.text();

  if (!response.ok) {
    const serverMessage = extractServerMessage(responseText);
    throw new PerformRequestError(
      response.status,
      serverMessage ?? `Planner ${method} ${path} failed (${response.status}): ${responseText || response.statusText}`,
      correlationId,
      false,
    );
  }

  return responseText ? (JSON.parse(responseText) as T) : (undefined as T);
}

// ── Domain calls (US-APP-1-02, -04) ───────────────────────────────────────

import type {PerformerSnapshot, StatusMap, TaskStatus} from './performerView';

export interface TodayResponse {
  date: string;
  agent_ids: number[];
  snapshot: PerformerSnapshot;
  statuses: StatusMap;
}

/** `date` omitted lets the server decide "today" (the timezone seam — see `perform/today_for`'s own header). */
export const fetchToday = (date?: string) => performRequest<TodayResponse>(`/perform/today${date ? `?date=${encodeURIComponent(date)}` : ''}`);

export type PerformEventType = 'started' | 'completed' | 'blocked' | 'unblocked' | 'skipped' | 'reopened' | 'note';

export interface RecordEventInput {
  workTaskId: number;
  eventType: PerformEventType;
  clientEventId: string;
  reasonCode?: string;
  note?: string;
}

export interface RecordEventResponse {
  work_task: {id: number; status: TaskStatus; started_at: number | null; completed_at: number | null};
  from: TaskStatus;
  to: TaskStatus;
  job_status: string;
  duplicate: boolean;
  stage: {stage_key: string; complete: boolean} | null;
  all_stages_complete: boolean;
}

/** Hits LOG-1's `work_task/{id}/event` — the only thing allowed to move a task's status. */
export const recordEvent = (input: RecordEventInput) =>
  performRequest<RecordEventResponse>(`/work_task/${input.workTaskId}/event`, {
    method: 'POST',
    body: {
      event_type: input.eventType,
      client_event_id: input.clientEventId,
      reason_code: input.reasonCode,
      note: input.note,
    },
  });
