// VAL-1 (US-VAL-1-04) — The summary banner shown for several errors,
// an unexpected server/network failure, a stale write, or "you don't
// have access". One component, driven by a `kind` so the wording and
// action always match what actually happened — never a raw error, never
// a stack trace (see docs/error-message-style.md).
import React from 'react';

export type ErrorBannerKind = 'validation' | 'server' | 'offline' | 'access_denied' | 'stale_write';

export interface ErrorBannerProps {
  kind: ErrorBannerKind;
  message?: string;
  /** Shown as "Reference: {reference}" on an unexpected error, so the user can quote it for support. */
  reference?: string | null;
  onReload?: () => void;
  onRetry?: () => void;
}

const DEFAULT_MESSAGE: Record<ErrorBannerKind, string> = {
  validation: 'Please fix the highlighted fields below.',
  server: "We couldn't save your changes. Your work is still here.",
  offline: 'No connection. Reconnect to continue.',
  access_denied: "You don't have access to do this.",
  stale_write: 'Someone else changed this. Reload to see the latest.',
};

export default function ErrorBanner({kind, message, reference, onReload, onRetry}: ErrorBannerProps) {
  const text = message ?? DEFAULT_MESSAGE[kind];
  return (
    <div className="rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800" role="alert">
      <div>{text}</div>
      {reference && <div className="text-xs text-red-600 mt-1">Reference: {reference}</div>}
      {(kind === 'stale_write' || kind === 'server') && onReload && (
        <button type="button" onClick={onReload} className="text-xs underline mt-1">
          Reload
        </button>
      )}
      {kind === 'server' && onRetry && (
        <button type="button" onClick={onRetry} className="text-xs underline mt-1 ml-3">
          Try again
        </button>
      )}
    </div>
  );
}
