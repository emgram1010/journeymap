// US-EXP-1-01b — Frontend graph client.
// Calls the walker (US-EXP-1-01), then fans out load_bundle calls to hydrate every
// reachable map. Returns one in-memory LinkedGraph that downstream builders
// (US-EXP-1-04 origin blocks, 1-09b skill bundle, 1-13 diagram, 1-15 notebooklm)
// all consume.
//
// Lean walker → parallel hydrate split keeps the backend response predictable
// and lets the client own retry, cancellation, and concurrency control.

import {
  fetchLinkedGraphRaw,
  loadJourneyMapBundle,
  type HydratedJourneyMapBundle,
  type LinkedGraphEdge,
  type LinkedGraphResponse,
  type LinkedGraphWarning,
} from './xano';

export type {LinkedGraphEdge, LinkedGraphWarning} from './xano';

export interface LinkedGraph {
  rootMapId: number;
  architectureId: number;
  /** Hydrated bundles keyed by journey_map.id, in BFS-visit order via bfsOrder. */
  maps: Map<number, HydratedJourneyMapBundle>;
  /** Includes real journey_link rows plus synthesized parent_child + agent_manual edges. */
  links: LinkedGraphEdge[];
  warnings: LinkedGraphWarning[];
  walkStatus: 'complete' | 'depth_capped';
  /** visited_map_ids from the walker — already in BFS order; drives folder numbering. */
  bfsOrder: number[];
}

export type LinkedGraphProgress =
  | {phase: 'walking'; done: 0; total: 1}
  | {phase: 'walking'; done: 1; total: 1}
  | {phase: 'hydrating'; done: number; total: number};

export interface FetchLinkedGraphOptions {
  maxDepth?: number;
  includeAgentManuals?: boolean;
  includeChildren?: boolean;
  /** Cap on parallel load_bundle calls. Default 8. */
  concurrency?: number;
  signal?: AbortSignal;
  onProgress?: (p: LinkedGraphProgress) => void;
}

const DEFAULT_CONCURRENCY = 8;

async function hydrateWithRetry(
  mapId: number,
  signal: AbortSignal | undefined,
): Promise<{ok: true; bundle: HydratedJourneyMapBundle} | {ok: false; reason: string}> {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    if (signal?.aborted) return {ok: false, reason: 'aborted'};
    try {
      const bundle = await loadJourneyMapBundle(mapId);
      return {ok: true, bundle};
    } catch (err) {
      if (signal?.aborted) return {ok: false, reason: 'aborted'};
      if (attempt === 1) {
        const reason = err instanceof Error ? err.message : 'unknown error';
        return {ok: false, reason};
      }
    }
  }
  return {ok: false, reason: 'unreachable'};
}

async function hydrateAll(
  mapIds: number[],
  concurrency: number,
  signal: AbortSignal | undefined,
  onProgress: ((p: LinkedGraphProgress) => void) | undefined,
): Promise<{maps: Map<number, HydratedJourneyMapBundle>; failures: LinkedGraphWarning[]}> {
  const maps = new Map<number, HydratedJourneyMapBundle>();
  const failures: LinkedGraphWarning[] = [];
  let done = 0;
  const total = mapIds.length;
  let cursor = 0;

  const worker = async (): Promise<void> => {
    while (cursor < mapIds.length) {
      if (signal?.aborted) return;
      const idx = cursor;
      cursor += 1;
      const mapId = mapIds[idx];
      const result = await hydrateWithRetry(mapId, signal);
      if (result.ok === true) {
        maps.set(mapId, result.bundle);
      } else {
        if (result.reason !== 'aborted') {
          failures.push({
            type: 'hydrate_failed',
            detail: `Failed to load map ${mapId}: ${result.reason}`,
          });
        }
      }
      done += 1;
      onProgress?.({phase: 'hydrating', done, total});
    }
  };

  const workers = Array.from({length: Math.min(concurrency, mapIds.length)}, () => worker());
  await Promise.all(workers);
  return {maps, failures};
}

export async function fetchLinkedGraph(
  rootMapId: number,
  opts: FetchLinkedGraphOptions = {},
): Promise<LinkedGraph> {
  const {signal, onProgress, concurrency = DEFAULT_CONCURRENCY} = opts;

  onProgress?.({phase: 'walking', done: 0, total: 1});
  const walk: LinkedGraphResponse = await fetchLinkedGraphRaw(rootMapId, {
    maxDepth: opts.maxDepth,
    includeAgentManuals: opts.includeAgentManuals,
    includeChildren: opts.includeChildren,
    signal,
  });
  onProgress?.({phase: 'walking', done: 1, total: 1});

  if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');

  const {maps, failures} = await hydrateAll(walk.visited_map_ids, concurrency, signal, onProgress);

  if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');

  return {
    rootMapId: walk.root_map_id,
    architectureId: walk.architecture_id,
    maps,
    links: walk.links,
    warnings: [...walk.warnings, ...failures],
    walkStatus: walk.walk_status,
    bfsOrder: walk.visited_map_ids,
  };
}
