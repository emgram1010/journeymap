# Google Sheets JSON Export — Multi-Map & Child Connections (v2)

**Epic ID:** GSE-2
**Status:** Vision / Backlog
**Depends on:** GSE-1 (MVP), EXP-1 (linked graph walker)
**Goal:** Extend the Sheets export so a single click on a root map produces one Google Sheets workbook with every reachable child / sub / exception / anti-journey / ai-agent-manual map as its own sheet, plus a relationships index, so business reviewers can navigate the full architecture without opening the app.

---

## Context

GSE-1 ships a per-map single-sheet export. Real journey work is multi-map: an L1 architecture invokes L2 actor journeys; an L3 atomic map points to recovery / anti-journey paths via `journey_link`; ai_agent lenses delegate to operating-manual maps via `agent_map_id`.

EXP-1 already solved the traversal (`fetchLinkedGraph`, `linkedGraphClient`, `linkedGraphBudget`). GSE-2 reuses that graph and emits a Sheets-flavoured workbook payload instead of Markdown.

## Existing Architecture to Reuse

- `static/src/linkedGraphClient.ts::fetchLinkedGraph` — owner-scoped BFS hydrated graph.
- `static/src/linkedGraphBudget.ts::computeWordBudget` — re-scale for cell-char limits.
- `static/src/exportLinkedSkillBundle.ts::filterGraph` — same traversal-mode picker.
- `static/src/LinkedSkillExportDialog.tsx` — same picker UI shell.
- `apis/journey_map/76_journey_map_root_map_id_export_linked_graph_GET.xs` — no change.

## Non-Goals

- No Google Sheets API integration (still paste-to-Apps-Script).
- No cross-architecture traversal.
- No live sync / incremental updates.

## Output Contract

One JSON payload per export:

```json
{
  "version": "gse-2",
  "root_map_id": 176,
  "sheets": [
    { "name": "01-Party Rentals Baseline", "rows": [ /* GSE-1 row shape */ ] },
    { "name": "02-Driver Manual",          "rows": [ /* … */ ] },
    { "name": "_Links",                    "rows": [ /* link graph */ ] },
    { "name": "_Maps",                     "rows": [ /* map metadata */ ] }
  ]
}
```

Apps Script iterates `sheets[]`, creates/clears one tab per entry, writes `rows[]`.

Note: spec rule 4 (identical keys in identical order) applies **within a sheet**, not across sheets. Each map's columns are self-contained.

---

## Stories

### US-GSE-2-01 — Multi-sheet builder

**File:** `static/src/exportGoogleSheetsMultiMap.ts`

**Public API:**
```ts
export interface GoogleSheetsWorkbook { version: 'gse-2'; root_map_id: number; sheets: SheetPayload[] }
export function buildGoogleSheetsWorkbook(graph: LinkedGraph): GoogleSheetsWorkbook
```

**Acceptance:**
- One `sheet` per map in `graph.bfsOrder`. Sheet name = `NN-<slug>` (NN zero-padded, ≤ 100 chars).
- Each sheet's `rows` produced by `buildGoogleSheetsRows` from GSE-1 (reused, not duplicated).
- Sheet 0 is always the root map.
- Sheets with > 200 stages flagged in `_Maps.warnings`.

---

### US-GSE-2-02 — Relationships sheet (`_Links`)

A `_Links` tab listing every edge in the graph so business users can see "what triggers what" without opening each tab.

**Columns:** `From Map | From Stage | From Lens | Link Type | To Map | Label`

**Acceptance:**
- One row per `LinkedGraphEdge`.
- Link types rendered in human language: `sub_journey → "Delegates to"`, `exception → "Recovers via"`, `anti_journey → "Alternate path"`, `agent_manual → "Operating manual"`, `parent_child → "Drills into"`.
- `To Map` cells become `=HYPERLINK(...)` formulas, bound at Apps Script time using `SpreadsheetApp.getSheetByName`.

---

### US-GSE-2-03 — Maps metadata sheet (`_Maps`)

A `_Maps` tab with one row per map for at-a-glance navigation.

**Columns:** `Sheet | Map Title | Map Level | Intent | Stages | Lenses | Cells Filled | Origin`

**Acceptance:**
- `Origin` resolves the parent link callout: `"exception from {parent map}/{parent stage}"`.
- Root row shows `(root)`.
- `Sheet` column is a `=HYPERLINK` to the sheet's first cell.

---

### US-GSE-2-04 — Multi-sheet Apps Script

Bundled script: `importLinkedJSON`.

**Behaviour:**
- Wipes existing sheets except first, then creates one tab per `sheets[]` entry.
- Applies GSE-1 formatting (freeze row, bold headers, wrap, autosize) per sheet.
- Resolves `=HYPERLINK` cells for cross-sheet refs.

**Acceptance:**
- Works on a blank spreadsheet on first run.
- Re-running on a populated spreadsheet replaces sheets (no duplication, no orphan tabs).
- Permissions block is the same as GSE-1.

---

### US-GSE-2-05 — Traversal picker dialog

**File:** `static/src/GoogleSheetsLinkedExportDialog.tsx`

**Acceptance:**
- Mirrors `LinkedSkillExportDialog` traversal options: scope (sub / exception / anti / manual / children), depth cap, include-agent-manuals toggle.
- Workbook size guard: warn if total rows > 50 000 or any sheet > 200 columns.
- Preview shows visited map count + total row estimate before generating.
- Same dialog supports both "linked from this map" and "entire architecture from root" via the root-map prop.

---

### US-GSE-2-06 — Architecture-level entrypoint

**File:** `static/src/ArchitectureDetail.tsx`

**Acceptance:**
- Architecture-level export menu gets a new item: "Google Sheets (linked workbook)".
- Per-map kebab gets a fourth item: "Google Sheets (with linked maps)" — opens the same dialog rooted at that map.
- GSE-1-07's MVP item remains unchanged ("Google Sheets (JSON)" stays as single-map shortcut).

---

## Open Questions

- Should `_Links` `=HYPERLINK` resolution live in the JSON payload (pre-cooked) or be computed by Apps Script via `getSheetByName`? **Lean:** Apps Script — keeps JSON portable across sheet renames.
- Sheet-name collision when two maps share a title — extend `mapSlug` with id prefix (already pattern in EXP-1).
- Anchor scheme (`[MAP:…]`, `[STAGE:…]`) from EXP-1 — surface as a `_Anchors` column on `_Maps`? Probably yes, low cost, lets users search the workbook.

## Acceptance (epic-level)

- One paste, one click, business user sees a multi-tab workbook covering the root map's full neighbourhood with cross-sheet hyperlinks.
- Apps Script handles re-imports idempotently.
- Token cost: zero (no API, no LLM).
- Tests cover edge cases: cycles in graph, depth-capped traversals, sheet-name collisions, empty linked maps.
