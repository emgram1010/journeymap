// US-EXP-1-08 — GLOSSARY.md builder for the linked bundle.
// Defines anchor grammar + lens / link-type / cell-status / plan-vs-actual
// semantics so an LLM with no prior context can answer questions correctly.
//
// Examples use real map IDs from the graph (no fictional samples) per the
// epic acceptance criteria.
//
// Soft word cap: ≤ 800 words.

import {cellLocal, lensLocal, mapSlug, stageLocal} from './exportAnchors';
import type {LinkedGraph} from './linkedGraphClient';

interface ExampleAnchors {
  mapSlug: string;
  stageLocal: string;
  lensLocal: string;
  cellLocal: string;
}

/** Pick the root map's first stage + first lens to ground anchor examples in real IDs. */
function chooseExamples(graph: LinkedGraph): ExampleAnchors {
  const root = graph.maps.get(graph.rootMapId);
  if (!root) {
    return {mapSlug: `m${graph.rootMapId}-root`, stageLocal: 's1-stage', lensLocal: 'l1-lens', cellLocal: 's1×l1'};
  }
  const stage = root.stages[0];
  const lens = root.lenses[0];
  return {
    mapSlug: mapSlug(root.journeyMap),
    stageLocal: stage ? stageLocal(stage, 0) : 's1-stage',
    lensLocal: lens ? lensLocal(lens, 0) : 'l1-lens',
    cellLocal: cellLocal(0, 0),
  };
}

export function buildGlossary(graph: LinkedGraph): string {
  const ex = chooseExamples(graph);
  const lines: string[] = [];

  lines.push('# Glossary', '');
  lines.push(
    'This file defines the vocabulary, anchor scheme, and conventions used across every file in this bundle. ' +
      'Read it once before answering questions about any specific map.',
    '',
  );

  lines.push('## Anchor grammar', '');
  lines.push('Every map, stage, lens, cell, and link in this bundle has a deterministic ID that resolves across files.', '');
  lines.push('```');
  lines.push(`[MAP:${ex.mapSlug}]`);
  lines.push(`[STAGE:${ex.mapSlug}/${ex.stageLocal}]`);
  lines.push(`[LENS:${ex.mapSlug}/${ex.lensLocal}]`);
  lines.push(`[CELL:${ex.mapSlug}/${ex.cellLocal}]`);
  lines.push(`[LINK:${ex.mapSlug}/${ex.cellLocal} →exception→ m{target_id}]`);
  lines.push('```', '');
  lines.push(
    '- `m{id}-{title-slug}` — the map slug. `{id}` is the numeric `journey_map.id`; `{title-slug}` is a lower-case kebab of the title.\n' +
      '- `s{N}-{slug}` — stage local key. `{N}` is the 1-based stage position in display order.\n' +
      '- `l{N}-{slug}` — lens local key. `{N}` is the 1-based lens position in display order.\n' +
      '- `s{N}×l{M}` — cell at the intersection of stage N and lens M.\n' +
      '- `→link_type→` — the edge type joining a source cell to a target map.',
    '',
  );

  lines.push('## Link types', '');
  lines.push(
    '- **sub_journey** — the target map is a delegated sub-process invoked at this cell. The runtime continues there until the sub completes, then returns.\n' +
      '- **exception** — the target map handles a failure or recovery path triggered at this cell. The main flow does not continue past the cell once the exception fires.\n' +
      '- **anti_journey** — the target map describes what happens when the actor does *not* follow the expected path. Useful for negative scenarios and SLA breaches.\n' +
      '- **agent_manual** — synthesised edge. Points from a lens with an `ai_agent` actor type to the journey map that serves as that agent\'s operating manual. The Orchestrator delegates execution to that map.\n' +
      '- **parent_child** — synthesised edge. Indicates a hierarchical parent → child relation via `journey_map.parent_map_id` (L1 → L2 → L3).',
    '',
  );

  lines.push('## Actor types (lens taxonomy)', '');
  lines.push(
    '- **customer** — external person whose outcome the journey serves.\n' +
      '- **internal** — employee performing work inside the org.\n' +
      '- **engineering** / **dev** — software/system builders.\n' +
      '- **handoff** — connector role bridging two actors or systems.\n' +
      '- **vendor** — third-party supplier.\n' +
      '- **financial** — money-flow perspective (revenue, cost, leakage).\n' +
      '- **operations** — day-to-day execution role.\n' +
      '- **ai_agent** — automated executor; usually has an `agent_manual` link to a sub-map.\n' +
      '- **metrics** — measurement-only row; no human actor.\n' +
      '- **custom** — domain-specific actor that doesn\'t fit the catalog.',
    '',
  );

  lines.push('## Cell status', '');
  lines.push(
    '- **empty** — no content.\n' +
      '- **draft** — content present but not yet confirmed; treat as provisional.\n' +
      '- **confirmed** — content reviewed and signed off; the source of truth.\n' +
      '- **locked** — content is frozen; further edits are blocked.',
    '',
  );

  lines.push('## Plan vs actual (atomic maps)', '');
  lines.push(
    'On L3 *atomic* maps every cell may carry duration fields:',
    '',
    '- **time_duration_value / time_duration_unit** — the canonical planned time for this cell.\n' +
      '- **planned_duration** — SOP/target time for the stage.\n' +
      '- **actual_duration** — real observed time.\n' +
      '\n' +
      'The gap between planned and actual is the *leakage signal*. Multiply by the lens `cost_rate_value` to translate leaked minutes into dollar cost.',
    '',
  );

  return lines.join('\n');
}
