// OBS-1 (US-OBS-1-04) — Catches unhandled front-end errors and reports
// them the same way a failed API call is reported, so a crashing screen
// shows up on the Health page with a Reference the user can quote.
import {logEvent} from './logEvent';
import {newCorrelationId} from './correlationId';

let installed = false;

export function installGlobalErrorHandler(): void {
  if (installed || typeof window === 'undefined') return;
  installed = true;

  window.addEventListener('error', (event) => {
    void logEvent({
      feature: 'CLIENT',
      step: 'unhandled_error',
      outcome: 'failure',
      message: event.message || 'An unexpected error occurred.',
      correlationId: newCorrelationId(),
      metadata: {filename: event.filename, lineno: event.lineno, colno: event.colno},
    });
  });

  window.addEventListener('unhandledrejection', (event) => {
    const reason = event.reason;
    const message = reason instanceof Error ? reason.message : String(reason);
    void logEvent({
      feature: 'CLIENT',
      step: 'unhandled_rejection',
      outcome: 'failure',
      message: message || 'An unexpected error occurred.',
      correlationId: newCorrelationId(),
    });
  });
}

/** Exposed only for tests, to reset the install guard between test cases. */
export function __resetGlobalErrorHandlerForTests(): void {
  installed = false;
}
