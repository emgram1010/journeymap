// US-EXP-1-13 — Mermaid architecture diagram (.mmd).
// Pure: takes an already-filtered LinkedGraph, returns a Mermaid flowchart string.
// Node = map, edge = link styled by link_type.

import {filterGraph} from './exportLinkedSkillBundle';
import {mapSlug} from './exportAnchors';
import type {TraversalMode} from './exportLinkedManifest';
import type {LinkedGraph, LinkedGraphEdge} from './linkedGraphClient';

export interface DiagramOptions {
  traversal: TraversalMode;
  direction?: 'TD' | 'LR';
  includeLegend?: boolean;
}

export interface DiagramResult {
  mermaid: string;
  filename: string;
  nodeCount: number;
  edgeCount: number;
}

const EDGE_STYLE: Record<LinkedGraphEdge['link_type'], {arrow: string; label: string}> = {
  sub_journey: {arrow: '-->', label: 'sub'},
  parent_child: {arrow: '-->', label: 'child'},
  exception: {arrow: '-.->', label: 'exception'},
  anti_journey: {arrow: '-.->', label: 'anti'},
  agent_manual: {arrow: '==>', label: 'agent'},
};

function escapeLabel(s: string): string {
  return s.replace(/"/g, '&quot;').replace(/\n/g, ' ').slice(0, 60);
}

function nodeId(mapId: number): string {
  return `m${mapId}`;
}

function nodeShape(role: 'root' | 'agent' | 'other'): {open: string; close: string} {
  if (role === 'root') return {open: '[[', close: ']]'};
  if (role === 'agent') return {open: '([', close: '])'};
  return {open: '[', close: ']'};
}

export function buildArchitectureDiagram(graph: LinkedGraph, opts: DiagramOptions): DiagramResult {
  const filtered = filterGraph(graph, opts.traversal);
  const direction = opts.direction ?? 'TD';
  const includeLegend = opts.includeLegend !== false;

  const agentTargets = new Set<number>();
  for (const e of filtered.links) {
    if (e.link_type === 'agent_manual') agentTargets.add(e.target_map);
  }

  const lines: string[] = [];
  lines.push(`%% Architecture diagram — root m${filtered.rootMapId} · traversal: ${opts.traversal}`);
  lines.push(`flowchart ${direction}`);

  for (const mapId of filtered.bfsOrder) {
    const bundle = filtered.maps.get(mapId);
    const title = bundle?.journeyMap.title ?? `Map ${mapId}`;
    const role: 'root' | 'agent' | 'other' =
      mapId === filtered.rootMapId ? 'root' : agentTargets.has(mapId) ? 'agent' : 'other';
    const shape = nodeShape(role);
    const slug = bundle ? mapSlug(bundle.journeyMap) : `m${mapId}`;
    lines.push(`  ${nodeId(mapId)}${shape.open}"${escapeLabel(title)}<br/><small>m${mapId} · ${slug}</small>"${shape.close}`);
  }

  for (const edge of filtered.links) {
    const style = EDGE_STYLE[edge.link_type];
    if (!style) continue;
    const userLabel = edge.label ? `${style.label}: ${escapeLabel(edge.label)}` : style.label;
    lines.push(`  ${nodeId(edge.source_map)} ${style.arrow}|"${userLabel}"| ${nodeId(edge.target_map)}`);
  }

  // Style classes
  lines.push('');
  lines.push('  classDef root fill:#18181b,stroke:#18181b,color:#fff;');
  lines.push('  classDef agent fill:#fef3c7,stroke:#b45309,color:#78350f;');
  lines.push(`  class ${nodeId(filtered.rootMapId)} root;`);
  if (agentTargets.size > 0) {
    lines.push(`  class ${Array.from(agentTargets).map(nodeId).join(',')} agent;`);
  }

  if (includeLegend && filtered.links.length > 0) {
    lines.push('');
    lines.push('  subgraph legend [Legend]');
    lines.push('    direction LR');
    lines.push('    l1["Root"]:::root');
    lines.push('    l2(["AI agent manual"]):::agent');
    lines.push('    l3["Sub-journey"] -.->|exception| l4["Recovery"]');
    lines.push('  end');
  }

  const rootBundle = filtered.maps.get(filtered.rootMapId);
  const rootSlug = rootBundle ? mapSlug(rootBundle.journeyMap) : `m${filtered.rootMapId}`;
  return {
    mermaid: lines.join('\n') + '\n',
    filename: `${rootSlug}-architecture.mmd`,
    nodeCount: filtered.bfsOrder.length,
    edgeCount: filtered.links.length,
  };
}
