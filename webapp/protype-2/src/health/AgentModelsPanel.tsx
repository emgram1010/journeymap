import React from 'react';
import {AGENT_MODELS, agentModelsSummary, isCurrentModel, modelLabel} from './agentModels';

/**
 * COP-13 story 02 - every AI agent and the model it runs on, so a stale model is visible on Health.
 * Read from the in-app manifest (checked against ai/agent/*.xs by a unit test); no server call.
 */
export default function AgentModelsPanel() {
  return (
    <div data-testid="health-agent-models">
      <h2 className="text-sm font-medium text-zinc-700 mb-2">AI models</h2>
      <div className="text-sm text-zinc-700 mb-2">{agentModelsSummary(AGENT_MODELS)}</div>
      <ul className="space-y-1">
        {AGENT_MODELS.map((a) => {
          const current = isCurrentModel(a.model);
          return (
            <li key={a.file} data-testid={`agent-model-${a.file.replace('.xs', '')}`} className="flex flex-wrap items-baseline justify-between gap-2 rounded-md border border-zinc-200 bg-white px-3 py-2 text-sm">
              <span>
                <span className="font-medium text-zinc-900">{a.name}</span> <span className="text-zinc-600">- {a.does}</span>
              </span>
              <span className={`shrink-0 rounded border px-2 py-0.5 text-xs ${current ? 'border-emerald-300 bg-emerald-50 text-emerald-800' : 'border-amber-300 bg-amber-50 text-amber-800'}`}>
                {modelLabel(a.model)}
                {current ? '' : ' - older'}
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
