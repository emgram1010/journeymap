// US-GSE-1-01/02/03/06 — Pure builder for the Google Sheets JSON export.
// One row per stage. Every row carries the exact same key set in the same order
// so the array doubles as spreadsheet header + body. Multi-value fields are
// flattened with " • ". Empty cells fall back to a structured render of
// actorFields so the sheet stays business-readable even before fill-out.

import type {Lens, MatrixCell, Stage, ActorFields} from './types';

const JOINER = ' • ';

export interface GoogleSheetsRow {
  [columnLabel: string]: string;
}

export interface BuildGoogleSheetsRowsInput {
  mapTitle: string;
  stages: Stage[];
  lenses: Lens[];
  cells: MatrixCell[];
}

const dashIfEmpty = (s: string): string => (s.trim() === '' ? '—' : s);

// Render structured actor fields into a single business-readable line:
//   "label: value • label: value"
// Keys are humanised (snake_case → Title Case). Null/empty values are skipped.
const flattenActorFields = (fields: ActorFields | null | undefined): string => {
  if (!fields || typeof fields !== 'object') return '';
  const parts: string[] = [];
  for (const [key, value] of Object.entries(fields)) {
    if (value === null || value === undefined) continue;
    const str = String(value).trim();
    if (str === '') continue;
    // Drop the numeric _value mirror fields (FinancialActorFields) — the string
    // sibling already carries the human label.
    if (key.endsWith('_value')) continue;
    const label = key.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
    parts.push(`${label}: ${str}`);
  }
  return parts.join(JOINER);
};

// Disambiguate duplicate lens labels by appending " (2)", " (3)" etc.
const buildUniqueLensColumns = (lenses: Lens[]): Array<{lens: Lens; column: string}> => {
  const counts = new Map<string, number>();
  return lenses.map((lens) => {
    const base = (lens.label ?? '').trim() || 'Lens';
    const seen = counts.get(base) ?? 0;
    counts.set(base, seen + 1);
    const column = seen === 0 ? base : `${base} (${seen + 1})`;
    return {lens, column};
  });
};

const resolveOwnedBy = (stage: Stage, lenses: Lens[]): string => {
  if (!stage.primaryActorLens) return '—';
  const owner = lenses.find((l) => l.key === stage.primaryActorLens);
  return owner?.label?.trim() || stage.primaryActorLens;
};

const cellContent = (cell: MatrixCell | undefined): string => {
  if (!cell) return '';
  const content = (cell.content ?? '').trim();
  if (content !== '') return content;
  return flattenActorFields(cell.actorFields);
};

const sortByDisplayOrder = <T extends {displayOrder?: number}>(items: T[]): T[] =>
  [...items].sort((a, b) => (a.displayOrder ?? 0) - (b.displayOrder ?? 0));

export function buildGoogleSheetsRows(input: BuildGoogleSheetsRowsInput): GoogleSheetsRow[] {
  const stages = sortByDisplayOrder(input.stages);
  const lenses = sortByDisplayOrder(input.lenses);
  const lensColumns = buildUniqueLensColumns(lenses);

  // Pre-index cells by stageId+lensId for O(1) lookup.
  const cellByKey = new Map<string, MatrixCell>();
  for (const c of input.cells) cellByKey.set(`${c.stageId}::${c.lensId}`, c);

  return stages.map((stage, idx) => {
    const row: GoogleSheetsRow = {
      'Map': input.mapTitle,
      'Stage #': String(idx + 1),
      'Stage': dashIfEmpty(stage.label ?? ''),
      'Stage Goal': dashIfEmpty(stage.stageGoal ?? ''),
      'Owned By': resolveOwnedBy(stage, lenses),
    };
    for (const {lens, column} of lensColumns) {
      row[column] = dashIfEmpty(cellContent(cellByKey.get(`${stage.id}::${lens.id}`)));
    }
    return row;
  });
}

export function serializeGoogleSheetsJson(rows: GoogleSheetsRow[]): string {
  return JSON.stringify(rows, null, 2);
}

// Apps Script users paste this into Extensions → Apps Script → run importJSON.
// Opens an HTML modal with a <textarea> (avoids ui.prompt 400 errors on large
// payloads) and posts the JSON back via google.script.run. The server-side
// writeJSON writes header + rows with frozen-bold header, wrap, and column
// auto-resize for readability.
export const APPS_SCRIPT_IMPORT_CODE = `function importJSON() {
  var html = HtmlService.createHtmlOutput(
    '<style>body{font-family:Arial,sans-serif;margin:8px;}textarea{width:100%;height:260px;font-family:monospace;font-size:11px;}button{padding:6px 14px;margin-top:8px;}.err{color:#b00;font-size:11px;margin-top:6px;min-height:14px;}</style>' +
    '<p style="margin:0 0 6px 0;font-size:12px;">Paste the exported Emgram JSON array, then click Import.</p>' +
    '<textarea id="j" placeholder="[ { ... }, { ... } ]"></textarea>' +
    '<div class="err" id="e"></div>' +
    '<button onclick="go()">Import</button>' +
    '<script>function go(){var t=document.getElementById("j").value;document.getElementById("e").textContent="Importing\u2026";google.script.run.withSuccessHandler(function(){google.script.host.close();}).withFailureHandler(function(err){document.getElementById("e").textContent=err.message||String(err);}).writeJSON(t);}<\\/script>'
  ).setWidth(560).setHeight(420);
  SpreadsheetApp.getUi().showModalDialog(html, 'Paste Emgram JSON');
}

function writeJSON(jsonText) {
  var rows;
  try { rows = JSON.parse(jsonText); }
  catch (e) { throw new Error('Invalid JSON: ' + e.message); }
  if (!Array.isArray(rows) || rows.length === 0) { throw new Error('No rows found.'); }
  var headers = Object.keys(rows[0]);
  var data = rows.map(function (r) { return headers.map(function (h) { return r[h] == null ? '' : String(r[h]); }); });
  var sheet = SpreadsheetApp.getActiveSheet();
  sheet.clear();
  sheet.getRange(1, 1, 1, headers.length).setValues([headers]).setFontWeight('bold');
  if (data.length > 0) sheet.getRange(2, 1, data.length, headers.length).setValues(data);
  sheet.setFrozenRows(1);
  sheet.getRange(1, 1, data.length + 1, headers.length).setWrap(true);
  for (var i = 1; i <= headers.length; i++) sheet.autoResizeColumn(i);
}`;
