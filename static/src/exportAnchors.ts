// US-EXP-1-03 — Canonical anchor scheme for the linked bundle.
// Every entity (map / stage / lens / cell / link) gets a deterministic
// slug-based ID so two exports of the same architecture produce
// byte-identical anchors and LLMs can resolve cross-file citations.
//
// Format reference (see EPIC-EXP-1, "Stable Anchor Scheme"):
//   [MAP:m126-linkedin-outreach]
//   [STAGE:m126-linkedin-outreach/s1-send-connection-request]
//   [LENS:m126-linkedin-outreach/l3-handoff]
//   [CELL:m126-linkedin-outreach/s1×l3]
//   [LINK:m126-linkedin-outreach/s2×l3 →exception→ m127]
//
// Stage/lens local keys preserve the convention already used in
// exportMarkdownBundle.ts: `s{i+1}-{slug(key ?? label)}`. Index is the
// 1-based position within the bundle's stages[]/lenses[] array, which
// load_bundle returns in display_order.

import type {Lens, Stage} from './types';
import type {XanoJourneyMap} from './xano';

const FALLBACK = 'item';

/** Lower-case kebab slug; empty/garbage input returns `item`. */
export function slugify(s: string | null | undefined): string {
  if (!s) return FALLBACK;
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '') || FALLBACK;
}

/** `m126-linkedin-outreach` — used for folder names and inside anchor brackets. */
export function mapSlug(map: Pick<XanoJourneyMap, 'id' | 'title'>): string {
  return `m${map.id}-${slugify(map.title)}`;
}

export function mapAnchor(map: Pick<XanoJourneyMap, 'id' | 'title'>): string {
  return `[MAP:${mapSlug(map)}]`;
}

/** `s1-send-connection-request` — index is 0-based; output is 1-based. */
export function stageLocal(stage: Stage, index: number): string {
  return `s${index + 1}-${slugify(stage.key ?? stage.label)}`;
}

export function stageAnchor(map: Pick<XanoJourneyMap, 'id' | 'title'>, stage: Stage, index: number): string {
  return `[STAGE:${mapSlug(map)}/${stageLocal(stage, index)}]`;
}

/** `l3-handoff` — index is 0-based; output is 1-based. */
export function lensLocal(lens: Lens, index: number): string {
  return `l${index + 1}-${slugify(lens.key ?? lens.label)}`;
}

export function lensAnchor(map: Pick<XanoJourneyMap, 'id' | 'title'>, lens: Lens, index: number): string {
  return `[LENS:${mapSlug(map)}/${lensLocal(lens, index)}]`;
}

/** Short form `s{N}×l{M}` — used inside [CELL:…] and [LINK:…] anchors. */
export function cellLocal(stageIndex: number, lensIndex: number): string {
  return `s${stageIndex + 1}×l${lensIndex + 1}`;
}

export function cellAnchor(
  map: Pick<XanoJourneyMap, 'id' | 'title'>,
  stageIndex: number,
  lensIndex: number,
): string {
  return `[CELL:${mapSlug(map)}/${cellLocal(stageIndex, lensIndex)}]`;
}

/**
 * `[LINK:m126-linkedin-outreach/s2×l3 →exception→ m127]`
 * `link_type` is preserved verbatim in the arrow segment.
 */
export function linkAnchor(
  sourceMap: Pick<XanoJourneyMap, 'id' | 'title'>,
  sourceStageIndex: number,
  sourceLensIndex: number,
  linkType: string,
  targetMapId: number,
): string {
  return `[LINK:${mapSlug(sourceMap)}/${cellLocal(sourceStageIndex, sourceLensIndex)} →${linkType}→ m${targetMapId}]`;
}

/**
 * Resolve a 0-based stage/lens index from an entity id within a bundle.
 * Returns -1 when not found, so callers can branch on synthesised edges
 * (parent_child, agent_manual) where source_cell may be null.
 */
export function indexOfStageId(stages: Stage[], stageId: string | number): number {
  return stages.findIndex((s) => s.id === stageId || s.xanoId === stageId);
}

export function indexOfLensId(lenses: Lens[], lensId: string | number): number {
  return lenses.findIndex((l) => l.id === lensId || l.xanoId === lensId);
}
