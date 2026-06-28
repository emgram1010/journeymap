// US-EXP-1-06 — Inline 🔗 link callouts.
// Pure helpers that emit a `> 🔗 **Links:** …` callout block when a cell or
// lens has outbound edges in the LinkedGraph. The linked-skill bundle
// builder (US-EXP-1-09b) calls these inside per-stage files so the LLM can
// follow the cross-file references without scanning the outbound-links
// manifest.
//
// Both helpers return `null` when there are no relevant edges so callers
// can `if (callout) lines.push(callout)`.

import {mapAnchor} from './exportAnchors';
import {mapSlug} from './exportAnchors';
import type {LinkedGraph, LinkedGraphEdge} from './linkedGraphClient';

function formatEdge(graph: LinkedGraph, edge: LinkedGraphEdge): string {
  const target = graph.maps.get(edge.target_map);
  const anchor = target ? mapAnchor(target.journeyMap) : `[MAP:m${edge.target_map}]`;
  const title = target ? target.journeyMap.title : `(unhydrated map m${edge.target_map})`;
  const file = target ? `maps/${mapSlug(target.journeyMap)}/README.md` : null;
  const note = edge.label?.trim();
  const filePart = file ? ` _(see \`${file}\`)_` : '';
  const notePart = note ? ` — ${note}` : '';
  return `- \`${edge.link_type}\` → ${anchor} ${title}${filePart}${notePart}`;
}

function buildBlock(title: string, edges: LinkedGraphEdge[], graph: LinkedGraph): string {
  const lines = [`> 🔗 **${title}**`];
  for (const edge of edges) {
    lines.push(`> ${formatEdge(graph, edge).replace(/^- /, '')}`);
  }
  return lines.join('\n');
}

/** Outbound edges originating at a specific cell (source_cell === cellXanoId). */
export function buildCellLinkCallout(
  graph: LinkedGraph,
  mapId: number,
  cellXanoId: number | null | undefined,
): string | null {
  if (cellXanoId == null) return null;
  const edges = graph.links.filter(
    (e) => e.source_map === mapId && e.source_cell === cellXanoId,
  );
  if (edges.length === 0) return null;
  return buildBlock(edges.length === 1 ? 'Links from this cell:' : 'Links from this cell:', edges, graph);
}

/** Outbound edges originating at a lens (agent_manual; no source_cell). */
export function buildLensLinkCallout(
  graph: LinkedGraph,
  mapId: number,
  lensXanoId: number | null | undefined,
): string | null {
  if (lensXanoId == null) return null;
  const edges = graph.links.filter(
    (e) =>
      e.source_map === mapId &&
      e.source_lens === lensXanoId &&
      (e.source_cell == null),
  );
  if (edges.length === 0) return null;
  return buildBlock('Operating manual for this lens:', edges, graph);
}
