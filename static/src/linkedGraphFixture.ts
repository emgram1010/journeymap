// US-EXP-1-12 — Pure in-memory fixture for the round-trip sanity test.
// Builds a `LinkedGraph` mirroring the acceptance shape:
//   parent (root) + 2 sub-journeys + 1 exception + 1 ai_agent operating manual.
// No network, no DOM — safe to consume from node:test.

import type {LinkedGraph} from './linkedGraphClient';
import type {Lens, MatrixCell, Stage} from './types';
import type {HydratedJourneyMapBundle, LinkedGraphEdge, LinkedGraphWarning, XanoJourneyMap} from './xano';

interface MapSeed {
  id: number;
  title: string;
  mapLevel?: 'architecture' | 'actor-journey' | 'atomic';
}

function makeBundle(seed: MapSeed): HydratedJourneyMapBundle {
  const journeyMap: XanoJourneyMap = {
    id: seed.id,
    created_at: 1_700_000_000,
    title: seed.title,
    status: 'draft',
    journey_architecture: 999,
    map_level: seed.mapLevel ?? 'actor-journey',
  } as XanoJourneyMap;

  const stages: Stage[] = [
    {id: `s${seed.id}-1`, key: `stage-one-${seed.id}`, xanoId: seed.id * 100 + 1, label: 'Stage One', stageGoal: 'Reach milestone'},
    {id: `s${seed.id}-2`, key: `stage-two-${seed.id}`, xanoId: seed.id * 100 + 2, label: 'Stage Two'},
  ];
  const lenses: Lens[] = [
    {id: `l${seed.id}-1`, key: `customer-${seed.id}`, xanoId: seed.id * 1000 + 1, label: 'Customer', actorType: 'customer', primaryGoal: 'Get value'},
    {id: `l${seed.id}-2`, key: `agent-${seed.id}`, xanoId: seed.id * 1000 + 2, label: 'Agent', actorType: 'ai_agent', personaDescription: 'AI helper'},
  ];

  const cells: MatrixCell[] = [];
  let cellCounter = 1;
  for (const s of stages) {
    for (const l of lenses) {
      cells.push({
        id: `c${seed.id}-${s.xanoId}-${l.xanoId}`,
        xanoId: seed.id * 10_000 + cellCounter,
        stageId: s.id,
        stageXanoId: s.xanoId,
        lensId: l.id,
        lensXanoId: l.xanoId,
        content: `Cell content for ${s.label} × ${l.label}`,
        status: 'draft',
      });
      cellCounter += 1;
    }
  }

  return {
    journeyMap,
    stages,
    lenses,
    cells,
    conversation: null,
    messages: [],
    source: 'business',
    hasHydratedMatrix: true,
  };
}

/**
 * Returns the canonical fixture graph used by the round-trip test:
 *   m100 (root) → sub_journey → m101
 *   m100        → sub_journey → m102
 *   m100        → exception   → m103
 *   m100        → agent_manual → m104
 */
export function buildFixtureLinkedGraph(): LinkedGraph {
  const root = makeBundle({id: 100, title: 'Root Architecture', mapLevel: 'architecture'});
  const sub1 = makeBundle({id: 101, title: 'Sub Journey One'});
  const sub2 = makeBundle({id: 102, title: 'Sub Journey Two'});
  const exc = makeBundle({id: 103, title: 'Exception Recovery'});
  const agent = makeBundle({id: 104, title: 'Agent Manual', mapLevel: 'atomic'});

  // Pick anchor cells on the root for source_cell on each edge.
  const rootStage1 = root.stages[0];
  const rootStage2 = root.stages[1];
  const rootLens1 = root.lenses[0];
  const rootLens2 = root.lenses[1];
  const cellAt = (sId: number, lId: number) =>
    root.cells.find((c) => c.stageXanoId === sId && c.lensXanoId === lId)!;

  const links: LinkedGraphEdge[] = [
    {
      source_map: 100,
      target_map: 101,
      link_type: 'sub_journey',
      label: 'Delegate path A',
      source_cell: cellAt(rootStage1.xanoId!, rootLens1.xanoId!).xanoId ?? null,
      source_lens: rootLens1.xanoId,
      source_lens_label: rootLens1.label,
      journey_architecture: 999,
    },
    {
      source_map: 100,
      target_map: 102,
      link_type: 'sub_journey',
      label: 'Delegate path B',
      source_cell: cellAt(rootStage1.xanoId!, rootLens2.xanoId!).xanoId ?? null,
      source_lens: rootLens2.xanoId,
      source_lens_label: rootLens2.label,
      journey_architecture: 999,
    },
    {
      source_map: 100,
      target_map: 103,
      link_type: 'exception',
      label: 'Recovery branch',
      source_cell: cellAt(rootStage2.xanoId!, rootLens1.xanoId!).xanoId ?? null,
      source_lens: rootLens1.xanoId,
      source_lens_label: rootLens1.label,
      journey_architecture: 999,
    },
    {
      source_map: 100,
      target_map: 104,
      link_type: 'agent_manual',
      label: null,
      source_cell: null,
      source_lens: rootLens2.xanoId,
      source_lens_label: rootLens2.label,
      journey_architecture: 999,
    },
  ];

  const warnings: LinkedGraphWarning[] = [];
  const maps = new Map<number, HydratedJourneyMapBundle>();
  for (const b of [root, sub1, sub2, exc, agent]) maps.set(b.journeyMap.id, b);

  return {
    rootMapId: 100,
    architectureId: 999,
    maps,
    links,
    warnings,
    walkStatus: 'complete',
    bfsOrder: [100, 101, 102, 103, 104],
  };
}
