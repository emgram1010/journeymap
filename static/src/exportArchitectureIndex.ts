// US-EXP-1-07 — ARCHITECTURE.md entrypoint.
// Top-level file at the root of the linked-skill bundle. The LLM reads this
// first to understand the shape of the journey architecture: how many maps,
// how they connect, which is root, and where to find each.
//
// BFS-ordered list mirrors the walker output (visited_map_ids) so the LLM's
// reading order matches the discovery order.

import {mapAnchor, mapSlug} from './exportAnchors';
import type {LinkedGraph, LinkedGraphEdge} from './linkedGraphClient';

interface LinkSummaryRow {
  type: string;
  count: number;
}

function summarizeLinks(edges: LinkedGraphEdge[]): LinkSummaryRow[] {
  const counts = new Map<string, number>();
  for (const edge of edges) {
    counts.set(edge.link_type, (counts.get(edge.link_type) ?? 0) + 1);
  }
  return Array.from(counts.entries())
    .map(([type, count]) => ({type, count}))
    .sort((a, b) => b.count - a.count);
}

/** Edge that first introduced a non-root map into the BFS frontier. */
function findIntroEdge(graph: LinkedGraph, mapId: number): LinkedGraphEdge | null {
  if (mapId === graph.rootMapId) return null;
  for (const edge of graph.links) {
    if (edge.target_map === mapId) return edge;
  }
  return null;
}

export function buildArchitectureIndex(graph: LinkedGraph): string {
  const root = graph.maps.get(graph.rootMapId);
  const lines: string[] = [];

  lines.push('# Architecture', '');
  if (root) {
    lines.push(
      `Root map: ${mapAnchor(root.journeyMap)} **${root.journeyMap.title}**`,
      '',
    );
  } else {
    lines.push(`Root map id: \`m${graph.rootMapId}\` _(not hydrated)_`, '');
  }

  lines.push(
    `This bundle contains **${graph.maps.size} maps** connected by **${graph.links.length} edges**. ` +
      `Walk status: \`${graph.walkStatus}\`. Start by reading \`GLOSSARY.md\` for anchor grammar and link semantics, ` +
      `then this file, then \`maps/${root ? mapSlug(root.journeyMap) : `m${graph.rootMapId}`}/README.md\`.`,
    '',
  );

  // Walker warnings up top so the LLM is aware of any partial hydration.
  if (graph.warnings.length > 0) {
    lines.push('## Walker warnings', '');
    for (const w of graph.warnings) {
      lines.push(`- \`${w.type}\` — ${w.detail}`);
    }
    lines.push('');
  }

  // Link-type summary.
  const summary = summarizeLinks(graph.links);
  if (summary.length > 0) {
    lines.push('## Edge summary', '');
    lines.push('| Link type | Count |');
    lines.push('| --- | --- |');
    for (const row of summary) {
      lines.push(`| \`${row.type}\` | ${row.count} |`);
    }
    lines.push('');
  }

  // BFS-ordered map index.
  lines.push('## Maps (BFS-ordered)', '');
  lines.push('| # | Map | Reached via | From |');
  lines.push('| --- | --- | --- | --- |');
  graph.bfsOrder.forEach((mapId, idx) => {
    const bundle = graph.maps.get(mapId);
    const anchor = bundle ? mapAnchor(bundle.journeyMap) : `[MAP:m${mapId}]`;
    const title = bundle ? bundle.journeyMap.title : `(unhydrated map m${mapId})`;
    const file = bundle ? `maps/${mapSlug(bundle.journeyMap)}/README.md` : '_n/a_';
    const intro = findIntroEdge(graph, mapId);
    const via = intro ? `\`${intro.link_type}\`` : '_root_';
    const fromBundle = intro ? graph.maps.get(intro.source_map) : null;
    const from = intro
      ? fromBundle
        ? mapAnchor(fromBundle.journeyMap)
        : `[MAP:m${intro.source_map}]`
      : '—';
    lines.push(`| ${idx + 1} | ${anchor} ${title} (\`${file}\`) | ${via} | ${from} |`);
  });
  lines.push('');

  // Reading-order hint.
  lines.push('## Suggested reading order', '');
  lines.push(
    '1. `GLOSSARY.md` — vocabulary and anchor grammar.\n' +
      '2. `ARCHITECTURE.md` — this file.\n' +
      `3. Root map: \`maps/${root ? mapSlug(root.journeyMap) : `m${graph.rootMapId}`}/README.md\`.\n` +
      '4. Each map\'s `04-outbound-links.md` if present, then follow the link to the next map.\n' +
      '5. Use `_manifest.json` to programmatically resolve anchors.',
    '',
  );

  return lines.join('\n');
}
