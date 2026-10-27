// EST-1 (US-EST-1-03/04) — THE ONE FORMULA. Nothing else in this app
// computes "baseline + sum(quantity x rate)" — the planner, the Health
// page and the backend's XanoScript twin (functions/estimate/
// estimate_job.xs) all call this (or its twin) and read the result.
//
// Pure, no I/O: given a frozen version snapshot (schema v1 or v2 —
// RATE-1) plus a job's order lines, it returns a per-stage estimate.
// It never throws for a missing rate — that is `missing`/`complete`,
// not an error — and it never falls back to a guessed constant.
//
// D-1 (RATE-1): a v1 snapshot (no Items row) has no `scaling`/`rates`
// keys at all. Every stage there is simply `per_order`, `has_items_row`
// is false, and `complete` is unconditionally true — lines are not
// even possible on such a job (E-EST-004 blocks them at creation).
//
// ROUNDING (PRD §6.2): round the STAGE'S total (baseline + variable)
// half-up to a whole minute, then sum the (now whole) stage totals.
// Baseline is always already a whole number (TIME-1's duration_to_minutes
// never returns a fraction), and rounding commutes with adding an
// integer, so rounding `variable_minutes` alone and adding the intact
// `baseline_minutes` gives the identical answer with one fewer place
// to get wrong.
//
// SOURCE is per stage, one of exactly three values — "measured" only
// when every rate actually used at that stage is measured, "seed" the
// moment any one of them is, "n/a" when no rate contributed anything
// (a per_order stage, or a per_unit stage with no lines/no matches).
// NOTE: the epic's own illustrative sample JSON shows a fourth value,
// "mixed", on a stage that used only one (seed) rate — that is a
// leftover from an earlier draft, not a value the prose rule or the
// test plan (UT-EST-1-09: measured / seed / n/a) ever names. This
// module follows the rule and the test plan, not the stale example.

export type ScalesWith = 'per_order' | 'per_unit' | 'per_flagged_unit';
export type RateSource = 'seed' | 'measured';
export type EstimateSource = 'measured' | 'seed' | 'n/a';

/** One stage, in the job's pinned version's display order. */
export interface EstimateStageSnapshot {
  key: string;
  owner_lens_key: string | null;
}

/** One work cell on the pinned version — only the field this module needs. */
export interface EstimateCellSnapshot {
  stage_key: string;
  lens_key: string;
  duration_minutes: number | null;
}

/** RATE-1 schema v2 — one stage's scaling choice. */
export interface EstimateScalingSnapshot {
  stage_key: string;
  scales_with: ScalesWith;
}

/** RATE-1 schema v2 — one frozen rate. */
export interface EstimateRateSnapshot {
  stage_key: string;
  quantity_key: string;
  method_key: string;
  minutes_per_unit: number;
  source: RateSource;
}

/** The slice of a journey_map_version.snapshot this module reads. */
export interface EstimateSnapshot {
  schema_version: number;
  stages: EstimateStageSnapshot[];
  cells: EstimateCellSnapshot[];
  /** Absent entirely on a v1 (no Items row) snapshot. */
  scaling?: EstimateScalingSnapshot[];
  /** Absent entirely on a v1 (no Items row) snapshot. */
  rates?: EstimateRateSnapshot[];
}

/** One order line (work_item_line), already resolved to its item's stable key. */
export interface EstimateLine {
  quantity_key: string;
  quantity: number;
  flagged_quantity: number;
}

export interface EstimateMethodTotal {
  method_key: string;
  minutes: number;
}

export interface EstimateMissingLine {
  stage_key: string;
  quantity_key: string;
}

export interface EstimateStageResult {
  stage_key: string;
  /** Review finding (EST-1 Opus pass): callers must only apply this stage's total to the task whose lens_key matches this — a second actor at the same stage keeps its own cell duration. */
  owner_lens_key: string | null;
  scales_with: ScalesWith;
  baseline_minutes: number;
  variable_minutes: number;
  total_minutes: number;
  source: EstimateSource;
  by_method: EstimateMethodTotal[];
  /** quantity_keys with no matching rate at this stage. */
  missing: string[];
}

export type EstimateReason = 'no_lines';

export interface EstimateResult {
  has_items_row: boolean;
  complete: boolean;
  total_minutes: number;
  stages: EstimateStageResult[];
  /** The same misses as stages[].missing, flattened for display/navigation. */
  missing: EstimateMissingLine[];
  reasons: EstimateReason[];
}

/** Half-up rounding, same family as TIME-1's `toMinutes`. */
function roundHalfUp(value: number): number {
  return Math.floor(value + 0.5);
}

/**
 * Computes one stage's estimate. Exported separately (mirrors
 * functions/estimate/stage_estimate.xs) so a caller that only needs
 * one stage — the planner's card-schedule endpoints read one stage at
 * a time — is not forced to pay for or re-derive the whole job.
 */
export function stageEstimate(
  stage: EstimateStageSnapshot,
  scalesWith: ScalesWith,
  baselineMinutes: number,
  rates: EstimateRateSnapshot[],
  lines: EstimateLine[],
  ownerLensKey: string | null = stage.owner_lens_key,
): EstimateStageResult {
  let variableRaw = 0;
  const byMethod = new Map<string, number>();
  const missing: string[] = [];
  let usedAny = false;
  let usedAnySeed = false;

  if (scalesWith === 'per_unit' || scalesWith === 'per_flagged_unit') {
    for (const line of lines) {
      // Review finding (EST-1 Opus pass): the XanoScript twin reads an
      // absent flagged_quantity as 0 (?? 0 at the call site); match
      // that here so a line missing the field never turns a per_
      // flagged_unit contribution into NaN.
      const count = scalesWith === 'per_unit' ? line.quantity : line.flagged_quantity ?? 0;
      const matches = rates.filter((r) => r.stage_key === stage.key && r.quantity_key === line.quantity_key);

      if (matches.length === 0) {
        // D-IR-16: a per_flagged_unit line with nothing flagged yet is
        // not missing — there is nothing to look up for it yet.
        if (!(scalesWith === 'per_flagged_unit' && count === 0)) {
          missing.push(line.quantity_key);
        }
        continue;
      }

      if (count === 0) continue;

      for (const rate of matches) {
        const minutes = count * rate.minutes_per_unit;
        variableRaw += minutes;
        byMethod.set(rate.method_key, (byMethod.get(rate.method_key) ?? 0) + minutes);
        usedAny = true;
        if (rate.source === 'seed') usedAnySeed = true;
      }
    }
  }

  const variableMinutes = roundHalfUp(variableRaw);
  const byMethodSorted = Array.from(byMethod.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([method_key, minutes]) => ({method_key, minutes: roundHalfUp(minutes)}));

  const source: EstimateSource = !usedAny ? 'n/a' : usedAnySeed ? 'seed' : 'measured';

  return {
    stage_key: stage.key,
    owner_lens_key: ownerLensKey,
    scales_with: scalesWith,
    baseline_minutes: baselineMinutes,
    variable_minutes: variableMinutes,
    total_minutes: baselineMinutes + variableMinutes,
    source,
    by_method: byMethodSorted,
    missing,
  };
}

/** The one formula. See the module header. */
export function estimateJob(snapshot: EstimateSnapshot, lines: EstimateLine[]): EstimateResult {
  const hasItemsRow = (snapshot.schema_version ?? 1) >= 2;

  const cellByStageLens = new Map<string, EstimateCellSnapshot>();
  for (const cell of snapshot.cells) {
    cellByStageLens.set(`${cell.stage_key}::${cell.lens_key}`, cell);
  }

  const scalingByStage = new Map<string, ScalesWith>();
  for (const s of snapshot.scaling ?? []) {
    scalingByStage.set(s.stage_key, s.scales_with);
  }

  const rates = snapshot.rates ?? [];
  const effectiveLines = hasItemsRow ? lines : [];

  const stages: EstimateStageResult[] = snapshot.stages.map((stage) => {
    const ownerCell = stage.owner_lens_key != null ? cellByStageLens.get(`${stage.key}::${stage.owner_lens_key}`) : undefined;
    const baseline = ownerCell?.duration_minutes ?? 0;
    const scalesWith: ScalesWith = hasItemsRow ? scalingByStage.get(stage.key) ?? 'per_order' : 'per_order';
    return stageEstimate(stage, scalesWith, baseline, rates, effectiveLines, stage.owner_lens_key);
  });

  const missing: EstimateMissingLine[] = [];
  for (const stage of stages) {
    for (const quantity_key of stage.missing) {
      missing.push({stage_key: stage.stage_key, quantity_key});
    }
  }

  const reasons: EstimateReason[] = [];
  if (hasItemsRow && lines.length === 0) {
    reasons.push('no_lines');
  }

  const complete = !hasItemsRow || (missing.length === 0 && reasons.length === 0);
  const total_minutes = stages.reduce((sum, s) => sum + s.total_minutes, 0);

  return {
    has_items_row: hasItemsRow,
    complete,
    total_minutes,
    stages,
    missing,
    reasons,
  };
}
