// PUB-1 (US-PUB-1-03/04) — The canonical serialisation a version's
// content_hash is computed from.
//
// WHY A HAND-BUILT STRING AND NOT JSON.stringify: the hash has to come
// out byte-identical on two different runtimes (this module, and
// functions/pub/canonical_hash.xs on Xano). JSON encoders differ on key
// order, whitespace, unicode escaping and number formatting, so encoding
// JSON on both sides would be a silent-divergence trap. Explicit
// concatenation in a fixed field order is reproducible anywhere.
//
// The canonicaliser is a pure function of the SNAPSHOT (not of the live
// database), including its array order. That is what makes
// verify_version meaningful: re-serialising a stored snapshot must
// reproduce the stored hash, or the row has been tampered with.

/** One stage, in the map's display order. */
export interface SnapshotStage {
  key: string;
  label: string;
  /** The lens key of the stage's owner, or null when unowned. */
  owner_lens_key: string | null;
}

/** One row (lens), in the map's display order. */
export interface SnapshotLens {
  key: string;
  label: string;
  actor_type: string;
  /** Resolved value (override, else the actor_type default) — see STAGE-1. */
  does_planned_work: boolean;
}

/** One work cell. Only cells on work-doing rows that have something in them are stored. */
export interface SnapshotCell {
  stage_key: string;
  lens_key: string;
  task: string | null;
  done_when: string | null;
  /** Whole minutes (TIME-1's toMinutes), or null when not set. */
  duration_minutes: number | null;
}

/** One cell→map link. */
export interface SnapshotLink {
  stage_key: string;
  lens_key: string;
  link_type: string;
  target_map_id: number;
}

/** RATE-1 (schema v2) — how one stage's time scales, from the Items row. */
export interface SnapshotScaling {
  stage_key: string;
  scales_with: 'per_order' | 'per_unit' | 'per_flagged_unit';
}

/** RATE-1 (schema v2) — one frozen rate: minutes per unit of an item, by a method, at a stage. */
export interface SnapshotRate {
  stage_key: string;
  quantity_key: string;
  method_key: string;
  /** At most 2 decimals — the Items cell validator (E-ITM-004) and build_map_snapshot both enforce it. */
  minutes_per_unit: number;
  source: 'seed' | 'measured';
}

export interface MapSnapshot {
  schema_version: number;
  title: string;
  stages: SnapshotStage[];
  lenses: SnapshotLens[];
  cells: SnapshotCell[];
  links: SnapshotLink[];
  /** Schema v2 only. Absent on every v1 snapshot. */
  scaling?: SnapshotScaling[];
  /** Schema v2 only. Absent on every v1 snapshot. */
  rates?: SnapshotRate[];
}

/**
 * Escapes a text field so a value containing the field or line separator
 * can never be mistaken for structure. Backslash first, or the other two
 * escapes would be double-escaped on the way back.
 */
export function escapeField(value: string | null | undefined): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/\\/g, '\\\\')
    .replace(/\|/g, '\\p')
    .replace(/\r/g, '')
    .replace(/\n/g, '\\n');
}

/** Whole minutes as text, or empty when not set. */
function minutesField(minutes: number | null | undefined): string {
  if (minutes === null || minutes === undefined) return '';
  return String(minutes);
}

/**
 * RATE-1 — a rate's minutes, always fixed 2 decimals with no thousands
 * separator (`0.00`, `0.50`, `12.25`, `1440.00`). Xano renders the same
 * value with `number_format:2:".":""`; the two agree on every value with
 * at most 2 decimals, which is all a snapshot can hold. (They can differ
 * on a half-cent like 2.005 — float vs. PHP rounding — which is exactly
 * why build_map_snapshot rounds before storing.)
 */
export function formatRateMinutes(minutes: number | null | undefined): string {
  // A missing value renders 0.00, exactly like canonical_hash.xs's
  // `($rt.minutes_per_unit ?? 0)` — only a malformed snapshot has one.
  return (minutes ?? 0).toFixed(2);
}

/**
 * Builds the canonical string for a snapshot. Field order is fixed here,
 * so the order of keys on the input objects is irrelevant. Array order is
 * taken as-is from the snapshot — reordering stages IS a definition
 * change and must change the hash.
 */
export function canonicalizeSnapshot(snapshot: MapSnapshot): string {
  let out = `v${snapshot.schema_version}\n`;
  out += `title|${escapeField(snapshot.title)}\n`;

  for (const stage of snapshot.stages) {
    out += `stage|${escapeField(stage.key)}|${escapeField(stage.label)}|${escapeField(stage.owner_lens_key)}\n`;
  }

  for (const lens of snapshot.lenses) {
    out += `lens|${escapeField(lens.key)}|${escapeField(lens.label)}|${escapeField(lens.actor_type)}|${lens.does_planned_work ? '1' : '0'}\n`;
  }

  for (const cell of snapshot.cells) {
    out += `cell|${escapeField(cell.stage_key)}|${escapeField(cell.lens_key)}|${escapeField(cell.task)}|${escapeField(cell.done_when)}|${minutesField(cell.duration_minutes)}\n`;
  }

  for (const link of snapshot.links) {
    out += `link|${escapeField(link.stage_key)}|${escapeField(link.lens_key)}|${escapeField(link.link_type)}|${link.target_map_id}\n`;
  }

  // RATE-1 — schema v2 adds the Items row's scaling and rates. Gated on
  // the snapshot's OWN schema_version, so a stored v1 snapshot still
  // re-serialises to exactly the bytes it was hashed with.
  if (snapshot.schema_version >= 2) {
    for (const s of snapshot.scaling ?? []) {
      out += `scale|${escapeField(s.stage_key)}|${escapeField(s.scales_with)}\n`;
    }
    for (const r of snapshot.rates ?? []) {
      out += `rate|${escapeField(r.stage_key)}|${escapeField(r.quantity_key)}|${escapeField(r.method_key)}|${formatRateMinutes(r.minutes_per_unit)}|${escapeField(r.source)}\n`;
    }
  }

  return out;
}

/**
 * sha256 of the canonical string, lower-case hex. Uses Web Crypto, which
 * is present in both the browser and Node 18+, so the same module works
 * in the app and in `node --test`.
 */
export async function hashSnapshot(snapshot: MapSnapshot): Promise<string> {
  const canonical = canonicalizeSnapshot(snapshot);
  const bytes = new TextEncoder().encode(canonical);
  const digest = await globalThis.crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}
