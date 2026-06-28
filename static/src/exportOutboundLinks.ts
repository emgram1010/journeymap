// US-EXP-1-05 — 04-outbound-links.md emitter.
// For a given map, lists every outbound edge grouped by link_type so the LLM
// sees all hops out of this map in one view. Uses the same deterministic
// anchors as the rest of the bundle so cross-file references resolve.

import {cellAnchor, lensAnchor, mapAnchor} from './exportAnchors';
import type {LinkedGraph, LinkedGraphEdge} from './linkedGraphClient';
import type {HydratedJourneyMapBundle} from './xano';

interface ResolvedSource {
  /** Anchor for the originating point inside the source map. */
  anchor: string;
  /** Human label after the anchor (cell content snippet or lens label). */
  hint: string;
}

function shorten(content: string | null | undefined, max = 140): string {
  const s = (content ?? '').trim().replace(/\s+/g, ' ');
  if (!s) return '';
  return s.length > max ? `${s.slice(0, max - 1)}…` : s;
}

function resolveSource(bundle: HydratedJourneyMapBundle, edge: LinkedGraphEdge): ResolvedSource {
  const map = bundle.journeyMap;

  if (edge.source_cell != null) {
    const cell = bundle.cells.find((c) => c.xanoId === edge.source_cell);
    if (cell) {
      const stageIndex = bundle.stages.findIndex((s) => s.xanoId === cell.stageXanoId);
      const lensIndex = bundle.lenses.findIndex((l) => l.xanoId === cell.lensXanoId);
      if (stageIndex >= 0 && lensIndex >= 0) {
        return {
          anchor: cellAnchor(map, stageIndex, lensIndex),
          hint: shorten(cell.content) || `${bundle.stages[stageIndex].label} × ${bundle.lenses[lensIndex].label}`,
        };
      }
    }
  }

  if (edge.source_lens != null) {
    const lensIndex = bundle.lenses.findIndex((l) => l.xanoId === edge.source_lens);
    if (lensIndex >= 0) {
      const lens = bundle.lenses[lensIndex];
      return {
        anchor: lensAnchor(map, lens, lensIndex),
        hint: edge.source_lens_label ?? lens.label,
      };
    }
  }

  return {anchor: mapAnchor(map), hint: map.title};
}

const TYPE_HEADINGS: Record<string, string> = {
  sub_journey: 'Sub-journeys',
  exception: 'Exceptions',
  anti_journey: 'Anti-journeys',
  agent_manual: 'Agent operating manuals',
  parent_child: 'Child maps',
};

const TYPE_ORDER = ['sub_journey', 'exception', 'anti_journey', 'agent_manual', 'parent_child'];

/** Return the markdown body, or null when this map has zero outbound edges. */
export function buildOutboundLinks(graph: LinkedGraph, mapId: number): string | null {
  const bundle = graph.maps.get(mapId);
  if (!bundle) return null;

  const outbound = graph.links.filter((e) => e.source_map === mapId);
  if (outbound.length === 0) return null;

  const grouped = new Map<string, LinkedGraphEdge[]>();
  for (const edge of outbound) {
    const bucket = grouped.get(edge.link_type) ?? [];
    bucket.push(edge);
    grouped.set(edge.link_type, bucket);
  }

  const lines: string[] = [];
  lines.push('# Outbound links', '');
  lines.push(
    `This map has ${outbound.length} outbound ${outbound.length === 1 ? 'link' : 'links'} to other maps in this bundle. ` +
      'Each row names the point inside this map that triggers the hop, the type of edge, and the target map.',
    '',
  );

  for (const type of TYPE_ORDER) {
    const edges = grouped.get(type);
    if (!edges || edges.length === 0) continue;
    lines.push(`## ${TYPE_HEADINGS[type] ?? type}`, '');
    lines.push('| From | → | Target | Note |');
    lines.push('| --- | --- | --- | --- |');
    for (const edge of edges) {
      const source = resolveSource(bundle, edge);
      const target = graph.maps.get(edge.target_map);
      const targetAnchor = target ? mapAnchor(target.journeyMap) : `[MAP:m${edge.target_map}]`;
      const targetTitle = target ? target.journeyMap.title : `(unhydrated map m${edge.target_map})`;
      const note = edge.label?.trim() || source.hint || '';
      lines.push(
        `| ${source.anchor} | ${type} | ${targetAnchor} ${targetTitle} | ${note.replace(/\|/g, '\\|')} |`,
      );
    }
    lines.push('');
  }

  // Catch any non-standard link_type that wasn't in TYPE_ORDER.
  for (const [type, edges] of grouped) {
    if (TYPE_ORDER.includes(type)) continue;
    lines.push(`## ${type}`, '');
    lines.push('| From | → | Target | Note |');
    lines.push('| --- | --- | --- | --- |');
    for (const edge of edges) {
      const source = resolveSource(bundle, edge);
      const target = graph.maps.get(edge.target_map);
      const targetAnchor = target ? mapAnchor(target.journeyMap) : `[MAP:m${edge.target_map}]`;
      const targetTitle = target ? target.journeyMap.title : `(unhydrated map m${edge.target_map})`;
      const note = edge.label?.trim() || source.hint || '';
      lines.push(
        `| ${source.anchor} | ${type} | ${targetAnchor} ${targetTitle} | ${note.replace(/\|/g, '\\|')} |`,
      );
    }
    lines.push('');
  }

  return lines.join('\n');
}
