# Epic D — Floating Journey Health Widget

**Goal:** A floating, draggable widget on the journey map that shows 3 key PM metrics in real-time — Journey Health Score, Revenue at Risk, and Critical Stages — with green/red delta tracking as the map is edited. Designed for a Staff PM making strategic decisions while building the map. Depends on Epics A and C for data.

---

## ⚙️ Staff Engineer Review

### SE-D1 — Polling on every cell save hammers the scorecard API
During AI bulk fills (10+ cells), a scorecard fetch fires after every single cell save. With network latency this creates a request queue of 10+ concurrent fetches, stale data races, and unnecessary load.

**Resolution:** Debounce the scorecard refresh with a 2-second delay after last cell save. Use `AbortController` to cancel the in-flight request before firing a new one. Pattern:
```typescript
const debouncedRefresh = useMemo(() =>
  debounce((signal: AbortSignal) => fetchScorecard(mapId, signal), 2000), [mapId]);
```

### SE-D2 — `$0` vs `null` for missing financial data
If no financial cells have `revenue_at_risk_value` set, summing returns `0`. The widget would show `$0 Revenue at Risk` — misleading (implies someone checked and the risk is zero).

**Resolution:** Scorecard endpoint returns `null` (not `0`) when no `revenue_at_risk_value` data exists. Widget renders `—` for null. Only show a dollar value when at least one financial cell has a numeric value.

### SE-D3 — Auth scope missing on scorecard endpoint
The new `GET /scorecard` endpoint reads financial data. Without auth scoping, any authenticated user could query another user's journey map scorecard by guessing `journey_map_id`.

**Resolution:** Endpoint must have `auth = "user"` and include a user ownership check: verify the requesting user owns (or has access to) the `journey_map_id` before returning data — same pattern as all other journey map endpoints.

### SE-D4 — localStorage key collision across tabs/maps
Two maps open in different tabs would write to the same key if the storage key is not fully qualified.

**Resolution:** Widget position key must be: `jh_widget_pos_{journey_map_id}`. Do not use a generic key.

### SE-D5 — Feature flag for gradual rollout
The widget and metrics actor are a significant new UI surface. Shipping to all users simultaneously risks disrupting existing workflows.

**Resolution:** Gate the entire feature behind a `METRICS_ACTOR_ENABLED` feature flag checked in App.tsx. Flag is `false` by default. Enable per-tenant or globally when ready for rollout.

### SE-D6 — Stale session baseline from concurrent edits
`sessionBaseline` is captured on map load. If another user edits the map between load and the current user's first change, the delta arrow is misleading — it shows changes made by someone else as "your improvement."

**Resolution:** Document this limitation clearly in code comments. Baseline tracks *this user's session changes*, not absolute map state. Consider a tooltip: "Delta since you opened this map."

---

## Why 3 Metrics (Design Decision)

| Metric | Dimension | Strategic question it answers |
|---|---|---|
| **Journey Health Score** | Overall signal | Is this journey getting better or worse? |
| **Revenue at Risk** | Business stake | What's the cost of inaction for leadership? |
| **Critical Stages** | Urgency | How many fires exist right now — isolated or systemic? |

One metric is too reductive (masks tradeoffs). More than three becomes a panel, not a signal. The delta arrow matters more than the absolute value — the PM needs *direction*, not just *state*.

---

## US-MET-12 — Journey Health Widget component
**File:** `webapp/protype-2/src/App.tsx` or new `JourneyHealthWidget.tsx`

**Collapsed state (default):**
```
📊 Journey Health  7.4  ▲ +0.6  🟢
```

**Expanded state (hover or click):**
```
📊 Journey Health    7.4  ▲ +0.6  🟢
   Revenue at Risk  $94K  ▼ -$18K 🟢
   Critical Stages    2   ▼ -2    🟢
```

**Behavior:**
- Floating, draggable — anchored top-right of the journey matrix by default
- Position persists in `localStorage` with key `jh_widget_pos_{journey_map_id}` (see SE-D4)
- Collapsible via X button — restored via a toolbar icon button
- Click expanded state → opens full scorecard side panel (stage-by-stage breakdown table)
- Empty state when no metrics cells exist: `📊 No metrics yet — add a Metrics row to enable`
- Only renders when `METRICS_ACTOR_ENABLED` feature flag is true (see SE-D5)

**Color logic per metric:**

| Metric | 🟢 Green | 🔴 Red |
|---|---|---|
| Journey Health | ↑ improving | ↓ degrading |
| Revenue at Risk | ↓ less risk | ↑ more risk |
| Critical Stages | ↓ fewer | ↑ more |

---

## US-MET-13 — Journey scorecard rollup API endpoint
**File:** New — `apis/journey_map/XX_journey_map_journey_map_id_scorecard_GET.xs`

`GET /journey_map/{journey_map_id}/scorecard`

**Logic:**
- `auth = "user"` required — verify requesting user owns the `journey_map_id` before querying (SE-D3)
- Query all `journey_cell` records where parent lens `actor_type == "metrics"`
- Average `actor_fields.stage_health` across all metrics cells with a non-null value → `journey_health`
- Query all `journey_cell` records where parent lens `actor_type == "financial"`
- Sum `actor_fields.revenue_at_risk_value` only for cells where the value is non-null → `revenue_at_risk`
- If no financial cells have `revenue_at_risk_value` set: return `revenue_at_risk: null` not `0` (SE-D2)
- Count metrics cells where `actor_fields.stage_health < 6` → `critical_stages`

**Response shape:**
```json
{
  "journey_health": 7.4,
  "revenue_at_risk": 94000,
  "critical_stages": 2,
  "metrics_cell_count": 6,
  "stage_breakdown": [
    {
      "stage_label": "Order & Inventory Lock",
      "stage_health": 7.8,
      "csat_score": 8.1,
      "completion_rate": 94,
      "drop_off_rate": 6
    },
    {
      "stage_label": "72-Hr Pre-Delivery Prep",
      "stage_health": 6.9,
      "csat_score": 7.4,
      "completion_rate": 89,
      "drop_off_rate": 11
    }
  ]
}
```

- Returns `null` for any field where no data exists yet
- Widget handles null gracefully with "—" placeholder

---

## US-MET-14 — Widget delta tracking (session-level baseline)
**File:** `webapp/protype-2/src/App.tsx`

**Baseline capture:**
- On map load (or first scorecard fetch), store result as `sessionBaseline` in component state
- `sessionBaseline` is never persisted — resets on refresh or navigation

**Delta display:**
- After every cell save (any actor type), debounce-refresh the scorecard endpoint (2s delay, AbortController — see SE-D1)
- Compare new values to `sessionBaseline` and display delta:
  - `▲ +0.6` — improved (green)
  - `▼ -0.4` — degraded (red)
  - `—` — no change (neutral grey)

**Full scorecard side panel (on widget click):**
- Slides in from the right (same pattern as cell detail panel)
- Shows stage-by-stage breakdown table from `stage_breakdown` in scorecard response
- Color-coded per stage using the same thresholds as the cell display (Epic B)
- "Weakest stages" section at top: sorted by `stage_health` ascending, top 3 highlighted
- Closes with X or clicking outside

---

## Notes

- Widget only renders when `METRICS_ACTOR_ENABLED` flag is true AND a `metrics` lens row exists (SE-D5)
- `revenue_at_risk` reads from `FinancialActorNumericFields.revenue_at_risk_value` — requires Epic A MET-02
- Scorecard endpoint: lightweight, `auth = "user"`, ownership-scoped (SE-D3)
- `revenue_at_risk: null` in response → widget shows `—`, never `$0` (SE-D2)
- Session baseline tracks this user's session changes only — not concurrent edits from others (SE-D6). Tooltip: "Delta since you opened this map."
- Future phase: swap polling for websocket update — design the refresh hook with a clean abstraction (`useScorecard`) so the transport layer can be replaced without touching widget UI
