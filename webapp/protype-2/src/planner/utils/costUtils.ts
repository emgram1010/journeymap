import { Agent, AppSettings, Timeline, Task, Throughput } from '../types';
import { calculateAgentDayLoad } from './agentUtils';

/**
 * Cost model
 * ----------
 * The plan stores *durations*, not tokens. So:
 *
 *   person agent -> hours x humanHourlyRate
 *   ai agent     -> minutes x (tokens/minute) x (price per token)
 *
 * Rates (what a token costs) are global; the throughput assumptions that
 * convert planned minutes into token volume are per-workspace, since how
 * token-intensive the work is is a property of the project.
 */

/** Effective $/hr for an agent, whether it's a person or a model. */
export function getAgentHourlyRate(
  agent: Agent,
  settings: AppSettings,
  throughput: Throughput
): number {
  if (agent.kind === 'person') {
    return settings.humanHourlyRate || 0;
  }

  const model = settings.models.find(m => m.id === agent.modelId);
  if (!model) return 0;

  const inputCostPerMinute = (throughput.inputTokensPerMinute * model.inputPer1M) / 1_000_000;
  const outputCostPerMinute = (throughput.outputTokensPerMinute * model.outputPer1M) / 1_000_000;
  return (inputCostPerMinute + outputCostPerMinute) * 60;
}

/** Cost of a block of planned minutes on a given agent. */
export function getCostForMinutes(
  agent: Agent,
  minutes: number,
  settings: AppSettings,
  throughput: Throughput
): number {
  return (minutes / 60) * getAgentHourlyRate(agent, settings, throughput);
}

export interface AgentCostRow {
  agent: Agent;
  plannedHours: number;
  hourlyRate: number;
  cost: number;
}

export interface WorkspaceCostSummary {
  totalCost: number;
  humanCost: number;
  aiCost: number;
  humanHours: number;
  aiHours: number;
  blendedHourlyRate: number; // totalCost / total planned hours
  perAgent: AgentCostRow[]; // sorted most expensive first
  /** True when nothing can be costed yet (no human rate, no models assigned). */
  isUnconfigured: boolean;
}

export function calculateWorkspaceCostSummary(
  agents: Agent[],
  visibleDates: string[],
  timelines: Timeline[],
  tasks: Task[],
  settings: AppSettings,
  throughput: Throughput
): WorkspaceCostSummary {
  const perAgent: AgentCostRow[] = [];
  let humanCost = 0;
  let aiCost = 0;
  let humanMinutes = 0;
  let aiMinutes = 0;

  agents.forEach(agent => {
    let plannedMinutes = 0;
    visibleDates.forEach(date => {
      plannedMinutes += calculateAgentDayLoad(agent, date, timelines, tasks).totalMinutes;
    });

    const hourlyRate = getAgentHourlyRate(agent, settings, throughput);
    const cost = (plannedMinutes / 60) * hourlyRate;

    if (agent.kind === 'person') {
      humanCost += cost;
      humanMinutes += plannedMinutes;
    } else {
      aiCost += cost;
      aiMinutes += plannedMinutes;
    }

    perAgent.push({
      agent,
      plannedHours: Math.round((plannedMinutes / 60) * 10) / 10,
      hourlyRate,
      cost,
    });
  });

  perAgent.sort((a, b) => b.cost - a.cost);

  const totalCost = humanCost + aiCost;
  const totalHours = (humanMinutes + aiMinutes) / 60;

  const anyRateSet =
    (settings.humanHourlyRate || 0) > 0 ||
    agents.some(a => a.kind === 'ai' && getAgentHourlyRate(a, settings, throughput) > 0);

  return {
    totalCost,
    humanCost,
    aiCost,
    humanHours: Math.round((humanMinutes / 60) * 10) / 10,
    aiHours: Math.round((aiMinutes / 60) * 10) / 10,
    blendedHourlyRate: totalHours > 0 ? totalCost / totalHours : 0,
    perAgent,
    isUnconfigured: !anyRateSet,
  };
}

/** Compact money formatting: $0 / $48 / $1.2K / $340K */
export function formatMoney(amount: number, symbol = '$'): string {
  const abs = Math.abs(amount);
  if (abs >= 1_000_000) return `${symbol}${(amount / 1_000_000).toFixed(1)}M`;
  if (abs >= 1_000) return `${symbol}${(amount / 1_000).toFixed(1)}K`;
  if (abs >= 100) return `${symbol}${Math.round(amount)}`;
  if (abs === 0) return `${symbol}0`;
  return `${symbol}${amount.toFixed(2)}`;
}
