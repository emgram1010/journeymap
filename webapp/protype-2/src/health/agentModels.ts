// COP-13 story 02 - which AI model each agent runs on, shown on Health so an old one is visible
// without opening Xano. This list is kept by hand next to the agent files and checked against
// them by agentModels.test.ts: change an agent's model in its file AND here, or the test fails.

export interface AgentModelRow {
  /** File name in ai/agent/. */
  file: string;
  /** The agent's name as Xano shows it. */
  name: string;
  /** One plain line: what it is for. */
  does: string;
  /** The model id in the agent's file. */
  model: string;
}

export const AGENT_MODELS: AgentModelRow[] = [
  {file: 'emgram_copilot.xs', name: 'Emgram Copilot', does: 'Your business copilot: chat and scheduled runs (starts cheap).', model: 'claude-sonnet-5-5'},
  {file: 'emgram_copilot_strong.xs', name: 'Emgram Copilot Strong', does: 'The copilot on the dearer model, only after you approve a step-up.', model: 'claude-opus-5-5'},
  {file: 'emgram_copilot_researcher.xs', name: 'Emgram Copilot Researcher', does: 'Researches a topic and drafts maps with sources.', model: 'claude-sonnet-5-5'},
  {file: 'journey_map_chat_agent.xs', name: 'Journey Map Chat Agent', does: 'Answers questions in the map chat.', model: 'claude-sonnet-5-5'},
  {file: 'journey_map_builder.xs', name: 'Journey Map Builder', does: 'Builds a map in phases.', model: 'claude-sonnet-4-5'},
  {file: 'journey_map_assistant.xs', name: 'Journey Map Assistant', does: 'Interviews you to draft a map.', model: 'claude-sonnet-4-5'},
  {file: 'journey_map_orchestrator.xs', name: 'Journey Map Orchestrator', does: 'Runs multi-step workflows across maps.', model: 'claude-sonnet-4-5'},
  {file: 'journey_compare_analyst.xs', name: 'Journey Compare Analyst', does: 'Compares scenarios and explains the gaps.', model: 'claude-sonnet-4-5'},
];

/** Claude 5 family models are current; anything older is flagged. */
export const isCurrentModel = (model: string): boolean => /^claude-(sonnet-5|opus-5|haiku-5|fable|mythos)/.test(model);

/** "claude-sonnet-5-5" -> "Sonnet 5.5". Anything not in that shape is shown as it is. */
export function modelLabel(model: string): string {
  const m = /^claude-(sonnet|opus|haiku)-(\d+)-(\d+)$/.exec(model);
  if (!m) return model;
  return `${m[1][0].toUpperCase()}${m[1].slice(1)} ${m[2]}.${m[3]}`;
}

export function agentModelsSummary(rows: {model: string}[]): string {
  const older = rows.filter((r) => !isCurrentModel(r.model)).length;
  return older === 0 ? `All ${rows.length} agents are on a current model.` : `${older} of ${rows.length} agents are on an older model.`;
}
