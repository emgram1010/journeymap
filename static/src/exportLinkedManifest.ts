// US-EXP-1-10b — _manifest.json builder for the linked bundle.
// Pure function that returns the ManifestV1 object so the dialog can render
// post-export warnings + the round-trip test (US-EXP-1-12) can assert on it
// without re-parsing markdown.

import {cellAnchor, mapSlug} from './exportAnchors';
import {computeWordBudget} from './linkedGraphBudget';
import type {LinkedGraph, LinkedGraphEdge} from './linkedGraphClient';
import type {HydratedJourneyMapBundle} from './xano';

export type TraversalMode = 'all_linked' | 'sub_only' | 'exception_only';

export type LinkType = LinkedGraphEdge['link_type'];

export type MapLevel = 'architecture' | 'actor-journey' | 'atomic' | null;

export interface ManifestParentRef {
  link_type: LinkType;
  source_map: number;
  source_cell?: string; // canonical [CELL:…] anchor
  source_lens?: number;
}

export interface ManifestMapEntry {
  map_id: number;
  slug: string;
  folder: string;
  title: string;
  map_level: MapLevel;
  depth_from_root: number;
  word_count: number;
  parent: ManifestParentRef | null;
}

export interface ManifestLinkEntry {
  source_map: number;
  target_map: number;
  link_type: LinkType;
  label: string | null;
  source_cell?: string;
  source_lens?: number;
}

export interface ManifestWarning {
  type: string;
  detail: string;
}

export interface ManifestV1 {
  schema_version: 1;
  generated_at: string;
  root_map_id: number;
  architecture_id: number;
  traversal: TraversalMode;
  walk_status: 'complete' | 'depth_capped';
  maps: ManifestMapEntry[];
  links: ManifestLinkEntry[];
  warnings: ManifestWarning[];
}

export interface BuildManifestOptions {
  traversal: TraversalMode;
  /** Extra builder-time warnings (hydrate failures, etc.) to merge with walker warnings. */
  extraWarnings?: ManifestWarning[];
}

/** Resolve a cell xanoId inside the source map to its canonical anchor, or undefined. */
function resolveCellAnchor(bundle: HydratedJourneyMapBundle | undefined, cellId: number | null | undefined): string | undefined {
  if (!bundle || cellId == null) return undefined;
  const cell = bundle.cells.find((c) => c.xanoId === cellId);
  if (!cell) return undefined;
  const stageIndex = bundle.stages.findIndex((s) => s.xanoId === cell.stageXanoId);
  const lensIndex = bundle.lenses.findIndex((l) => l.xanoId === cell.lensXanoId);
  if (stageIndex < 0 || lensIndex < 0) return undefined;
  return cellAnchor(bundle.journeyMap, stageIndex, lensIndex);
}

/** BFS depth from rootMapId via the graph's directed edges (source → target). */
function computeDepths(graph: LinkedGraph): Map<number, number> {
  const depths = new Map<number, number>();
  depths.set(graph.rootMapId, 0);
  const queue: number[] = [graph.rootMapId];
  const adjacency = new Map<number, number[]>();
  for (const edge of graph.links) {
    const list = adjacency.get(edge.source_map) ?? [];
    list.push(edge.target_map);
    adjacency.set(edge.source_map, list);
  }
  while (queue.length > 0) {
    const current = queue.shift()!;
    const next = adjacency.get(current) ?? [];
    for (const target of next) {
      if (!depths.has(target)) {
        depths.set(target, (depths.get(current) ?? 0) + 1);
        queue.push(target);
      }
    }
  }
  return depths;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

/** First inbound edge in BFS order = canonical parent. Null for the root. */
function findParentEdge(graph: LinkedGraph, mapId: number): LinkedGraphEdge | null {
  if (mapId === graph.rootMapId) return null;
  for (const edge of graph.links) {
    if (edge.target_map === mapId) return edge;
  }
  return null;
}

export function buildLinkedManifest(graph: LinkedGraph, opts: BuildManifestOptions): ManifestV1 {
  const budget = computeWordBudget(graph);
  const depths = computeDepths(graph);

  const maps: ManifestMapEntry[] = graph.bfsOrder.map((mapId, idx) => {
    const bundle = graph.maps.get(mapId);
    const parentEdge = findParentEdge(graph, mapId);
    const parentBundle = parentEdge ? graph.maps.get(parentEdge.source_map) : undefined;
    const slug = bundle ? mapSlug(bundle.journeyMap) : `m${mapId}`;

    let parent: ManifestParentRef | null = null;
    if (parentEdge) {
      parent = {
        link_type: parentEdge.link_type,
        source_map: parentEdge.source_map,
      };
      const cellRef = resolveCellAnchor(parentBundle, parentEdge.source_cell);
      if (cellRef) parent.source_cell = cellRef;
      if (parentEdge.source_lens != null) parent.source_lens = parentEdge.source_lens;
    }

    return {
      map_id: mapId,
      slug,
      folder: `maps/${pad2(idx + 1)}-${slug}`,
      title: bundle?.journeyMap.title ?? `(unhydrated map m${mapId})`,
      map_level: (bundle?.journeyMap.map_level ?? null) as MapLevel,
      depth_from_root: depths.get(mapId) ?? -1,
      word_count: budget.perMap.get(mapId) ?? 0,
      parent,
    };
  });

  const links: ManifestLinkEntry[] = graph.links.map((edge) => {
    const entry: ManifestLinkEntry = {
      source_map: edge.source_map,
      target_map: edge.target_map,
      link_type: edge.link_type,
      label: edge.label,
    };
    const cellRef = resolveCellAnchor(graph.maps.get(edge.source_map), edge.source_cell);
    if (cellRef) entry.source_cell = cellRef;
    if (edge.source_lens != null) entry.source_lens = edge.source_lens;
    return entry;
  });

  const warnings: ManifestWarning[] = [
    ...graph.warnings.map((w) => ({type: w.type, detail: w.detail})),
    ...(opts.extraWarnings ?? []),
  ];

  return {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    root_map_id: graph.rootMapId,
    architecture_id: graph.architectureId,
    traversal: opts.traversal,
    walk_status: graph.walkStatus,
    maps,
    links,
    warnings,
  };
}

/** Convenience: pretty-printed JSON (2-space indent) for direct embedding into the zip. */
export function serializeManifest(manifest: ManifestV1): string {
  return JSON.stringify(manifest, null, 2);
}
