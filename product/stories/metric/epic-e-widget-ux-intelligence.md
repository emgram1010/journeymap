# Epic E — Widget UX Intelligence

**Goal:** Make the Journey Health Widget self-explanatory and proactive for a PM or BA who may not know what each metric means, where values come from, or why something shows "—". The widget should guide the user toward completing their map, not just display numbers.

**Target user:** Business Analyst or Product Manager building a journey map — not a data analyst. They understand delivery performance concepts but don't know the field schema.

---

## Design Principles

1. **Don't show silence** — "—" with no context is worse than nothing. Always explain why a value is missing.
2. **Source transparency** — every metric should be traceable to a specific actor row/field.
3. **Phase-aware** — a map in planning has different expectations than a map in review. The widget should know the difference and not shame the user for missing data.
4. **AI as the bridge** — if data is missing, the AI can fill it. One click should get the user there.

---

## US-MET-15 — Tooltip info icons on each widget row

**File:** `webapp/protype-2/src/JourneyHealthWidget.tsx`

Each metric row gets a `?` icon (info tooltip on hover) explaining:
- What the metric measures
- Where the value comes from (which actor row + field)
- What a good value looks like

| Metric | Tooltip text |
|---|---|
| Score | Avg stage_health across all Metrics lens cells (1–10). Healthy ≥ 8.0. Populated by the Metrics actor row. |
| Revenue at Risk | Sum of revenue_at_risk from Financial Intelligence cells. Shows — until financial actor fields are filled. |
| Critical Stages | Count of stages where stage_health < 5. Zero is good. |

---

## US-MET-16 — Smart empty states (phase-aware messaging)

**File:** `webapp/protype-2/src/JourneyHealthWidget.tsx`

Replace all `—` with context-aware messages that tell the user *why* and *how to fix it*.

**Rules:**

| Condition | Current | New |
|---|---|---|
| No metrics lens exists | "No metrics yet — add a Metrics row" | Same + "Add Row → Metrics" button hint |
| Metrics lens exists, 0 cells populated | "No metrics yet" | "Metrics row added — ask AI to populate scores" + AI nudge |
| Metrics partially populated (1–5 of 6) | Score shows, others show — | "X of 6 stages scored · ask AI to complete" |
| Revenue at Risk = — | — | "No financial data · populate Financial lens fields" |
| All 6 stages populated | Score + deltas | Full widget — no hint needed |

**Phase banner (top of widget when < 3 stages populated):**
```
📋 Planning mode — X of 6 stages have metrics data
```

---

## US-MET-17 — AI nudge button in widget

**File:** `webapp/protype-2/src/JourneyHealthWidget.tsx` + `App.tsx`

When a metric row shows an empty state, show a small **"Ask AI →"** button that:
- Opens the chat panel (if not already open)
- Pre-fills the input with the right prompt for that metric:
  - Score missing → `"populate the Metrics actor cell fields for all stages — infer from existing actor rows"`
  - Revenue at Risk missing → `"populate the revenue_at_risk field in the Financial Intelligence cells"`

Widget calls a callback prop `onAiNudge(prompt: string)` which App.tsx wires to open chat + pre-fill.

---

## US-MET-18 — Completeness progress bar

**File:** `webapp/protype-2/src/JourneyHealthWidget.tsx`

In expanded state, show a thin progress bar above the stage breakdown:

```
Metrics coverage  ████████░░  4 / 6 stages
```

Color: amber when < 50%, green when ≥ 80%.
Source: `metrics_rollup.populated_count / metrics_rollup.total_count`

---

## Implementation Priority

| Story | Effort | Value | Status |
|---|---|---|---|
| US-MET-15 Tooltips | Low | High | ✅ Done |
| US-MET-16 Smart empty states | Low | High | ✅ Done |
| US-MET-17 AI nudge | Medium | High | ✅ Done |
| US-MET-18 Progress bar | Low | Medium | ✅ Done |
