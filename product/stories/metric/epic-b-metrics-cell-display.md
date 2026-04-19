# Epic B — Metrics Cell Display

**Goal:** Render metrics cells differently from all other actor cells. Instead of plain text, metrics cells show a compact color-coded scorecard in the matrix and a structured panel in the cell detail view. Depends on Epic A.

---

## ⚙️ Staff Engineer Review

### SE-B1 — NaN in stage health formula when fields are null
`null / 10 = NaN` in JavaScript. With most fields empty, the auto-calculated `stage_health` would display `NaN`. The formula must be null-safe and re-weight based on available fields only.

**Resolution:** Replace the raw formula with a null-safe helper:
```typescript
export function calcStageHealth(f: MetricsActorFields): number | null {
  const parts: Array<{ value: number; weight: number }> = [];
  if (f.csat_score != null)       parts.push({ value: f.csat_score / 10, weight: 0.35 });
  if (f.completion_rate != null)  parts.push({ value: f.completion_rate / 100, weight: 0.35 });
  if (f.drop_off_rate != null)    parts.push({ value: (100 - f.drop_off_rate) / 100, weight: 0.20 });
  if (f.error_rate != null)       parts.push({ value: (100 - f.error_rate) / 100, weight: 0.10 });
  if (parts.length === 0) return null;
  const totalWeight = parts.reduce((s, p) => s + p.weight, 0);
  return (parts.reduce((s, p) => s + p.value * p.weight, 0) / totalWeight) * 10;
}
```
Returns `null` (not `NaN`) when no fields are populated. Re-weights proportionally when only some fields exist.

### SE-B2 — Hardcoded thresholds in component
Color thresholds inline in the renderer make future business rule changes a code change.

**Resolution:** Extract thresholds to `constants.ts` as a `METRICS_THRESHOLDS` map, co-located with the `MetricsActorTemplate`. Component imports from constants — no logic in the renderer.

### SE-B3 — Memoize the scorecard calculation
The health formula runs on every render for every metrics cell. In a 6-stage map this is 6 × every keystroke in the map.

**Resolution:** Wrap `calcStageHealth` call in `useMemo` keyed on the `actorFields` object reference. Only recalculates when the cell's fields actually change.

### SE-B4 — "AI Infer from Actors" button routes through chat UI
Triggering inference by injecting a chat message is fragile — it requires the chat panel to be in a specific state and couples display logic to the AI pipeline.

**Resolution:** The button should call the `infer_stage_metrics` API endpoint directly (Epic C, MET-10), not route through chat. On success, update the cell's `actorFields` in local state. The chat panel stays independent.

---

## US-MET-06 — Metrics cell matrix display (scorecard chip layout)
**File:** `webapp/protype-2/src/App.tsx` (or dedicated cell renderer component)

When a cell belongs to a `metrics` actor row, render a compact scorecard layout instead of plain text.

**Display format inside the matrix cell:**
```
Stage Health  7.4  🟡
CSAT          8.1  🟢   Completion  89%  🟡
Drop-off     11%  🔴   Error rate  3.2%  🟢
```

**Color thresholds:**

| Metric | 🟢 Green | 🟡 Yellow | 🔴 Red |
|---|---|---|---|
| `stage_health` | ≥ 8.0 | 6.0–7.9 | < 6.0 |
| `csat_score` | ≥ 8.0 | 6.0–7.9 | < 6.0 |
| `completion_rate` | ≥ 90% | 75–89% | < 75% |
| `drop_off_rate` | ≤ 10% | 11–20% | > 20% |
| `error_rate` | ≤ 5% | 6–15% | > 15% |
| `sla_compliance_rate` | ≥ 90% | 75–89% | < 75% |

**Stage health auto-calculation (frontend):**
- Use `calcStageHealth(fields)` utility from Epic A (see SE-B1) — null-safe, re-weights on partial data
- If `stage_health` is explicitly set by the user, use stored value — skip auto-calculation
- Returns `null` (not `NaN`) when no fields are populated — show `—` placeholder
- Fall back to plain text content display if no metric fields are populated yet
- **⚠️ Staff Engineer note (SE-B1, SE-B3):** Wrap in `useMemo`. Import thresholds from `METRICS_THRESHOLDS` in constants (SE-B2).

---

## US-MET-07 — Metrics cell detail panel view
**File:** `webapp/protype-2/src/App.tsx` (Cell Detail Panel section)

When the cell detail panel opens for a `metrics` actor cell, render a structured metrics panel instead of the standard `CellFieldDef` list.

**Panel layout:**
- Stage Health Score displayed prominently at the top (large number + color ring or gauge)
- Each metric below as a labeled row containing:
  - Current value (bold)
  - Color indicator dot based on threshold
  - Default benchmark shown alongside (e.g. "target: ≥ 90%")
  - "Below threshold" / "On target" label
- All values editable inline — clicking a value opens a number input
- `volume_frequency` renders as a text input (only string field)

**"AI Infer from Actors" button:**
- Appears at the top of the panel
- On click: calls `infer_stage_metrics` API endpoint directly for this cell's `stage_id` — does NOT route through the chat UI (see SE-B4)
- Shows a loading spinner while inference runs
- On success: updates the cell's `actorFields` in local React state — panel values refresh without reload
- On error: shows inline error message "Inference failed — try again or enter values manually"

---

## Design Notes

- Metrics cell matrix rendering is gated on `actorType === 'metrics'` on the parent lens
- If all metric fields are `null`, render a placeholder: `📊 No metrics yet — ask AI to infer`
- Stage health color is the dominant signal in the collapsed matrix cell — it should be visually prominent
- The detail panel replaces the standard field list entirely for metrics cells — do not render `CellFieldDef` inputs for numeric fields using the standard text area pattern
