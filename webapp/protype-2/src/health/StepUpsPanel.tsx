import React, {useEffect, useState} from 'react';
import {getOpsStepUps, type OpsStepUpsResponse} from '../xano';
import {stepUpRowText, stepUpsSummary} from './stepUpsModel';

/**
 * COP-13 story 05 - how often the copilot asked to use the stronger, dearer model, per day and business,
 * and what happened. Loads on its own, so a failure here never blanks the rest of the Health page.
 */
export default function StepUpsPanel() {
  const [data, setData] = useState<OpsStepUpsResponse | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;
    getOpsStepUps()
      .then((r) => live && setData(r))
      .catch(() => live && setFailed(true));
    return () => {
      live = false;
    };
  }, []);

  const rows = [...(data?.rows ?? [])].filter((r) => r.requested > 0 || r.approved + r.declined + r.expired + r.waiting > 0).sort((a, b) => b.day - a.day);

  return (
    <div data-testid="health-step-ups">
      <h2 className="text-sm font-medium text-zinc-700 mb-2">Stronger model</h2>
      {failed ? (
        <div className="text-sm text-zinc-500">Couldn't load stronger-model use right now.</div>
      ) : !data ? (
        <div className="text-sm text-zinc-500">Loading…</div>
      ) : (
        <div className="space-y-2">
          <div className="text-sm text-zinc-700">{stepUpsSummary(data)}</div>
          {rows.length > 0 && (
            <ul className="space-y-1">
              {rows.map((r) => (
                <li key={`${r.day}-${r.journey_architecture_id}`} className="rounded-md border border-zinc-200 bg-white px-3 py-2 text-sm text-zinc-700">
                  {stepUpRowText(r)}
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
