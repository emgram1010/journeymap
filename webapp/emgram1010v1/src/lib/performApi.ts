// PLN-9 — The transport layer here is kept byte-identical in spirit to
// webapp/protype-2/src/perform/performApi.ts's own `performRequest`/
// `PerformRequestError` (same planner API group, same error shape). The
// APP-1-specific domain calls at the bottom of that file do NOT belong
// here — this file's own domain calls are planner-specific and live in
// plannerApi.ts instead. See EPIC-PLN-9-planner-frontend-wiring.md's
// "HTTP client" decision for why this is a deliberate duplication, not
// an import.
import {getAuthToken, XanoHttpError} from './xanoHttpError';
import {CORRELATION_HEADER, newCorrelationId} from './correlationId';

const DEFAULT_PLANNER_BASE_URL = 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:PE5iDldw';

function trimTrailingSlash(value: string): string {
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

export function getPlannerBaseUrl(): string {
  const configured = import.meta.env.VITE_XANO_PLANNER_BASE_URL?.trim();
  return trimTrailingSlash(configured || DEFAULT_PLANNER_BASE_URL);
}

// PLN-9 (US-PLN-9-06) — the journey-map group, needed only to list
// candidate maps for "add a map to this plan" (journey_map/search).
// Same base URL protype-2's own xano.ts already uses for this group;
// same bearer token works across groups since both check it against
// the same `user` table.
const DEFAULT_JOURNEY_MAP_BASE_URL = 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:ER4MRRWZ';

export function getJourneyMapBaseUrl(): string {
  const configured = import.meta.env.VITE_XANO_JOURNEY_MAP_BASE_URL?.trim();
  return trimTrailingSlash(configured || DEFAULT_JOURNEY_MAP_BASE_URL);
}

export interface PerformRequestOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  body?: Record<string, unknown>;
  signal?: AbortSignal;
  /** Defaults to the planner group; pass getJourneyMapBaseUrl() for a journey-map call. */
  baseUrl?: string;
}

/**
 * Thrown for both a network-level failure (no response at all — offline,
 * DNS, CORS) and a non-2xx response. `offline` distinguishes the two.
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
 * Parses a rejection's JSON body for its `message` field — every
 * phase-4 rejection already writes a friendly sentence into it (VAL-1).
 * Falls back to the raw text when the body isn't JSON or has no
 * `message`, so a malformed error response still surfaces something.
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
