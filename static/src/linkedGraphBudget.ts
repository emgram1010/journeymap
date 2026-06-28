// US-EXP-1-02 — Word-budget pre-flight for the linked exporter.
// Pure compute over a hydrated LinkedGraph — no I/O, no DOM.
// Used by:
//  • US-EXP-1-09 dialog → live fit-badge per traversal radio
//  • US-EXP-1-15 NotebookLM bundle → per-file fit (each map = own source)
//  • US-EXP-1-09b core builder → final guard before zip

import {buildJourneyMapNotebookLM} from './exportMarkdownNotebookLM';
import {countWords, NOTEBOOKLM_WORD_LIMIT, NOTEBOOKLM_WORD_WARN} from './exportMarkdownNotebookLM';
import type {LinkedGraph} from './linkedGraphClient';

export type FitBadge = 'green' | 'yellow' | 'red';

export interface SplitPlanEntry {
  rootMapId: number;
  includedMaps: number[];
  wordCount: number;
}

export interface WordBudget {
  /** Word count per map_id, computed from the per-map NotebookLM render (the densest emitter). */
  perMap: Map<number, number>;
  /** Sum of perMap values. */
  total: number;
  /** 🟢 <400K · 🟡 400–500K · 🔴 >500K. */
  fitBadge: FitBadge;
  /** Present only when total > 500K — proposes BFS sub-trees that each fit. */
  splitPlan?: SplitPlanEntry[];
}

export function classifyFit(total: number): FitBadge {
  if (total >= NOTEBOOKLM_WORD_LIMIT) return 'red';
  if (total >= NOTEBOOKLM_WORD_WARN) return 'yellow';
  return 'green';
}

/** Word count for a single hydrated map, using the same renderer the exporter uses. */
function wordsForMap(graph: LinkedGraph, mapId: number): number {
  const bundle = graph.maps.get(mapId);
  if (!bundle) return 0;
  return countWords(buildJourneyMapNotebookLM(bundle));
}

/**
 * BFS-greedy partition: walk bfsOrder once, packing maps into the current bucket
 * until adding the next map would overflow NOTEBOOKLM_WORD_LIMIT, then start a new
 * bucket rooted at that map. Stable, deterministic, and matches the folder-numbering
 * the bundle already uses.
 */
function computeSplitPlan(graph: LinkedGraph, perMap: Map<number, number>): SplitPlanEntry[] {
  const buckets: SplitPlanEntry[] = [];
  let current: SplitPlanEntry | null = null;
  for (const mapId of graph.bfsOrder) {
    const w = perMap.get(mapId) ?? 0;
    if (!current || current.wordCount + w > NOTEBOOKLM_WORD_LIMIT) {
      current = {rootMapId: mapId, includedMaps: [mapId], wordCount: w};
      buckets.push(current);
    } else {
      current.includedMaps.push(mapId);
      current.wordCount += w;
    }
  }
  return buckets;
}

export function computeWordBudget(graph: LinkedGraph): WordBudget {
  const perMap = new Map<number, number>();
  let total = 0;
  for (const mapId of graph.bfsOrder) {
    const w = wordsForMap(graph, mapId);
    perMap.set(mapId, w);
    total += w;
  }
  const fitBadge = classifyFit(total);
  const budget: WordBudget = {perMap, total, fitBadge};
  if (fitBadge === 'red') {
    budget.splitPlan = computeSplitPlan(graph, perMap);
  }
  return budget;
}
