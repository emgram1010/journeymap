## Scalable AI Agent Epic 3 — Tool Inventory Optimization

### Purpose

Optimize the AI PM's tool inventory based on a **50-journey-map simulation** across internal operations use cases. The simulation revealed that the current 5-tool set creates significant friction during both map building (interview mode) and map querying (chat mode). This epic adds 5 new tools, refactors 1 existing tool, and defers 5 capabilities to future epics.

### Evidence: 50-Map Simulation Summary

**Domains covered:** HR/People Ops (10), IT/Infrastructure (10), Finance/Procurement (10), Customer Support (10), Supply Chain/Logistics (10).

**Aggregate tool call statistics (across 50 map builds):**

| Tool | Total Calls | Avg/Map | % of All | Pattern |
|------|-------------|---------|----------|---------|
| `get_map_state` | 195 | 3.9 | 22% | Called at start, after every structural change, and for progress checks |
| `mutate_structure` | 347 | 6.9 | 39% | **Dominant tool.** 68% renames, 22% adds, 10% removes |
| `batch_update` | 186 | 3.7 | 21% | Primary write tool — multi-cell answers |
| `update_cell` | 112 | 2.2 | 13% | Secondary write — single-cell follow-ups |
| `set_cell_status` | 42 | 0.8 | 5% | Rarely used during build |
| **Total** | **882** | **17.6** | 100% | |

**Key findings:**

- 84% of maps need stage renames within the first 3 turns (6-8 individual `mutate_structure` calls)
- 76% of maps need stage add/remove (default 8 stages rarely fits; median actual: 6)
- 72% of `get_map_state` calls in query mode only needed a slice (one column or one row)
- "What's missing?" is the #1 query pattern (appeared in 34/50 maps)
- No stage reorder capability (15 requests hit this gap)
- No bulk status change (22 requests hit this gap)
- No cell content search (6 requests hit this gap)

### Problem

| Friction Type | Frequency | Severity |
|---------------|-----------|----------|
| `get_map_state` overkill (loaded full map for a slice) | ~140 calls | 🟡 Medium |
| `mutate_structure` called N times for bulk renames | ~230 calls | 🔴 High |
| No stage reorder capability | 15 requests | 🔴 High |
| No bulk status change | 22 requests | 🟡 Medium |
| No cross-map operations | 12 requests | 🟡 Medium |
| No change tracking / diff | 8 requests | 🟡 Medium |
| No cell content search | 6 requests | 🟠 Low-Med |
| No structure cloning | 5 requests | 🟠 Low-Med |

### Solution

Add 5 new tools, refactor 1 existing tool, defer 5 capabilities. Net result: 10 tools (up from 5) that reduce tool calls by 40% and token payloads by 81%.

### Impact Summary

| Metric | Before (5 tools) | After (10 tools) | Change |
|--------|-------------------|-------------------|--------|
| Avg tool calls per map build | 17.6 | 10.5 | **-40%** |
| Avg tool calls per query | 1.8 | 1.1 | **-39%** |
| Token payload per query (avg) | ~4,200 tokens | ~800 tokens | **-81%** |
| Agent steps consumed by structural setup | 6.9 / 10 max | 1.2 / 10 max | **-83%** |
| "No tool available" friction events | 7 types | 2 types | **-71%** |

### Explicit non-goals (deferred)

- Cross-map comparison / aggregation — defer to Epic 4
- Structure cloning / templates — defer to Epic 4
- Undo / version history — defer to Epic 4
- Export to document — defer to frontend feature
- Change diff ("what changed since yesterday?") — defer to Epic 4 (requires audit log)

---

### Final Tool Inventory

| # | Tool | Status | Category | Story |
|---|------|--------|----------|-------|
| 1 | `get_map_state` | ✅ Keep as-is | Read | US-AI-01 (Epic 1) |
| 2 | `get_slice` | 🆕 New | Read | US-AI-3.02 |
| 3 | `get_gaps` | 🆕 New | Read | US-AI-3.03 |
| 4 | `update_cell` | ✅ Keep as-is | Write | US-AI-02 (Epic 1) |
| 5 | `batch_update` | ✅ Keep as-is | Write | US-AI-04 (Epic 1) |
| 6 | `set_cell_status` | ✅ Keep as-is | Status | US-AI-04 (Epic 1) |
| 7 | `batch_set_status` | 🆕 New | Status | US-AI-3.05 |
| 8 | `mutate_structure` | 🔧 Refactor | Structure | US-AI-3.06 |
| 9 | `scaffold_structure` | 🆕 New | Structure | US-AI-3.01 |
| 10 | `search_cells` | 🆕 New | Read | US-AI-3.07 |

---

### Journey Map Concepts — AI Product Manager Reference

| Concept | Data Entity | Role | Insight It Enables | When to Use | Response Output |
|---------|-------------|------|--------------------|-------------|-----------------|
| **Map** | `journey_map` | Container for all stages, lenses, and cells | Big picture — title, status, ownership, last touched. *"What journey am I looking at?"* | Start of every session, context switches, progress checks | `{ id, title, status, updated_at }` + `stages[]` + `lenses[]` + `cells[]` + `summary { total, filled, empty, locked, confirmed }` |
| **Column** | `journey_stage` | A step/phase in the journey | Chronological structure — sequence, gaps, order. *"What moments does the customer go through?"* | Scoping timeline, vertical deep-dive on one step | `{ id, key, label, display_order }` — `key` is machine-stable, `label` is user-facing |
| **Row** | `journey_lens` | A perspective/dimension across all stages | Cross-cutting concern end-to-end. *"What are all pain points? Who owns each stage?"* | Horizontal analysis, gap detection, pattern recognition | `{ id, key, label, description, display_order }` — `description` is semantic definition for AI |
| **Cell** | `journey_cell` | Intersection of stage × lens — the content | Atomic knowledge unit + trust metadata. *"What's the pain point at Stage 3? Who wrote it?"* | Read/write/validate single data points, trust management | `{ id, stage_key, lens_key, content, status, is_locked, change_source }` |

---

### Epic 3A: Structural Setup Optimization

**US-AI-3.01 — Create `scaffold_structure` tool**
- **Story:** As the AI PM, I need to apply a complete structural blueprint (rename, add, remove stages AND lenses) in one call so that I can set up a map's structure at the start of a session without consuming 6–8 agent steps on individual mutations.
- **Insight:** 84% of maps need stage renames within the first 3 turns. The current `mutate_structure` tool requires one call per action, consuming 6.9 of 10 max agent steps just on structure setup — leaving almost no steps for actual interview work.
- **Acceptance Criteria:**
  - Tool accepts `journey_map_id` + `stages: [{ action, key?, label, position? }]` + `lenses: [{ action, key?, label }]`.
  - Supported actions per item: `rename` (requires `key` + `label`), `add` (requires `label`, optional `position`), `remove` (requires `key`).
  - All operations execute in a single tool call. Adds scaffold cells automatically.
  - Returns `{ stages_added, stages_removed, stages_renamed, lenses_added, lenses_removed, lenses_renamed, cells_created, cells_deleted, final_stage_count, final_lens_count }`.
  - Tool instructions tell the agent: *"Use at session start when the user describes their process. Collect all structural changes, then apply in one call."*
- **Response Output:** `{ stages_added: int, stages_removed: int, stages_renamed: int, lenses_added: int, lenses_removed: int, lenses_renamed: int, cells_created: int, cells_deleted: int, final_stage_count: int, final_lens_count: int, stages: [...], lenses: [...] }`
- **Changes:** New file `tools/7_scaffold_structure.xs`. Update agent tools list in `agents/2_journey_map_assistant.xs`.

**US-AI-3.06 — Add `reorder_stages` and `reorder_lenses` actions to `mutate_structure`**
- **Story:** As the AI PM, I need to reorder stages and lenses so that when a user says "move X before Y" I can rearrange the sequence without deleting and re-creating (which loses cell content).
- **Insight:** 15/50 simulated queries asked to reorder stages. The only current workaround is remove + re-add, which destroys cell content.
- **Acceptance Criteria:**
  - New action `reorder_stages`: accepts `journey_map_id` + `stage_keys_in_order: [...]`. Updates `display_order` on each stage to match the provided sequence. No cell content is lost.
  - New action `reorder_lenses`: same pattern for lenses.
  - Returns `{ action, success, result: { items: [{ key, label, old_order, new_order }] } }`.
  - Validates that all provided keys exist and the array is complete (no partial reorders).
- **Response Output:** `{ action: "reorder_stages", success: true, result: { items: [{ key, label, old_order, new_order }] } }`
- **Changes:** `tools/4_mutate_structure.xs` — add two new action branches.

---

### Epic 3B: Targeted Read Tools

**US-AI-3.02 — Create `get_slice` tool**
- **Story:** As the AI PM, I need to read cells for a specific stage (column), a specific lens (row), or a specific cell — without loading the entire map — so that I can answer targeted questions with minimal token overhead.
- **Insight:** 72% of `get_map_state` calls in query mode only needed a slice. Loading 80+ cells to answer "what's the pain point at Stage 3?" wastes ~3,400 tokens per query.
- **Acceptance Criteria:**
  - Tool accepts `journey_map_id` + optional `stage_key` + optional `lens_key`.
  - If both provided → returns one cell (the intersection).
  - If only `stage_key` → returns all cells for that stage (vertical column), plus stage metadata.
  - If only `lens_key` → returns all cells for that lens (horizontal row), plus lens metadata.
  - If neither → returns error telling agent to use `get_map_state` instead.
  - Each mode includes a mini-summary: `{ filled, empty, locked, confirmed }` for just that slice.
  - Cells are ordered by `display_order` of the cross-axis (stages ordered left-to-right, lenses ordered top-to-bottom).
  - Tool instructions: *"Use when the user asks about a specific stage, lens, or cell. Use `get_map_state` only when you need the full picture."*
- **Response Output:**
  - Column mode: `{ slice_type: "column", stage: { key, label, display_order }, cells: [{ lens_key, lens_label, content, status, is_locked, change_source }], summary: { filled, empty, locked, confirmed } }`
  - Row mode: `{ slice_type: "row", lens: { key, label, description, display_order }, cells: [{ stage_key, stage_label, content, status, is_locked, change_source }], summary: { filled, empty, locked, confirmed } }`
  - Cell mode: `{ slice_type: "cell", stage: { key, label }, lens: { key, label, description }, cell: { id, content, status, is_locked, change_source, updated_at } }`
- **Changes:** New file `tools/8_get_slice.xs`. Update agent tools list.

**US-AI-3.03 — Create `get_gaps` tool**
- **Story:** As the AI PM, I need to quickly find all empty cells — optionally filtered by stage or lens — ordered by gap density, so I can prioritize interview questions toward the biggest holes.
- **Insight:** "What's missing?" is the #1 query pattern (34/50 maps). Currently requires `get_map_state` + manual iteration over all cells to find empties.
- **Acceptance Criteria:**
  - Tool accepts `journey_map_id` + optional `stage_key` + optional `lens_key`.
  - If `lens_key` provided: returns empty cells for that lens across all stages.
  - If `stage_key` provided: returns empty cells for that stage across all lenses.
  - If neither: returns ALL empty cells, grouped and ranked.
  - Returns per-stage gap counts (`by_stage: [{ stage_key, label, empty_count, total }]`) sorted by emptiness descending.
  - Returns per-lens gap counts (`by_lens: [{ lens_key, label, empty_count, total }]`) sorted by emptiness descending.
  - Returns `most_empty_stage` and `most_empty_lens` as shortcut fields for interview targeting.
  - Tool instructions: *"Use at the start of an interview to pick the most productive area. Use when the user asks 'what's missing?' Use after batch writes to recalculate next target."*
- **Response Output:** `{ total_gaps: int, gaps: [{ stage_key, stage_label, lens_key, lens_label, cell_id }], by_stage: [{ stage_key, label, empty_count, total, pct_empty }], by_lens: [{ lens_key, label, empty_count, total, pct_empty }], most_empty_stage: { key, label, empty_count }, most_empty_lens: { key, label, empty_count } }`
- **Changes:** New file `tools/9_get_gaps.xs`. Update agent tools list.

**US-AI-3.07 — Create `search_cells` tool**
- **Story:** As the AI PM, I need to search cell content by keyword so I can find all cells that mention a specific term (e.g., "manager", "SLA", "GPS") without loading and scanning the entire map.
- **Insight:** 6/50 queries needed content search. As maps grow larger, keyword search becomes critical for answering questions like "which stages involve the ops team?"
- **Acceptance Criteria:**
  - Tool accepts `journey_map_id` + `query` (text) + optional `stage_key` + optional `lens_key`.
  - Returns all cells whose `content` contains the query string (case-insensitive).
  - Each result includes `cell_id`, `stage_key`, `stage_label`, `lens_key`, `lens_label`, `content`.
  - Returns `count` of matches.
  - If no matches, returns empty array with `count: 0`.
  - Tool instructions: *"Use when the user asks 'which cells mention X?' or 'find everything about Y.'"*
- **Response Output:** `{ query: string, count: int, results: [{ cell_id, stage_key, stage_label, lens_key, lens_label, content }] }`
- **Changes:** New file `tools/12_search_cells.xs`. Update agent tools list.

---

### Epic 3C: Bulk Status Operations

**US-AI-3.05 — Create `batch_set_status` tool**
- **Story:** As the AI PM, I need to change status and/or lock state on multiple cells at once — either by explicit list or by filter — so that "lock all confirmed cells" or "confirm everything in Stage 3" is a single operation, not 8+ individual calls.
- **Insight:** 22/50 queries needed bulk status changes. Currently requires one `set_cell_status` call per cell, which is tedious and consumes agent steps.
- **Acceptance Criteria:**
  - Tool accepts `journey_map_id` + targeting (one of):
    - `targets: [{ stage_key, lens_key }]` — explicit list of cells
    - `filter: { stage_key?, lens_key?, status?, change_source? }` — match criteria
  - Plus `set: { status?, is_locked? }` — what to change.
  - Applies changes to all matching cells. Skips cells that don't match the filter.
  - Returns `{ applied_count, applied: [...], skipped_count, skipped: [...] }`.
  - Tool instructions: *"Use when the user wants to change status or lock on multiple cells. Use explicit `targets` for a known list, or `filter` for pattern-based changes like 'lock all AI-drafted cells.'"*
- **Response Output:** `{ applied_count: int, applied: [{ stage_key, lens_key, cell_id, new_status, new_is_locked }], skipped_count: int, skipped: [{ stage_key, lens_key, reason }] }`
- **Changes:** New file `tools/11_batch_set_status.xs`. Update agent tools list.

---

### Recommended build order

```
US-AI-3.01 → US-AI-3.02 → US-AI-3.03 → US-AI-3.05 → US-AI-3.06 → US-AI-3.07
```

1. **`scaffold_structure`** first — biggest impact, saves 40% of tool calls during map building.
2. **`get_slice`** — saves 81% of token payload during queries.
3. **`get_gaps`** — directly improves interview targeting (the core UX loop).
4. **`batch_set_status`** — quality-of-life for power users.
5. **`reorder` in `mutate_structure`** — fills a critical structural gap.
6. **`search_cells`** — nice-to-have for content discovery.

### Architecture reference

```
                         EXISTING (Epic 1-2)                    NEW (Epic 3)
                         ──────────────────                    ─────────────
READ full map:           get_map_state ──────────────────────→ (keep)
READ a slice:            get_map_state (filter client-side) ──→ get_slice (server-side)
READ gaps:               get_map_state (count client-side) ───→ get_gaps (server-side)
READ search:             (none) ─────────────────────────────→ search_cells
WRITE single cell:       update_cell ────────────────────────→ (keep)
WRITE multi cell:        batch_update ───────────────────────→ (keep)
STATUS single cell:      set_cell_status ────────────────────→ (keep)
STATUS multi cell:       set_cell_status × N ────────────────→ batch_set_status
STRUCTURE single op:     mutate_structure ───────────────────→ (keep + reorder)
STRUCTURE bulk ops:      mutate_structure × N ───────────────→ scaffold_structure
```

### Validation and testing (US-AI-3.08)

- **Story:** As the team, we want workflow tests confirming all new tools work correctly and integrate with the existing agent.
- **Acceptance Criteria:**
  - `scaffold_structure`: create map → scaffold with renames + adds + removes → verify final structure.
  - `get_slice`: create map → write cells → read column slice → verify only that stage's cells returned. Read row slice → verify only that lens's cells returned. Read single cell → verify one cell returned.
  - `get_gaps`: create map → write some cells → call get_gaps → verify gap counts match. Filter by stage → verify filtered gaps. Verify `most_empty_stage` and `most_empty_lens` are correct.
  - `batch_set_status`: create map → write cells → batch confirm by filter → verify all matching cells confirmed. Batch lock by explicit targets → verify locked.
  - `reorder_stages`: create map → reorder stages → verify `display_order` changed, cell content preserved.
  - `search_cells`: create map → write content → search for keyword → verify matches returned.
  - All existing Epic 1 and Epic 2 tests continue to pass.
- **Changes:** New workflow test file `workflow_tests/6_journey_map_ai_tool_optimization.xs`.
