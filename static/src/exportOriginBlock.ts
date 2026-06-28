// US-EXP-1-04 — Origin block emitter for non-root maps.
// Each non-root README.md opens with a YAML frontmatter block + `> Origin.`
// callout naming the parent map / stage / lens / cell and inlining the
// parent cell content so the sub-map is self-explanatory in isolation.
//
// For the root map we emit a placeholder frontmatter with `link_type: root`
// and no parent fields so every README has a consistent shape.

import {cellAnchor, cellLocal, lensAnchor, mapAnchor, stageAnchor} from './exportAnchors';
import type {LinkedGraph, LinkedGraphEdge} from './linkedGraphClient';
import type {HydratedJourneyMapBundle} from './xano';

/** Pick the first BFS-order edge that discovered this map. Null when none (= root). */
function findParentEdge(graph: LinkedGraph, mapId: number): LinkedGraphEdge | null {
  for (const edge of graph.links) {
    if (edge.target_map === mapId) return edge;
  }
  return null;
}

function yamlEscape(value: string | null | undefined): string {
  if (value === null || value === undefined) return 'null';
  const s = String(value).trim();
  if (s === '') return 'null';
  // Quote when the string contains chars that would break YAML scalar parsing.
  if (/[:#\[\]{}&*!|>'"%@`,?\n]/.test(s)) {
    return `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  }
  return s;
}

interface ParentResolution {
  parentBundle: HydratedJourneyMapBundle;
  stageIndex: number; // -1 when not resolvable
  lensIndex: number; // -1 when not resolvable
}

function resolveParent(graph: LinkedGraph, edge: LinkedGraphEdge): ParentResolution | null {
  const parentBundle = graph.maps.get(edge.source_map);
  if (!parentBundle) return null;
  let stageIndex = -1;
  let lensIndex = -1;

  if (edge.source_cell != null) {
    const cell = parentBundle.cells.find((c) => c.xanoId === edge.source_cell);
    if (cell) {
      stageIndex = parentBundle.stages.findIndex((s) => s.xanoId === cell.stageXanoId);
      lensIndex = parentBundle.lenses.findIndex((l) => l.xanoId === cell.lensXanoId);
    }
  }
  if (lensIndex < 0 && edge.source_lens != null) {
    lensIndex = parentBundle.lenses.findIndex((l) => l.xanoId === edge.source_lens);
  }
  return {parentBundle, stageIndex, lensIndex};
}

function buildRootBlock(targetBundle: HydratedJourneyMapBundle): string {
  const m = targetBundle.journeyMap;
  const lines = [
    '---',
    `map_id: m${m.id}`,
    `title: ${yamlEscape(m.title)}`,
    'link_type: root',
    '---',
    '',
    '> **Origin.** This is the root map of the bundle. It was the entry point selected for export; every other map in this bundle is reachable from here via a journey link, a parent-child relation, or an `ai_agent` operating-manual reference.',
    '',
  ];
  return lines.join('\n');
}

export function buildOriginBlock(graph: LinkedGraph, mapId: number): string {
  const target = graph.maps.get(mapId);
  if (!target) return '';
  if (mapId === graph.rootMapId) return buildRootBlock(target);

  const edge = findParentEdge(graph, mapId);
  if (!edge) return buildRootBlock(target); // defensive: orphan map gets root shape

  const m = target.journeyMap;
  const resolved = resolveParent(graph, edge);
  const lines: string[] = ['---'];
  lines.push(`map_id: m${m.id}`);
  lines.push(`title: ${yamlEscape(m.title)}`);
  lines.push(`link_type: ${edge.link_type}`);

  if (!resolved) {
    // Parent bundle missing (hydrate failure) — still emit a partial block.
    lines.push(`parent_map: [MAP:m${edge.source_map}]`);
    lines.push('---', '');
    lines.push(
      `> **Origin.** This map was reached via a \`${edge.link_type}\` edge from map \`m${edge.source_map}\`. The parent map could not be hydrated, so detailed parent context is unavailable.`,
      '',
    );
    return lines.join('\n');
  }

  const {parentBundle, stageIndex, lensIndex} = resolved;
  const parentMap = parentBundle.journeyMap;
  const stage = stageIndex >= 0 ? parentBundle.stages[stageIndex] : null;
  const lens = lensIndex >= 0 ? parentBundle.lenses[lensIndex] : null;
  const cell =
    stageIndex >= 0 && lensIndex >= 0
      ? parentBundle.cells.find((c) => c.stageXanoId === stage?.xanoId && c.lensXanoId === lens?.xanoId)
      : null;

  lines.push(`parent_map: ${mapAnchor(parentMap)}`);
  if (stage) lines.push(`parent_stage: ${stageAnchor(parentMap, stage, stageIndex)} ${yamlEscape(stage.label)}`);
  if (lens) lines.push(`parent_lens: ${lensAnchor(parentMap, lens, lensIndex)} (${lens.actorType ?? 'unknown'} actor)`);
  if (stage && lens) lines.push(`parent_cell: ${cellAnchor(parentMap, stageIndex, lensIndex)}`);
  if (lens?.personaDescription) lines.push(`parent_actor_persona: ${yamlEscape(lens.personaDescription)}`);
  lines.push('---', '');

  // Prose callout — inlines parent cell content + stage goal + lens persona/goal verbatim.
  const cellRef = stage && lens ? cellAnchor(parentMap, stageIndex, lensIndex) : mapAnchor(parentMap);
  const cellQuote = cell?.content?.trim();
  const stageGoal = stage?.stageGoal?.trim();
  const lensGoal = lens?.primaryGoal?.trim();

  lines.push(
    `> **Origin.** This map handles the \`${edge.link_type}\` path triggered at ${cellRef} in ${mapAnchor(parentMap)}.`,
  );
  if (cellQuote) {
    lines.push(`>`, `> The parent cell says: "${cellQuote.replace(/\n+/g, ' ')}"`);
  }
  if (stageGoal) {
    lines.push(`>`, `> Parent stage goal: ${stageGoal}`);
  }
  if (lensGoal) {
    lines.push(`>`, `> Parent actor's primary goal: ${lensGoal}`);
  }
  lines.push('');
  return lines.join('\n');
}
