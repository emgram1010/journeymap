import {useEffect, useState} from 'react';
import {getAccountCopilot} from '../xano';
import type {CopilotInfo} from './aiAgentModel';

/**
 * COP-5 story 06 — the account's copilot (who it is, on or off), shared by every planner component
 * that marks or guards the copilot's column. A failed load resolves to `null` ("unknown"), and
 * unknown never blocks anything (see aiAgentModel.isSwitchedOffCopilot).
 *
 * Final review R12: the answer used to be kept for the life of the page, failures included. So a
 * copilot switched off on Manage users was still offered in the planner, and one failed lookup was
 * never retried. Now a failure is not kept, an answer is reused for one minute, and switching any
 * user on or off (Manage users) refreshes it at once.
 */
export const COPILOT_CHANGED_EVENT = 'emgram:copilot-changed';
export const COPILOT_CACHE_MS = 60_000;

type Entry = {promise: Promise<CopilotInfo | null>; loadedAt: number; failed: boolean};
let cached: Entry | null = null;

/** Pure rule, tested: reload when nothing is kept, the last load failed, or it is older than a minute. */
export function shouldReloadCopilot(entry: {loadedAt: number; failed: boolean} | null, now: number): boolean {
  if (!entry) return true;
  if (entry.failed) return true;
  return now - entry.loadedAt >= COPILOT_CACHE_MS;
}

export function loadAccountCopilot(force = false): Promise<CopilotInfo | null> {
  const now = Date.now();
  if (force || shouldReloadCopilot(cached, now)) {
    const entry: Entry = {promise: Promise.resolve(null), loadedAt: now, failed: false};
    entry.promise = getAccountCopilot()
      .then((c) => ({has_copilot: !!c.has_copilot, user_id: c.user_id || 0, name: c.name || '', is_active: c.is_active !== false}))
      .catch(() => {
        entry.failed = true;
        return null;
      });
    cached = entry;
  }
  return cached!.promise;
}

/** Called after a user is switched on or off, so every open planner view asks again. */
export function announceCopilotChanged(): void {
  cached = null;
  if (typeof window !== 'undefined') window.dispatchEvent(new Event(COPILOT_CHANGED_EVENT));
}

export function useAccountCopilot(): CopilotInfo | null {
  const [copilot, setCopilot] = useState<CopilotInfo | null>(null);
  useEffect(() => {
    let alive = true;
    const refresh = (force: boolean) => {
      void loadAccountCopilot(force).then((c) => {
        if (alive) setCopilot(c);
      });
    };
    refresh(false);
    const onChanged = () => refresh(true);
    const onFocus = () => refresh(false);
    window.addEventListener(COPILOT_CHANGED_EVENT, onChanged);
    window.addEventListener('focus', onFocus);
    return () => {
      alive = false;
      window.removeEventListener(COPILOT_CHANGED_EVENT, onChanged);
      window.removeEventListener('focus', onFocus);
    };
  }, []);
  return copilot;
}
