// APP-1 (E2E-APP-1-G03) — Catches a render-time crash in the performer
// screen and shows a friendly recovery state instead of a blank page.
//
// `ops/globalErrorHandler.ts` already reports `window.onerror` and
// unhandled promise rejections under `feature: 'CLIENT'`, but React
// swallows a render-time throw before it ever reaches `window` — only
// a real error boundary sees it. This one is scoped to the /perform
// route rather than wrapping the whole app, so a crash here cannot
// take down screens that have nothing to do with it.
import React from 'react';
import {logEvent} from '../ops/logEvent';
import {newCorrelationId} from '../ops/correlationId';

interface Props {
  children: React.ReactNode;
}

interface State {
  reference: string | null;
}

export class PerformErrorBoundary extends React.Component<Props, State> {
  state: State = {reference: null};

  static getDerivedStateFromError(): State {
    return {reference: newCorrelationId()};
  }

  componentDidCatch(error: Error): void {
    void logEvent({
      feature: 'APP-1',
      step: 'client_error',
      outcome: 'failure',
      message: error.message || 'Unhandled exception in the performer screen.',
      correlationId: this.state.reference,
      metadata: {screen: 'perform'},
    });
  }

  render() {
    if (this.state.reference) {
      return (
        <div className="min-h-screen bg-zinc-50 flex items-center justify-center p-6">
          <div className="max-w-sm text-center">
            <p className="text-sm text-zinc-700">Something went wrong. We've recorded it.</p>
            <p className="mt-2 text-xs text-zinc-400">Reference: {this.state.reference}</p>
            <button
              type="button"
              onClick={() => this.setState({reference: null})}
              className="mt-4 rounded-lg bg-zinc-900 px-4 py-2 text-sm text-white"
            >
              Try again
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
