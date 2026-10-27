// EXC-1 (US-EXC-1-08) — Which maps a step can send work to, and what the
// child job is called.
//
// `exceptionLinksForStage` reads the job's PINNED snapshot (`links[]`,
// written by build_map_snapshot since PUB-1), never the live map: a job
// runs on the version it started with. Stage-matched, ANY lens (D-10 —
// the Items row or a description cell may hold the link while the
// performer's step is on the actor row). `exception` only (D-6): a
// `sub_journey` is a method's how-to and never starts a job.
//
// `childTitle` is the one frontend copy of the title rule; the spawn
// endpoint mirrors it. The snapshot's links carry no label (adding one
// would change the version hash), so the backend passes the target map's
// title; `linkLabel` exists for a caller that has one.

export type SnapshotLink = {stage_key?: string; lens_key?: string; link_type?: string; target_map_id?: number};
export type ExceptionLink = {stage_key: string; lens_key: string; target_map_id: number};

export const CHILD_TITLE_MAX = 120;

export function exceptionLinksForStage(snapshot: {links?: SnapshotLink[] | null}, stageKey: string): ExceptionLink[] {
  const out: ExceptionLink[] = [];
  const seen = new Set<number>();
  for (const l of snapshot.links ?? []) {
    if (l.link_type !== 'exception' || l.stage_key !== stageKey) continue;
    const target = l.target_map_id ?? 0;
    if (!(target > 0) || seen.has(target)) continue;
    seen.add(target);
    out.push({stage_key: stageKey, lens_key: l.lens_key ?? '', target_map_id: target});
  }
  return out;
}

export type MovedForTitle = {quantity: number; label: string};

export function childTitle(parentTitle: string, linkLabel: string, targetTitle: string, moved: MovedForTitle[]): string {
  const name = linkLabel.trim() !== '' ? linkLabel.trim() : targetTitle.trim();
  const base = `${parentTitle.trim()} · ${name}`;
  let suffix = '';
  if (moved.length === 1) suffix = ` (${moved[0].quantity} ${moved[0].label})`;
  else if (moved.length > 1) suffix = ` (${moved.reduce((n, m) => n + m.quantity, 0)} items)`;
  const room = CHILD_TITLE_MAX - suffix.length;
  const cut = base.length > room ? base.slice(0, room).trimEnd() : base;
  return cut + suffix;
}

// ── US-EXC-1-01 — the map author's view of the same links ─────────────────

/** One plain line per link type, shown under the cell link picker. */
export const LINK_TYPE_HELP: Record<'exception' | 'anti_journey' | 'sub_journey', string> = {
  exception: 'Work leaves this journey here and continues on the linked map. Performers can send part of a job there.',
  anti_journey: "The person didn't follow the expected path here; the linked map handles the alternate route.",
  sub_journey: 'How this stage is done, in more detail. Shown as steps; never starts a separate job.',
};

export type LiveCellLink = {sourceCellId: number; linkType: string; targetMapId: number};

/**
 * Stage id → the titles of the maps its cells hand work off to (`exception`
 * links only, any row, one entry per target). Drives the stage-header chip
 * so the author sees the handoff without opening a cell. Reads the LIVE
 * links (the author is editing the live map); performers read the pinned
 * snapshot instead (`exceptionLinksForStage`).
 */
export function stageExceptionTargets(
  links: readonly LiveCellLink[],
  stageOfCell: ReadonlyMap<number, string>,
  titleOfMap: ReadonlyMap<number, string>,
): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  const seen = new Set<string>();
  for (const l of links) {
    if (l.linkType !== 'exception') continue;
    const stageId = stageOfCell.get(l.sourceCellId);
    if (!stageId) continue;
    const key = `${stageId}::${l.targetMapId}`;
    if (seen.has(key)) continue;
    seen.add(key);
    (out[stageId] ??= []).push(titleOfMap.get(l.targetMapId) ?? `map #${l.targetMapId}`);
  }
  return out;
}
