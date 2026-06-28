// US-EXP-1-09b — Core linked-skill bundle orchestrator.
// Pure: takes an already-hydrated LinkedGraph and options, returns the zip
// blob + filename + manifest. No DOM, no fetch — testable in US-EXP-1-12.

import JSZip from 'jszip';
import {mapSlug, slugify} from './exportAnchors';
import {buildArchitectureIndex} from './exportArchitectureIndex';
import {buildGlossary} from './exportGlossary';
import {buildCellLinkCallout, buildLensLinkCallout} from './exportLinkCallouts';
import {buildLinkedManifest, serializeManifest, type ManifestV1, type ManifestWarning, type TraversalMode} from './exportLinkedManifest';
import {buildJourneyMapFiles, type StageCallouts} from './exportMarkdownBundle';
import {buildOriginBlock} from './exportOriginBlock';
import {buildOutboundLinks} from './exportOutboundLinks';
import type {LinkedGraph, LinkedGraphEdge} from './linkedGraphClient';

export interface LinkedSkillOptions {
  traversal: TraversalMode;
  includeGlossary?: boolean; // default true
  shouldCancel?: () => boolean;
}

export type LinkedSkillProgress = (phase: 'building' | 'zipping', done: number, total: number) => void;

export interface LinkedSkillResult {
  blob: Blob | null;
  filename: string;
  manifest: ManifestV1;
  cancelled: boolean;
}

const TRAVERSAL_EDGE_TYPES: Record<TraversalMode, Set<string>> = {
  all_linked: new Set(['sub_journey', 'exception', 'anti_journey', 'agent_manual', 'parent_child']),
  sub_only: new Set(['sub_journey', 'agent_manual', 'parent_child']),
  exception_only: new Set(['exception']),
};

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

/** Drop edges by traversal type, then prune unreached maps via BFS from root. */
export function filterGraph(graph: LinkedGraph, traversal: TraversalMode): LinkedGraph {
  const allowed = TRAVERSAL_EDGE_TYPES[traversal];
  const links = graph.links.filter((e) => allowed.has(e.link_type));

  // BFS from root using only the filtered edges to determine reachable maps.
  const reached = new Set<number>([graph.rootMapId]);
  const order: number[] = [graph.rootMapId];
  const queue: number[] = [graph.rootMapId];
  const adjacency = new Map<number, number[]>();
  for (const edge of links) {
    const list = adjacency.get(edge.source_map) ?? [];
    list.push(edge.target_map);
    adjacency.set(edge.source_map, list);
  }
  while (queue.length > 0) {
    const current = queue.shift()!;
    for (const target of adjacency.get(current) ?? []) {
      if (!reached.has(target)) {
        reached.add(target);
        order.push(target);
        queue.push(target);
      }
    }
  }

  const maps = new Map<number, ReturnType<LinkedGraph['maps']['get']>>();
  for (const id of reached) {
    const b = graph.maps.get(id);
    if (b) maps.set(id, b);
  }

  return {
    rootMapId: graph.rootMapId,
    architectureId: graph.architectureId,
    maps: maps as LinkedGraph['maps'],
    links: links.filter((e) => reached.has(e.source_map) && reached.has(e.target_map)),
    warnings: graph.warnings,
    walkStatus: graph.walkStatus,
    bfsOrder: order,
  };
}

function buildCalloutsForMap(graph: LinkedGraph, mapId: number): (s: unknown, i: number) => StageCallouts {
  return () => ({
    forCell: (cell) => buildCellLinkCallout(graph, mapId, cell?.xanoId ?? null),
    forLens: (lens) => buildLensLinkCallout(graph, mapId, lens.xanoId ?? null),
  });
}

export async function buildLinkedSkillBundle(
  graph: LinkedGraph,
  opts: LinkedSkillOptions,
  onProgress?: LinkedSkillProgress,
): Promise<LinkedSkillResult> {
  const filtered = filterGraph(graph, opts.traversal);
  const includeGlossary = opts.includeGlossary !== false;
  const extraWarnings: ManifestWarning[] = [];

  // Surface maps that exist in bfsOrder but weren't hydrated (walker found them, hydrate failed).
  for (const mapId of filtered.bfsOrder) {
    if (!filtered.maps.has(mapId)) {
      extraWarnings.push({type: 'hydrate_missing', detail: `Map m${mapId} reached by walker but not hydrated; emitted as anchor only.`});
    }
  }

  const manifest = buildLinkedManifest(filtered, {traversal: opts.traversal, extraWarnings});
  const totalMaps = filtered.bfsOrder.length;
  let done = 0;
  onProgress?.('building', done, totalMaps);

  const zip = new JSZip();
  const rootSlug = (() => {
    const rootBundle = filtered.maps.get(filtered.rootMapId);
    if (rootBundle) return mapSlug(rootBundle.journeyMap);
    return `m${filtered.rootMapId}`;
  })();
  const rootFolderName = slugify(filtered.maps.get(filtered.rootMapId)?.journeyMap.title ?? `journey-${filtered.rootMapId}`);
  const root = zip.folder(`${rootFolderName}-skill-linked`)!;

  root.file('ARCHITECTURE.md', buildArchitectureIndex(filtered));
  if (includeGlossary) root.file('GLOSSARY.md', buildGlossary(filtered));
  root.file('_manifest.json', serializeManifest(manifest));

  const filename = `${rootSlug}-skill-linked.zip`;

  for (let idx = 0; idx < filtered.bfsOrder.length; idx += 1) {
    if (opts.shouldCancel?.()) {
      return {blob: null, filename, manifest, cancelled: true};
    }
    const mapId = filtered.bfsOrder[idx];
    const bundle = filtered.maps.get(mapId);
    const folderName = `maps/${pad2(idx + 1)}-${bundle ? mapSlug(bundle.journeyMap) : `m${mapId}`}`;
    const folder = root.folder(folderName)!;

    if (!bundle) {
      // Map referenced but not hydrated — emit a placeholder so anchors resolve to *something*.
      folder.file('README.md', `# Map m${mapId}\n\n_Not hydrated. See \`_manifest.json\` warnings for detail._\n`);
      done += 1;
      onProgress?.('building', done, totalMaps);
      continue;
    }

    const files = buildJourneyMapFiles(bundle, buildCalloutsForMap(filtered, mapId));
    const originBlock = buildOriginBlock(filtered, mapId);
    const agents = files['AGENTS.md'] ?? '';
    folder.file('README.md', `${originBlock}\n${agents}`);
    for (const [path, content] of Object.entries(files)) {
      if (path === 'AGENTS.md' || path === 'INDEX.md') continue;
      folder.file(path, content);
    }
    const outbound = buildOutboundLinks(filtered, mapId);
    if (outbound) folder.file('04-outbound-links.md', outbound);

    done += 1;
    onProgress?.('building', done, totalMaps);
  }

  if (opts.shouldCancel?.()) {
    return {blob: null, filename, manifest, cancelled: true};
  }

  onProgress?.('zipping', 0, 1);
  const blob = await zip.generateAsync({type: 'blob'});
  onProgress?.('zipping', 1, 1);

  return {blob, filename, manifest, cancelled: false};
}
