import React, {useEffect, useState} from 'react';
import {getOpsToolCalls, type OpsToolCallsResponse} from '../xano';
import {refusalMeaning, refusalWho, toolCallsSummary} from './toolCallsModel';

/**
 * COP-1 story 04 - every AI tool call is logged with who; this shows the last 24 hours on Health.
 * Loads on its own, so a failure here never blanks the rest of the page.
 */
export default function ToolCallsPanel() {
  const [data, setData] = useState<OpsToolCallsResponse | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;
    getOpsToolCalls()
      .then((r) => live && setData(r))
      .catch(() => live && setFailed(true));
    return () => {
      live = false;
    };
  }, []);

  return (
    <div data-testid="health-tool-calls">
      <h2 className="text-sm font-medium text-zinc-700 mb-2">AI tool calls</h2>
      {failed ? (
        <div className="text-sm text-zinc-500">Couldn't load AI tool calls right now.</div>
      ) : !data ? (
        <div className="text-sm text-zinc-500">Loading…</div>
      ) : (
        <div className="space-y-2">
          <div className="text-sm text-zinc-700">{toolCallsSummary(data)}</div>
          {data.recent_refusals.length > 0 && (
            <ul className="space-y-1">
              {data.recent_refusals.map((r) => (
                <li key={r.id} className="rounded-md border border-zinc-200 bg-white px-3 py-2 text-sm">
                  <span className="font-medium text-zinc-900">{r.tool}</span>{' '}
                  <span className="text-zinc-700">- {refusalMeaning(r)}</span>
                  <div className="text-xs text-zinc-500">
                    {r.code || 'no code'} · {refusalWho(r)} · {new Date(r.at).toLocaleString()}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
