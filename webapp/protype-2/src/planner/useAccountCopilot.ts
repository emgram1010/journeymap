import {useEffect, useState} from 'react';
import {getAccountCopilot} from '../xano';
import type {CopilotInfo} from './aiAgentModel';

/**
 * COP-5 story 06 — the account's copilot (who it is, on or off), loaded once per page and shared by
 * every planner component that marks or guards the copilot's column. A failed load resolves to
 * `null` ("unknown"), and unknown never blocks anything (see aiAgentModel.isSwitchedOffCopilot).
 */
let cached: Promise<CopilotInfo | null> | null = null;

export function loadAccountCopilot(force = false): Promise<CopilotInfo | null> {
  if (!cached || force) {
    cached = getAccountCopilot()
      .then((c) => ({has_copilot: !!c.has_copilot, user_id: c.user_id || 0, name: c.name || '', is_active: c.is_active !== false}))
      .catch(() => null);
  }
  return cached;
}

export function useAccountCopilot(): CopilotInfo | null {
  const [copilot, setCopilot] = useState<CopilotInfo | null>(null);
  useEffect(() => {
    let alive = true;
    void loadAccountCopilot().then((c) => {
      if (alive) setCopilot(c);
    });
    return () => {
      alive = false;
    };
  }, []);
  return copilot;
}
