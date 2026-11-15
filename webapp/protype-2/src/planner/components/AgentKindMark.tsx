import React from 'react';
import {COPILOT_OFF_MESSAGE, aiAgentState, type AgentLike} from '../aiAgentModel';
import {useAccountCopilot} from '../useAccountCopilot';

/**
 * COP-5 story 06 — the small mark after a column's name: ● a person, ◆ AI for an AI column, and a
 * warning when that column is the account copilot and the copilot is switched off (its existing
 * work will not be done, and it is not offered new work).
 */
export default function AgentKindMark({agent}: {agent: AgentLike}) {
  const copilot = useAccountCopilot();
  const state = aiAgentState(agent, copilot);

  if (state === 'person') {
    return (
      <span className="text-[9px] text-neutral-400 font-bold shrink-0" title="Person">
        ●
      </span>
    );
  }

  return (
    <>
      <span
        className="text-[10px] text-purple-700 font-bold shrink-0"
        title={state === 'ai_unlinked' ? 'AI column - not linked to the copilot, so nothing does this work yet' : 'AI - the account copilot'}
        data-testid="agent-ai-mark"
      >
        ◆ AI
      </span>
      {state === 'copilot_off' && (
        <span
          className="text-[9px] font-bold shrink-0 rounded-sm bg-amber-100 text-amber-800 px-1"
          title={`${COPILOT_OFF_MESSAGE} Work already on its days will not be done until then.`}
          data-testid="agent-copilot-off"
        >
          Switched off
        </span>
      )}
    </>
  );
}
