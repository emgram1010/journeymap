# Epic A — Metrics Actor Foundation

**Goal:** Register `metrics` as a first-class actor type in the system — types, template, scaffold, API enum, and DB. This is the foundation all other metric epics depend on.

---

## ⚙️ Staff Engineer Review

### SE-A1 — Type union breakage (`ActorFields`)
`MetricsActorFields` uses `number | null`. The current `ActorFields` union is `string | null` everywhere. Introducing `number` breaks every component that reads actor fields without type narrowing — TypeScript will widen to `string | number | null` and callers will get type errors or silent runtime bugs.

**Resolution:** Add a type guard helper alongside the interface:
```typescript
export function isMetricsActorFields(f: ActorFields): f is MetricsActorFields {
  return f != null && ('csat_score' in f || 'stage_health' in f);
}
```
Use this guard in every component that reads actor fields before accessing numeric properties. Do not cast with `as`.

### SE-A2 — JSON numeric serialization from Xano
Xano stores `actor_fields` as a JSON column. When numbers are stored (`csat_score: 7.4`) and read back, they may be deserialized as strings (`"7.4"`) depending on the JSON column type configuration. Do not assume type round-trips correctly.

**Resolution:** Add a `parseMetricValue` utility on the frontend:
```typescript
export const parseMetricValue = (v: unknown): number | null =>
  v == null ? null : typeof v === 'number' ? v : Number(v) || null;
```
Call this on every `MetricsActorFields` value read from the API before using it in calculations or display.

### SE-A3 — Two sources of truth for Financial data
`FinancialActorFields.revenue_at_risk` (string) and `FinancialActorNumericFields.revenue_at_risk_value` (number) will silently diverge. If the AI writes only to the string field, the widget reads `$0`. If a user edits the numeric field, the narrative string is stale.

**Resolution:** These fields must be treated as a write-pair, not independent fields. Add to agent system prompt: "When writing any Financial monetary field, always write both the string key (narrative) and the `_value` key (numeric) in the same `update_actor_cell_fields` call." Document this constraint in the Financial actor template `rolePrompt`.

### SE-A4 — DB enum migration rollback plan
Adding `"metrics"` to a Postgres enum in Xano is a DDL operation. If it fails mid-migration (e.g. lock timeout), the enum is in an inconsistent state.

**Resolution:** Test enum addition in a staging environment first. Rollback is safe — if the enum value is never added, the `actor_type = "metrics"` validation on the API input will reject the request cleanly. No data corruption. Document: migration is non-breaking to existing records.

---

## US-MET-01 — Update `ActorType` and add `MetricsActorFields` to types.ts
**File:** `webapp/protype-2/src/types.ts`
- Add `'metrics'` to the `ActorType` union
- Add `MetricsActorFields` interface with typed numeric fields:
  - `csat_score?: number | null` — 1–10
  - `completion_rate?: number | null` — 0–100 (%)
  - `drop_off_rate?: number | null` — 0–100 (%)
  - `avg_time_to_complete?: number | null` — minutes
  - `error_rate?: number | null` — 0–100 (%)
  - `sla_compliance_rate?: number | null` — 0–100 (%)
  - `volume_frequency?: string | null` — free text (e.g. "~300 interactions/day")
  - `stage_health?: number | null` — 1–10, auto-calculated composite
- Update `ActorFields` union to include `MetricsActorFields`
- Add `isMetricsActorFields(f: ActorFields): f is MetricsActorFields` type guard (see SE-A1)
- Add `parseMetricValue(v: unknown): number | null` utility for safe JSON deserialization (see SE-A2)
- **⚠️ Staff Engineer note:** `MetricsActorFields` is the first actor interface using `number | null`. Every consumer of `ActorFields` must use the type guard before accessing numeric properties.

---

## US-MET-02 — Add Financial actor numeric paired fields to types.ts
**File:** `webapp/protype-2/src/types.ts`
- Add `FinancialActorNumericFields` interface alongside existing `FinancialActorFields`:
  - `cost_to_serve_value?: number | null` — USD numeric
  - `revenue_at_risk_value?: number | null` — USD numeric
  - `automation_savings_value?: number | null` — USD numeric
  - `revenue_leakage_value?: number | null` — USD numeric
- Existing string fields stay unchanged — numeric fields are additive paired values
- Update `ActorFields` union to include `FinancialActorNumericFields`
- Purpose: enables rollup math (sum across stages) for journey P&L in the widget
- **⚠️ Staff Engineer note (SE-A3):** String and numeric financial fields are a write-pair. Update agent system prompt and Financial `rolePrompt` to enforce writing both keys together. Without this, the two fields silently diverge.

---

## US-MET-03 — Add `metrics` template to constants.ts
**File:** `webapp/protype-2/src/constants.ts`
- Add `metrics` entry to `ACTOR_TEMPLATES` array
- `actorType: 'metrics'`, `templateKey: 'metrics-v1'`, `label: 'Metrics'`, `icon: '📊'`
- `description`: "Operational KPIs — CSAT, completion rate, drop-off, error rate, and stage health score at each stage. AI-inferred from qualitative actor content."
- 8 `CellFieldDef` entries:

| Key | Label | Placeholder |
|---|---|---|
| `csat_score` | CSAT Score (1–10) | e.g. 7.4 |
| `completion_rate` | Completion Rate (%) | e.g. 89 |
| `drop_off_rate` | Drop-off Rate (%) | e.g. 11 |
| `avg_time_to_complete` | Avg Time to Complete (min) | e.g. 4 |
| `error_rate` | Error Rate (%) | e.g. 3.2 |
| `sla_compliance_rate` | SLA Compliance Rate (%) | e.g. 91 |
| `volume_frequency` | Volume / Frequency | e.g. ~300 interactions/day |
| `stage_health` | Stage Health Score (1–10) | Auto-calculated — or override |

- `cellFieldScaffold`: all 8 keys set to `null`
- `rolePrompt`: instructs AI to infer numeric values from Customer `friction_points`/`emotions`, Internal `pain_points`/`success_criteria`, AI Agent `failure_scenarios`/`confidence_threshold`, Financial `revenue_leakage`, and Engineering `error_states_edge_cases` at the same stage

---

## US-MET-04 — Add `metrics` to add-lens API enum and scaffold block
**File:** `apis/journey_map/49_journey_lens_add_journey_map_id_POST.xs`
- Add `"metrics"` to the `actor_type` enum values list
- Add scaffold block following the existing `conditional` pattern:
  ```
  conditional {
    if ($input.actor_type == "metrics") {
      var.update $effective_template_key { value = "metrics-v1" }
      var.update $actor_fields_scaffold {
        value = {}
          |set:"csat_score":null
          |set:"completion_rate":null
          |set:"drop_off_rate":null
          |set:"avg_time_to_complete":null
          |set:"error_rate":null
          |set:"sla_compliance_rate":null
          |set:"volume_frequency":null
          |set:"stage_health":null
      }
    }
  }
  ```
- No DB schema change for `actor_fields` — it is already a JSON column

---

## US-MET-05 — Add `metrics` to DB actor_type enum
**File:** Xano DB — `journey_lens.actor_type` enum
- Add `"metrics"` to the enum values list
- **⚠️ Staff Engineer note (SE-A4):** Run in staging first. Postgres enum additions are DDL — test for lock timeouts. If migration fails, API input validation rejects `actor_type = "metrics"` cleanly — no data corruption. No rollback script needed; failure is graceful.

---

## Fields Reference

| # | Key | Type | Label | Healthy Threshold |
|---|---|---|---|---|
| 1 | `csat_score` | number 1–10 | CSAT Score | ≥ 8.0 |
| 2 | `completion_rate` | number % | Completion Rate | ≥ 90% |
| 3 | `drop_off_rate` | number % | Drop-off Rate | ≤ 10% |
| 4 | `avg_time_to_complete` | number (min) | Avg Time to Complete | context-dependent |
| 5 | `error_rate` | number % | Error Rate | ≤ 5% |
| 6 | `sla_compliance_rate` | number % | SLA Compliance Rate | ≥ 90% |
| 7 | `volume_frequency` | string | Volume / Frequency | n/a |
| 8 | `stage_health` | number 1–10 | Stage Health Score | ≥ 8.0 |
