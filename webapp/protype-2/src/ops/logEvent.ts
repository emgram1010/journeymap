// OBS-1 (US-OBS-1-02 client half; US-OBS-1-04; US-OBS-1-11) — The single
// place the app reports a client-side success, rejection or failure to
// POST /ops/event. Applies the dedup/rate gate before even trying to
// send, and falls back to the offline buffer when the request itself
// fails (never when the server validly rejects it — that's a real
// answer, not an offline condition).
import {ClientEventGate, OfflineEventBuffer, createBrowserStorage} from './clientEventBuffer';
import {fingerprint} from './fingerprint';
import {redact} from './redact';

export interface LogEventInput {
  feature: string;
  step: string;
  outcome: 'success' | 'rejected' | 'failure';
  severity?: 'info' | 'warn' | 'error';
  errorCode?: string | null;
  message?: string | null;
  entityType?: string | null;
  entityId?: number | null;
  correlationId?: string | null;
  durationMs?: number | null;
  metadata?: unknown;
}

// Shared singletons for the life of the page. Kept as module state
// (rather than React state) because logging must work from anywhere,
// including outside any component.
const gate = new ClientEventGate();
const offlineBuffer = new OfflineEventBuffer(typeof window !== 'undefined' ? createBrowserStorage() : undefined);

/** Overridable by tests; defaults to a real fetch against the ops/event endpoint. */
export type EventSender = (input: LogEventInput) => Promise<void>;

let sendImpl: EventSender = defaultSend;

export function __setEventSenderForTests(impl: EventSender | null): void {
  sendImpl = impl ?? defaultSend;
}

async function defaultSend(input: LogEventInput): Promise<void> {
  // Imported lazily to avoid a hard circular dependency between xano.ts
  // (which attaches a correlation id to every request) and this module.
  const {xanoRequest} = await import('../xano');
  await xanoRequest('/ops/event', {
    method: 'POST',
    body: {
      feature: input.feature,
      step: input.step,
      outcome: input.outcome,
      severity: input.severity,
      error_code: input.errorCode,
      message: input.message,
      entity_type: input.entityType,
      entity_id: input.entityId,
      correlation_id: input.correlationId,
      duration_ms: input.durationMs,
      metadata: input.metadata !== undefined ? redact(input.metadata) : undefined,
    },
  });
}

/** Attempts to flush anything the offline buffer is holding. Safe to call often; it is a no-op when the buffer is empty. */
export async function flushOfflineEvents(): Promise<void> {
  const pending = offlineBuffer.drain();
  for (const entry of pending) {
    try {
      await sendImpl({
        feature: entry.feature,
        step: entry.step,
        outcome: entry.outcome,
        errorCode: entry.errorCode,
        message: entry.message,
        metadata: entry.metadata,
      });
    } catch {
      // Still offline (or the server is down) — put it back and stop
      // trying the rest this pass; we'll retry on the next flush.
      offlineBuffer.add(entry);
      return;
    }
  }
}

export async function logEvent(input: LogEventInput): Promise<void> {
  const key = fingerprint({feature: input.feature, step: input.step, errorCode: input.errorCode});
  if (!gate.shouldSend(key)) return;

  try {
    await sendImpl(input);
  } catch {
    if (input.outcome === 'failure') {
      offlineBuffer.add({
        feature: input.feature,
        step: input.step,
        outcome: 'failure',
        errorCode: input.errorCode,
        message: input.message,
        metadata: input.metadata,
      });
    }
    // A rejected/success event that failed to send is simply dropped —
    // it is not critical enough to persist offline storage for.
  }
}

if (typeof window !== 'undefined') {
  window.addEventListener('online', () => {
    void flushOfflineEvents();
  });
}
