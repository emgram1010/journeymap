# In-Cell Tile Display Epic

## Goal

Replace the plain notes/content text block in every matrix cell with a structured, actor-type-specific tile layout — derived from `actor_fields` — so the journey map is scannable at a glance without opening the detail panel.

---

## Current State

| Layer | What happens today |
|---|---|
| All non-metrics cells | Render `content` (notes text) as a plain paragraph + a `4/9` field-count badge |
| Metrics cells | Already render a custom scorecard tile via `formatMetricsScorecardMarkup` ✅ |
| Actor fields | Stored in `actor_fields` JSON on each cell but not surfaced in the matrix view |

The `formatMatrixCellMarkup` function in `journeyMatrixTabulatorHelpers.ts` is the single render entry point. It already branches on `actorType === 'metrics'`. This epic extends that branch pattern for every remaining actor type.

---

## Design Language

### Stakeholder / Human actor tiles (customer, internal)
Emotion badge at top → action text → optional bottom tag (Pain Point / Opportunity / Handoff)

### System / Data actor tiles (engineering, ai_agent, vendor, handoff)
Identity header → key data pair or flow line → optional bottom flag (Error / Failure / Escalation)

### Financial actor tile
Priority badge → dollar value pair → optional risk flag

### Metrics tile
Already built — Health score + metric dot rows ✅

### Fallback (operations, dev, custom, null actor type)
No change — keep current content text + field-count badge

---

## Emotion → Color Mapping (shared utility)

Used by customer and internal tiles. Parse `emotions` text with keyword matching:

| Keywords (case-insensitive) | Badge Color | Label |
|---|---|---|
| frustrated, anxious, confused, overwhelmed, concerned, worried | `#ef4444` red | text as-is |
| confident, happy, satisfied, excited, relieved, positive | `#22c55e` green | text as-is |
| neutral, passive, mild, moderate, uncertain (default) | `#f59e0b` yellow | text as-is |

Truncate emotion text to 18 chars in the badge.

## Financial Priority → Color Mapping

Parse `priority_score` text:

| Keyword | Badge Color |
|---|---|
| "high" | `#ef4444` red-orange |
| "medium" | `#f59e0b` yellow |
| "low" | `#22c55e` green |
| no match | `#a1a1aa` grey |

---

## Tile Designs Per Actor Type

### `customer`
```
[ 🟡 Neutral          ]   ← emotions field, color-coded pill
Entry: Receives order confirmation...  ← entry_trigger (2 lines max)
                  [ Pain Point ]       ← shown if friction_points filled
```
Fields used: `emotions`, `entry_trigger`, `friction_points`

### `internal`
```
[ Task: Match driver to order    ]   ← task_objective (1 line)
Tools: Algorithm + Driver App        ← tools_systems (1 line)
[ Pain Point ]  [ Handoff → ]        ← pain_points / handoff_dependencies
```
Fields used: `task_objective`, `tools_systems`, `pain_points`, `handoff_dependencies`

### `engineering`
```
[ System: Matching Service       ]   ← system_service_owner
In: Order data  →  Out: Driver ID    ← data_inputs → data_outputs
                  [ ⚠ Error States ] ← shown if error_states_edge_cases filled
```
Fields used: `system_service_owner`, `data_inputs`, `data_outputs`, `error_states_edge_cases`

### `ai_agent`
```
[ 🤖 GPT-4o                     ]   ← ai_model_agent
In: Order  →  Out: Match score       ← input_data → decision_output
Confidence: ≥85%  [ Escalates ]      ← confidence_threshold / escalation_logic
```
Fields used: `ai_model_agent`, `input_data`, `decision_output`, `confidence_threshold`, `escalation_logic`

### `financial`
```
[ 🔴 Priority: High              ]   ← priority_score, color-coded
Cost: $1.20   |   Risk: $4,800       ← cost_to_serve | revenue_at_risk
              [ ⚠ Revenue Leakage ]  ← shown if revenue_leakage filled
```
Fields used: `priority_score`, `cost_to_serve`, `revenue_at_risk`, `revenue_leakage`

### `vendor`
```
[ Vendor: Google Maps API        ]   ← vendor_name_type
Role: Route optimization             ← role_at_step
SLA: 99.9%   Cost: $0.02/call        ← sla_performance_metrics | cost_impact
```
Fields used: `vendor_name_type`, `role_at_step`, `sla_performance_metrics`, `cost_impact`, `failure_scenario`

### `handoff`
```
[ Trigger: Order confirmed       ]   ← trigger_event
Retail Partner  →  Driver            ← upstream_actor → downstream_actor
              [ ⚠ Failure Recovery ] ← shown if failure_recovery filled
```
Fields used: `trigger_event`, `upstream_actor`, `downstream_actor`, `failure_recovery`

### `metrics` — ✅ Already built (no change)

### `operations`, `dev`, `custom`, `null` — no tile, keep current text display

---

## Stories

### US-ICT-00 — Shared emotion color utility
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

Add exported function `resolveEmotionColor(emotions: string | null | undefined): { color: string; label: string }` using the keyword table above. Returns yellow/Neutral as default.

Add exported function `resolveFinancialPriorityColor(priorityScore: string | null | undefined): string` using priority keyword table. Returns grey as default.

**Acceptance Criteria:**
- `resolveEmotionColor('Frustrated — waiting too long')` returns `{ color: '#ef4444', label: 'Frustrated — waiting...' }` (truncated to 18 chars)
- `resolveEmotionColor('Confident')` returns `{ color: '#22c55e', label: 'Confident' }`
- `resolveEmotionColor(null)` returns `{ color: '#f59e0b', label: 'Neutral' }`
- `resolveFinancialPriorityColor('High — $7K/mo recoverable')` returns `'#ef4444'`
- `resolveFinancialPriorityColor(null)` returns `'#a1a1aa'`

---

### US-ICT-01 — Customer tile renderer
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

Add private function `formatCustomerTileMarkup(fields: CustomerActorFields): string`.

**Tile layout:**
1. Emotion badge pill — color from `resolveEmotionColor(fields.emotions)`, text is truncated emotion label
2. Action line — `fields.entry_trigger` truncated to 2 lines (CSS clamp), grey if missing
3. Bottom tag row — `Pain Point` tag (pink) if `fields.friction_points` is non-null/non-empty

**Acceptance Criteria:**
- Renders emotion badge with correct color when `emotions` is set
- Renders `entry_trigger` text below badge; shows `—` if empty
- Shows Pain Point tag only when `friction_points` has a value
- Returns empty-state string `👤 No data yet` when all three fields are null

---

### US-ICT-02 — Internal tile renderer
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

Add private function `formatInternalTileMarkup(fields: InternalActorFields): string`.

**Tile layout:**
1. Task line — `Task:` label + `fields.task_objective` (1 line clamp)
2. Tools line — `Tools:` label + `fields.tools_systems` (1 line clamp), omitted if empty
3. Bottom tag row — `Pain Point` (pink) if `pain_points` filled; `Handoff →` (blue) if `handoff_dependencies` filled

**Acceptance Criteria:**
- Tools line is omitted when `tools_systems` is null
- Both tags can appear simultaneously
- Returns empty-state string `🏢 No data yet` when all fields are null

---

### US-ICT-03 — Engineering tile renderer
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

Add private function `formatEngineeringTileMarkup(fields: EngineeringActorFields): string`.

**Tile layout:**
1. System line — `System:` label + `fields.system_service_owner` (1 line clamp)
2. Data flow line — `In:` + `fields.data_inputs` truncated + `→` + `fields.data_outputs` truncated; omitted if both empty
3. Bottom tag — `⚠ Error States` (orange) if `error_states_edge_cases` filled

**Acceptance Criteria:**
- Flow arrow line is omitted if both `data_inputs` and `data_outputs` are null
- Error tag appears only when `error_states_edge_cases` has a value
- Returns empty-state string `⚙️ No data yet` when all fields null

---

### US-ICT-04 — AI Agent tile renderer
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

Add private function `formatAiAgentTileMarkup(fields: AiAgentActorFields): string`.

**Tile layout:**
1. Model badge — `🤖` + `fields.ai_model_agent` (1 line, prominent)
2. Decision flow line — `In:` + `fields.input_data` truncated + `→` + `fields.decision_output` truncated
3. Confidence/Escalation line — `Confidence: {threshold}` + `Escalates` tag (purple) if `escalation_logic` filled

**Acceptance Criteria:**
- Model badge is omitted if `ai_model_agent` is null, falls back to `🤖 AI Agent`
- Decision flow line omitted if both `input_data` and `decision_output` are null
- Escalates tag appears only when `escalation_logic` is non-empty
- Returns empty-state string `🤖 No data yet` when all fields null

---

### US-ICT-05 — Financial tile renderer
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

Add private function `formatFinancialTileMarkup(fields: FinancialActorFields): string`.

**Tile layout:**
1. Priority badge — `Priority:` + `fields.priority_score` truncated, color from `resolveFinancialPriorityColor`
2. Cost/Risk row — `Cost: {cost_to_serve}` | `Risk: {revenue_at_risk}` (omit each if null)
3. Bottom flag — `⚠ Revenue Leakage` (red) if `revenue_leakage` filled

**Acceptance Criteria:**
- Priority badge color matches resolved color from priority_score text
- Cost and Risk labels are omitted independently if their fields are null
- Revenue leakage flag appears only when `revenue_leakage` has a value
- Returns empty-state string `💰 No data yet` when all fields null

---

### US-ICT-06 — Vendor tile renderer
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

Add private function `formatVendorTileMarkup(fields: VendorActorFields): string`.

**Tile layout:**
1. Vendor header — `Vendor:` + `fields.vendor_name_type` (1 line)
2. Role line — `Role:` + `fields.role_at_step` (1 line), omitted if empty
3. SLA/Cost line — `SLA: {sla_performance_metrics}` | `Cost: {cost_impact}`, each omitted if null
4. Bottom flag — `⚠ Failure Risk` (orange) if `failure_scenario` filled

**Acceptance Criteria:**
- All four data lines are independently optional
- Failure flag appears only when `failure_scenario` is non-empty
- Returns empty-state string `🤝 No data yet` when all fields null

---

### US-ICT-07 — Handoff tile renderer
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

Add private function `formatHandoffTileMarkup(fields: HandoffActorFields): string`.

**Tile layout:**
1. Trigger line — `Trigger:` + `fields.trigger_event` (1 line)
2. Flow line — `fields.upstream_actor` + `→` + `fields.downstream_actor`, each omitted if null
3. Bottom flag — `⚠ Failure Recovery` (orange) if `failure_recovery` filled

**Acceptance Criteria:**
- Arrow flow line is omitted if both upstream and downstream are null
- If only one side is present, renders as `→ {downstream}` or `{upstream} →`
- Returns empty-state string `⇄ No data yet` when all fields null

---

### US-ICT-08 — Wire tile renderers into `formatMatrixCellMarkup`
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

Extend the `actorType` branch in `formatMatrixCellMarkup` to call the new tile formatters when `meta?.actorFields` is present:

```
metrics   → formatMetricsScorecardMarkup   (existing)
customer  → formatCustomerTileMarkup
internal  → formatInternalTileMarkup
engineering → formatEngineeringTileMarkup
ai_agent  → formatAiAgentTileMarkup
financial → formatFinancialTileMarkup
vendor    → formatVendorTileMarkup
handoff   → formatHandoffTileMarkup
operations, dev, custom, null → existing content text + badge (no change)
```

Each branch wraps the tile output in the same `jm-grid-cell` shell already used by metrics, preserving `selectedClass`, `cellIdAttribute`, `indicator`, and `linkIndicator`.

**Acceptance Criteria:**
- Each supported actor type renders its tile when `actorFields` is present and non-null
- If `actorFields` is null or empty for a typed row, renders the empty-state string from the respective formatter
- Fallback actor types still render content text + field-count badge unchanged
- Import statements updated to include all new actor field interfaces from `types.ts`

---

### US-ICT-09 — CSS tile component styles
**File:** `webapp/protype-2/src/index.css`

Add CSS classes used by the tile renderers:

| Class | Purpose |
|---|---|
| `.jm-tile-emotion-badge` | Emotion pill — rounded, colored background, white text, 10px font |
| `.jm-tile-header` | Bold 1-line header row (model name, vendor, system) |
| `.jm-tile-body` | Secondary text line — grey, 10px, 1-line clamp |
| `.jm-tile-flow` | Data flow line — In → Out, monospace arrows, 10px |
| `.jm-tile-tags` | Bottom tag row — flex, gap 4px |
| `.jm-tile-tag` | Individual tag pill — 9px, rounded, colored by variant |
| `.jm-tile-tag.pain` | Pink background `#fce7f3` / `#be185d` text |
| `.jm-tile-tag.opportunity` | Blue background `#e0f2fe` / `#0369a1` text |
| `.jm-tile-tag.handoff` | Blue-grey background / blue text |
| `.jm-tile-tag.error` | Orange background `#ffedd5` / `#c2410c` text |
| `.jm-tile-tag.escalation` | Purple background `#ede9fe` / `#7c3aed` text |
| `.jm-tile-tag.risk` | Red background `#fee2e2` / `#dc2626` text |
| `.jm-tile-empty` | Empty state — grey italic 10px |

**Acceptance Criteria:**
- All tag variants have sufficient color contrast (WCAG AA)
- Tiles remain contained within the cell card — no overflow outside `.jm-grid-cell`
- Styles don't conflict with existing `.jm-metrics-*` or `.jm-actor-badge` classes

---

### US-ICT-10 — Tests
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.test.ts`

Add test cases:

- `resolveEmotionColor` — frustrated → red, confident → green, null → yellow default
- `resolveFinancialPriorityColor` — high → red, null → grey
- `formatCustomerTileMarkup` — emotion badge rendered, pain point tag present/absent, empty state
- `formatInternalTileMarkup` — task line, tools omitted when null, both tags independently
- `formatEngineeringTileMarkup` — flow line omitted when both inputs null, error tag
- `formatAiAgentTileMarkup` — model fallback, escalation tag, empty state
- `formatFinancialTileMarkup` — priority color applied, leakage flag, cost/risk independently optional
- `formatVendorTileMarkup` — failure flag, SLA/cost optional
- `formatHandoffTileMarkup` — partial flow (upstream only), failure flag
- `formatMatrixCellMarkup` with `actorType: 'customer'` + actorFields — delegates to customer tile
- `formatMatrixCellMarkup` with `actorType: 'operations'` — falls through to content text unchanged

**Acceptance Criteria:**
- All new tests pass
- Existing tests remain green — no regressions on metrics scorecard, lens cell, or base cell markup
