# Execution — Phase 4: Plan vs Actual Time Gap (Per-Stage, Per-Run)

**Problem this phase solves:** Leakage math today runs at the map level — it computes a theoretical cost based on planned durations across all runs. But during a live execution, there is no per-stage comparison of how long a stage was *planned* to take vs how long it *actually* took. The `per_stage_log` captures `duration_ms` (actual), but the planned time lives only in the map cell. No one sees the gap in real time, and no one can trend it across runs.

**Goal:** Capture planned duration alongside actual duration in every `per_stage_log` entry. Surface the gap per stage, per run. Aggregate it across runs to identify which stages consistently overrun and by how much. This turns execution records into a continuous leakage signal — not just a one-time map-level estimate.

**Dependency:** Phases 1–3 must be complete. Requires `per_stage_log` (Phase 1) and the pinned snapshot (Publishing Phase 3) so planned durations are read from the certified map version, not the live editable map.

**Exit condition for this phase:** Every `per_stage_log` entry includes `planned_duration_ms` sourced from the snapshot. A per-run gap report is available. Aggregate stage overrun metrics feed the Stage Health Panel (US-EXE-09).

---

## US-EXE-10 — Add planned_duration_ms to Per-Stage Log Entry

**What:** Extend the `per_stage_log` entry schema (defined in US-EXE-01) with two new fields that capture the planned time and the gap against actual.

**New fields added to per-stage log entry schema:**
```json
{
  "stage_key": "s3",
  "planned_duration_ms": 720000,
  "duration_ms": 940000,
  "duration_gap_ms": 220000,
  "duration_gap_pct": 30.6
}
```

**Field rules:**
- `planned_duration_ms` — sourced from `time_duration_value` + `time_duration_unit` on the primary actor cell in the pinned snapshot. Read at stage start, not at map build time.
- `duration_gap_ms` — computed: `duration_ms - planned_duration_ms`. Positive = overrun. Negative = ahead of plan.
- `duration_gap_pct` — computed: `(duration_gap_ms / planned_duration_ms) * 100`. Rounded to 1 decimal.
- If `planned_duration_ms` is null (cell has no time_duration set) — log `null` for gap fields, do not error. Flag the stage as missing planned time.

**Acceptance criteria:**
- `planned_duration_ms` is written to every `per_stage_log` entry at stage start
- `duration_gap_ms` and `duration_gap_pct` are computed and written at stage close
- Null planned duration is handled gracefully — does not block stage execution or log write

---

## US-EXE-11 — Per-Run Gap Report

**What:** After Sign Out (Gate 3), include a plan vs actual gap summary in the Sign Out report surfaced to the user. This gives the map owner immediate visibility into which stages overran and by how much — every single run.

**Gap report shape (added to Sign Out summary):**
```json
{
  "plan_vs_actual": {
    "total_planned_ms": 3600000,
    "total_actual_ms": 4320000,
    "total_gap_ms": 720000,
    "total_gap_pct": 20.0,
    "stage_gaps": [
      { "stage_key": "s3", "stage_label": "Duration Reality Check", "gap_ms": 220000, "gap_pct": 30.6, "status": "overrun" },
      { "stage_key": "s5", "stage_label": "Leakage Trigger", "gap_ms": -60000, "gap_pct": -8.3, "status": "ahead" }
    ]
  }
}
```

**Acceptance criteria:**
- Gap report is included in every Sign Out summary where at least one stage has `planned_duration_ms` set
- Stages with null planned duration are listed separately as "no plan set"
- `status` field is `overrun | ahead | on_plan` — `on_plan` when gap is within ±5%

---

## US-EXE-12 — Aggregate Overrun Metrics in Stage Health Panel

**What:** Extend the Stage Health Panel (US-EXE-09, View 2) to include plan vs actual aggregate metrics per stage across all runs. This surfaces which stages *consistently* overrun — the chronic leakage points vs the one-off exceptions.

**New metrics added to Stage Health Panel per stage:**
- `avg_gap_pct` — average duration gap across all runs where planned time was set
- `overrun_rate` — percentage of runs where the stage overran (gap > +5%)
- `worst_gap_pct` — highest single-run overrun recorded
- Flag: stages with `overrun_rate > 0.30` (30% of runs overrun) highlighted as chronic

**Why this matters:** The map says a stage takes 12 minutes. Execution data shows it takes 18 minutes on average across 40 runs. That 50% gap is a leakage signal the map-level estimate never captured. This is how execution data feeds back into map improvement.

**Acceptance criteria:**
- Stage Health Panel shows `avg_gap_pct`, `overrun_rate`, and `worst_gap_pct` per stage
- Stages with `overrun_rate > 0.30` are flagged as chronic overruns
- Metrics only compute when at least 5 runs have `planned_duration_ms` set for that stage — no misleading stats from 1–2 data points
