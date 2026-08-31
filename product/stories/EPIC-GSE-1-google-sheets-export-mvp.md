# Google Sheets JSON Export — Epic PRD (MVP)

**Epic ID:** GSE-1
**Status:** Planning
**Goal:** From a single journey map's kebab menu, export the map as a JSON array that pastes 1:1 into a bundled Google Apps Script and produces a clean, business-readable spreadsheet — one row per stage, one column per actor.

---

## Audience

Primary: business + operations stakeholders who consume journey maps in spreadsheets for review, status reporting, and change baselining. Not LLMs — that is what EXP-1 / NotebookLM exports are for.

## Context

`static/src/exportMarkdownBundle.ts`, `exportMarkdownNotebookLM.ts`, and `exportLinkedSkillBundle.ts` cover AI / LLM consumption. There is no spreadsheet-friendly export. Pasting Markdown into Sheets is unusable; CSV loses Unicode and bullets; the only delivery channel non-technical users trust is "open Sheets, paste, click run".

## Existing Architecture (Do Not Break)

- `static/src/exportMarkdownBundle.ts::buildJourneyMapFiles` — reference pattern: pure builder + thin DOM trigger.
- `static/src/xano.ts::loadJourneyMapBundle` — hydrates one map (stages, lenses, cells, actorFields).
- `static/src/ArchitectureDetail.tsx` — per-map kebab menu (~lines 190–200) hosts "Intelligence Layer" + "NotebookLM".
- `static/src/types.ts` — `MatrixCell`, `Stage`, `Lens`, `ActorFields` union.

## Non-Goals (MVP)

- No multi-map / architecture-level export (see GSE-2).
- No backend changes — frontend only.
- No live Sheets API integration — Apps Script paste flow only.
- No CSV / XLSX format. No toast system — feedback inline in dialog.

## Output Contract (LOCKED)

JSON array of flat objects, pretty-printed (2-space indent). Identical keys in identical order across every object. Multi-value content collapsed via ` • `. Empty cells = `""`. Columns are dynamic per map.

```json
[
  {
    "Stage": "Receive Intake",
    "Stage Goal": "Intake parsed; name, company, pain confirmed",
    "Owned By": "Customer",
    "Customer": "Submits form • Gets confirmation",
    "Internal": "Triage queue notified",
    "Handoff": ""
  }
]
```

Column order: `Stage` → `Stage Goal` (conditional) → `Owned By` (conditional) → each lens in `display_order`.

---

## Stories

### US-GSE-1-01 — Pure builder + Apps Script constant

**File:** `static/src/exportGoogleSheetsJson.ts`

**Public API:**
```ts
export function buildGoogleSheetsRows(bundle: HydratedJourneyMapBundle): Array<Record<string, string>>
export function serializeGoogleSheetsJson(rows): string  // JSON.stringify(rows, null, 2)
export const APPS_SCRIPT_IMPORT_CODE: string
```

**Acceptance:**
- One row per stage in `display_order`.
- Headers built once, applied to every row → identical keys in identical order.
- Multi-line content split on `\n`, leading bullets (`- `, `* `, `• `, `–`) stripped, trimmed, empties dropped, joined with ` • `.
- Empty cells emit `""`. No DOM dependency.
- Duplicate lens labels disambiguated with `(2)`, `(3)`, …

---

### US-GSE-1-02 — actorFields fallback

When `cell.content` is empty but the lens has structured `actorFields`, render populated fields as `"Field Label: value • Field Label: value"` instead of leaving blank.

**Acceptance:**
- Per actor_type (customer, internal, engineering, handoff, vendor, financial, ai_agent, metrics), known field keys mapped to human labels.
- Only non-empty fields included; passed through the same collapse rule.
- `cell.content` always wins when present.

---

### US-GSE-1-03 — Stage Goal + Owned By columns

Context columns business reviewers expect: stage exit condition and accountable actor.

**Acceptance:**
- `Stage Goal` included only when at least one stage has non-empty `stageGoal`.
- `Owned By` included only when at least one stage has `primaryActorLens`; value = that lens's `label`.
- Both come before the lens columns.

---

### US-GSE-1-04 — Unit tests

**File:** `static/src/exportGoogleSheetsJson.test.ts`

**Acceptance:**
- Roundtrip: `JSON.parse(serialize(rows))` equals input.
- Every row has identical key set in identical order.
- Every value is a string. Multi-line + bullet collapse cases. Duplicate label disambiguation.
- Empty map (0 stages) returns `[]`. 0-lens map returns context-columns-only rows.
- Special chars (quotes, newlines, emoji) survive roundtrip.

---

### US-GSE-1-05 — Export dialog

**File:** `static/src/GoogleSheetsExportDialog.tsx`

**UI:**
- Title: "Export to Google Sheets (JSON)" + one-line audience copy.
- JSON preview (truncated above 4k chars with "Show full").
- Primary actions: `Copy JSON`, `Download .json`.
- 4-step import instructions + Apps Script code block with `Copy Script`.
- Inline confirmation toast ("Copied!", "Downloaded") that fades after 2s.
- Warning row when any joined cell > 40 000 chars (Sheets limit is 50 000).

**Acceptance:**
- Receives rows + json string as props; no fetching inside the dialog.
- Copy uses `navigator.clipboard.writeText`; falls back to a select-this-text textarea when unavailable.
- Download mirrors `exportJourneyMapBundle`'s Blob + anchor pattern. Closes on Esc / backdrop / X.

---

### US-GSE-1-06 — Apps Script readability upgrade

Bundled in `APPS_SCRIPT_IMPORT_CODE`:

```js
sheet.setFrozenRows(1);
sheet.getRange(1, 1, 1, headers.length).setFontWeight("bold").setBackground("#f3f4f6");
range.setWrap(true).setVerticalAlignment("top");
sheet.autoResizeColumns(1, headers.length);
```

**Acceptance:** Header row frozen + bold + light-gray bg; all cells wrap + top-align; columns auto-sized. Single `importJSON` function, no helpers.

---

### US-GSE-1-07 — Wire export menu

**File:** `static/src/ArchitectureDetail.tsx`

**Acceptance:**
- New menu item "Google Sheets (JSON)" under the existing "Export" sub-header in the per-map kebab. Order: Intelligence Layer → NotebookLM → Google Sheets (JSON).
- `handleExportGoogleSheets(map)` loads bundle, builds rows, opens dialog. Error path: `setError('Unable to export map for Google Sheets. Please try again.')`.
- Dialog state lifted to `ArchitectureDetail`, same pattern as `LinkedSkillExportDialog`.
- Empty map (0 stages) → dialog shows "Nothing to export" instead of throwing.

---

## Acceptance (epic-level)

- Pasting exported JSON into bundled `importJSON` produces: frozen + bold header row; one row per stage; columns in declared order; no crash on empty cells.
- Multi-line content renders as ` • `-joined single strings.
- Maps with `actorFields`-only content still produce informative cells.
- Tests green: `npm test -- exportGoogleSheetsJson`.

## Known Limitations (shown in dialog)

- Single map only — see GSE-2 for multi-map.
- Sheet cell hard limit 50 000 chars; collapsed cells over 40k warn in dialog.
- Clipboard API requires HTTPS or `localhost`.
- One sheet per import — re-running overwrites starting at A1.
