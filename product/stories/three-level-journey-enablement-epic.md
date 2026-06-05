# Three-Level Journey Map — Enablement Epic

**Status:** Ready for Development
**Goal:** Make L1 Architecture, L2 Actor Journey, and L3 Atomic maps feel intentional and
distinct — with AI-guided prescription, level-specific build protocols, parent-child navigation
in the UI, revenue-at-risk fields, and a leakage results panel.

---

## Context: What's Done vs What's Missing

| Capability | Status |
|---|---|
| `map_level` field on DB + API | ✅ Done |
| Level badge + picker on create | ✅ Done |
| Ring 2 fields in UI (cost rate, time duration, measurement) | ✅ Done |
| Xano API allowlist fix | ✅ Done |
| `calculate_leakage` MCP tool | ✅ Done |
| AI prescription interview (L1/L2/L3 decision) | ✅ Done |
| Level-specific AI build protocols | ✅ Done |
| L1→L2→L3 navigation UI | ❌ Missing |
| Revenue at risk fields (avg deal value, miss rate) | ❌ Missing |
| Leakage results display in UI | ❌ Missing |
| Plan vs Actual fields | ❌ Missing |

---

## Epic TL-1 — AI Level Prescription Interview

**Owner:** Journey Map Assistant (system prompt)
**Trigger:** Any build request or [GREET] on an empty map with no `map_level` set

The AI must determine the correct map level through conversation — never by asking
"what map level do you want?"

### US-TL-01 — Domain + actor identification
**AI asks (in order):**
1. "What type of business or operation are we mapping? What does it try to deliver?"
   → writes `journey_scope`
2. "Who is the person or system that does the actual work we want to understand?"
   → writes `primary_actor`

### US-TL-02 — Scope gate (L1 vs L2/L3)
**AI asks:**
> "Are you trying to understand the overall business flow, or one specific person's process?"
- Overall → prescribe L1, set `map_level = "architecture"`
- Specific actor → continue to granularity check

### US-TL-03 — Granularity gate (L2 vs L3)
**AI asks:**
> "Do you want [actor]'s end-to-end process, or zoom into one specific task they perform?"
- End-to-end → prescribe L2, set `map_level = "actor-journey"`
- One task → prescribe L3, set `map_level = "atomic"`

### US-TL-04 — Insight goal override (force L3)
**AI asks:**
> "Do you need to find where time or money is being lost, or is this for documentation?"
- Leakage/cost → force L3 regardless of prior answers
- Documentation → L1 or L2 is sufficient

**Acceptance Criteria:**
- `map_level` always set before first stage is created
- AI never asks "what map level do you want?"
- Prescription resolves in ≤ 3 questions
- Null `map_level` on existing map triggers prescription before any build operation

---

## Epic TL-2 — Level-Specific AI Build Protocols

### US-TL-05 — L1 Architecture build protocol
**Trigger:** `map_level = "architecture"` prescribed
**AI collects:** domain description, top-level processes (→ stages), actors involved (→ lenses)
**AI does NOT collect:** measurement fields, cost rates, time durations
**AI writes:** description cells only — narrative context per stage
**At end of build:** offers to create an L2 drill-down for each major actor identified

### US-TL-06 — L2 Actor Journey build protocol
**Trigger:** `map_level = "actor-journey"` prescribed
**AI collects:** actor identity (persona, goal, constraints), stage sequence, `cost_rate_value`
**Per stage:** time duration, actor experience (emotions, friction), pain points
**AI does NOT collect:** `measurement_frequency`, `miss_rate`, `planned_duration`
**At end of build:** offers to create an L3 for any stage where "I want to measure this"

### US-TL-07 — L3 Atomic build protocol + Guard Rail Tests
**Trigger:** `map_level = "atomic"` prescribed
**Before stage collection:** collect Ring 2 map-level fields in order:
1. `measurement_frequency` — "How many times per year does this process run?"
2. `measurement_period_label` — "What's a label for one instance? e.g. 'per job'"
3. `average_deal_value` — "What's one successful outcome worth in revenue?"
4. `miss_rate` — "What % of those go unanswered or mishandled?"

**Per stage — 5 Guard Rail Tests (silent, run before writing each stage):**

| Test | Check | Fail action |
|---|---|---|
| Single Actor | One owner for this stage's output? | Split stage or link sub-journey |
| Time-on-Site | Can user give a real-world time? | Stage too vague — ask to narrow |
| Completion Signal | What signals this step is done? | Require `stage_goal` before proceeding |
| Exception | What happens when this goes wrong? | Flag for exception map |
| Isolation | Can this step produce a result alone? | Needs sub-journey |

**Per stage — after Guard Rails pass:**
- Collect `time_duration_value` + unit — "How long does [actor] spend on '[stage]'?"
- Collect `planned_duration` — "How long should it ideally take?"
- Collect leakage metric — "What's the main thing that goes wrong here?"
  → writes to `actor_fields.metrics[]` with `flag: "leakage"`

**At end of build:**
- Run leakage-ready check per stage (all Ring 2 fields present?)
- Call `calculate_leakage` and surface the 3-year cost-of-inaction in closing message

**Acceptance Criteria:**
- L1 never prompts for cost or time fields
- L2 collects cost rate but not measurement_frequency or miss_rate
- L3 collects all Ring 2 fields; every stage passes 5 Guard Rail Tests
- `calculate_leakage` always called at end of L3 build

---

## Epic TL-3 — L1→L2→L3 Navigation UI

**Surface:** Dashboard, ArchitectureDetail, map editor
**Rule:** L1 links → L2 via `sub_journey`. L2 links → L3 via `sub_journey`.

### US-TL-08 — Parent map breadcrumb in map editor
**Where:** top of the map editor header
**Shows:** "↑ [Parent Map Title]" when `parent_map_id` is set
**Action:** clicking navigates to the parent map
**API:** read `parent_map_id` from the map bundle; fetch title via `get_map`

### US-TL-09 — Child maps panel on stage
**Where:** stage edit panel (StageEditPanel.tsx) — new "Linked Maps" section
**Shows:** any `sub_journey` links from this stage's cells
**Action:** "Create drill-down map" button → opens create dialog pre-set to next level down
  (L1 stage → creates L2; L2 stage → creates L3)
**API:** call `link_map` with `sub_journey` after creation; set `parent_map_id` on new map

### US-TL-10 — Child map count badge on stage header
**Where:** stage column header in the map grid
**Shows:** small link icon + count if any sub-journey links exist on this stage's cells
**Click:** opens the linked maps panel / navigates to child

### US-TL-11 — Architecture overview tile — child map count
**Where:** Dashboard map tiles and ArchitectureDetail
**Shows:** "3 actor journeys" below L1 tile; "2 atomic maps" below L2 tile
**API:** filter `list_maps` by `parent_map_id` to count children

**Acceptance Criteria:**
- Every L3 map shows its L2 parent in the breadcrumb
- Clicking "Create drill-down" pre-fills map level and sets `parent_map_id`
- Stage headers with linked children show a visible indicator
- Navigation is traversable without the AI

---

## Epic TL-4 — Revenue at Risk Fields

**Why:** labor cost opens the conversation; revenue gap closes the deal.

### US-TL-12 — Add `average_deal_value`, `miss_rate`, `conversion_rate` to DB
**File:** `tables/6_journey_map.xs`
**Fields:**
- `decimal average_deal_value?` — average revenue per successful event (e.g. 350.00)
- `decimal miss_rate?` — % of events mishandled (0.0–1.0, e.g. 0.40)
- `decimal conversion_rate?` — % of engaged prospects that convert (0.0–1.0, e.g. 0.35)

### US-TL-13 — Expose via journey settings PATCH endpoint
**File:** `apis/journey_map/62_journey_map_settings_journey_map_id_PATCH.xs`
**Add to `input` block and `$allowed_fields`:** `average_deal_value`, `miss_rate`, `conversion_rate`

### US-TL-14 — Expose via `update_journey_settings` MCP tool
**File:** `tools/14_update_journey_settings.xs`
**Add to input schema:** all three fields

### US-TL-15 — Revenue at risk fields in Map Settings UI (L3 only)
**File:** `webapp/protype-2/src/App.tsx` — settings sidebar
**Add below existing L3 leakage section:**
- `average_deal_value` — currency number input
- `miss_rate` — percentage input (0–100%, stored as 0.0–1.0)
- `conversion_rate` — percentage input (optional)

**Acceptance Criteria:**
- Fields writable via PATCH, MCP tool, and UI
- Returned in journey map load bundle
- Only visible in settings panel for `map_level = "atomic"` maps
- `calculate_leakage` returns `revenue_at_risk_annual` + `3yr_revenue_gap` when present

---

## Epic TL-5 — Leakage Results UI Panel

**Why:** the 3-year number should be visible on the map — not buried in chat.

### US-TL-16 — Leakage summary panel in map editor
**Where:** right sidebar or floating panel (toggle button in map toolbar)
**Shows when:** `map_level = "atomic"` + at least one cell has `time_duration_value` set
**Contents:**
```
Cost per event:        $80.00
Monthly cost:          $1,386
Annual cost:           $16,640
3-Year cost of inaction: $49,920

Revenue at risk (annual): $145,600   ← only shown when miss_rate + avg_deal_value set
3-Year revenue gap:       $436,800
```
**Refresh:** recalculates on every cell save (debounced 2s)
**API:** calls `calculate_leakage` endpoint (or MCP tool equivalent)

### US-TL-17 — Per-stage leakage breakdown in stage edit panel
**Where:** StageEditPanel.tsx — collapsed section at bottom
**Shows:** cost per event for this stage and its % of total map leakage
**Only shown when:** stage has primary actor with `cost_rate_value` + cell has `time_duration_value`

### US-TL-18 — Incomplete fields callout
**Where:** leakage panel
**Shows when:** `incomplete_cells[]` returned by `calculate_leakage`
**Content:** "3 stages missing time duration — leakage total is partial"
**Action:** clicking a stage label in the list opens that stage's edit panel

**Acceptance Criteria:**
- Panel only visible on L3 atomic maps
- 3-year number is always the most prominent figure
- Incomplete fields callout prevents false confidence in partial numbers
- Panel does not appear on L1 or L2 maps

---

## Epic TL-6 — Plan vs Actual Fields (LA-6a)

**Why:** the gap between planned and actual is the leakage signal in Phase 1 discovery.

### US-TL-19 — Add `planned_duration` + `actual_duration` to journey_cell
**File:** `tables/9_journey_cell.xs`
- `decimal planned_duration?` — what the blueprint says this stage should take
- `decimal actual_duration?` — what the prospect says actually happens today

### US-TL-20 — Expose via cell update endpoint
**File:** `apis/journey_map/44_journey_cell_update_journey_cell_id_PATCH.xs`
Add both fields to `input` block, `$allowed_fields` (or `pick` pattern), and `response`

### US-TL-21 — Expose via MCP tools
**Files:** `tools/3_update_cell.xs`, `tools/51_fill_cells.xs`
Add both fields to input schemas

### US-TL-22 — Plan vs Actual inputs in Stage Edit Panel
**File:** `webapp/protype-2/src/StageEditPanel.tsx`
**Add below "Time on Task" section (L3 only):**
- `planned_duration` — "Planned time" number + unit (mirrors time_duration_value default)
- `actual_duration` — "Actual time (what really happens)" number + unit
**Shows gap:** if both are set, display "Gap: +X min" in amber when actual > planned

**Acceptance Criteria:**
- Both fields nullable — no breaking change to existing maps
- Gap calculation visible inline when both values are present
- `calculate_leakage` uses `actual_duration` gap cost when both values present

---

## Build Order

```
TL-1   AI Level Prescription         (AI prompt — no DB changes)
TL-2   Level Build Protocols         (AI prompt — depends on TL-1)
TL-4   Revenue at Risk Fields        (DB + API + UI — independent)
TL-6   Plan vs Actual Fields         (DB + API + UI — independent)
TL-3   Navigation UI                 (frontend — depends on existing link_map tool)
TL-5   Leakage Results Panel         (frontend — depends on TL-4 + TL-6 for full numbers)
```

---

## Relationship to Other Epics

| Epic | Relationship |
|---|---|
| `leakage-analysis-epic.md` | TL-4 + TL-6 complete LA-7 and LA-6a |
| `journey-map-level-architecture-epic.md` | TL-1 + TL-2 implement JMA-1 through JMA-3 |
| `xano-api-field-allowlist-fix-epic.md` | Prerequisite — must be pushed before TL-4/TL-6 |
| `atomic-map-ui-fields-epic.md` | Prerequisite — Ring 2 UI fields must exist before TL-5 |
