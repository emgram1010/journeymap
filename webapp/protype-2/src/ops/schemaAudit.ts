// GOV-1 (US-GOV-1-04) — Schema conformance audit.
//
// Parses the XanoScript table files in static/tables/ and checks them
// against the GOV-1 standards (docs/data-standards.md). New tables
// (id >= NEW_TABLE_MIN_ID) produce FAILURES; tables created before
// GOV-1 are grandfathered and produce WARNINGS only, so the audit can
// run on the whole repo from day one without blocking on legacy debt.
//
// Runs as part of `npm test` (see schemaAudit.test.ts), so a new table
// that breaks a standard fails the build with the table and rule named.

export type Severity = 'error' | 'warning';

export interface AuditFinding {
  table: string;
  tableId: number | null;
  rule: string;
  severity: Severity;
  message: string;
}

export interface ParsedField {
  name: string;
  type: string;
  optional: boolean;
  /** The table this column references, when it declares `table = "..."`. */
  referencesTable: string | null;
}

export interface ParsedIndex {
  /** Raw type string, e.g. "primary", "btree", "btree|unique". */
  type: string;
  /** Field names in index order. */
  fields: string[];
}

export interface ParsedTable {
  fileName: string;
  /** Numeric prefix of the file name, e.g. 9 for "9_journey_cell.xs". */
  tableId: number | null;
  name: string;
  fields: ParsedField[];
  indexes: ParsedIndex[];
}

/** Tables numbered at or above this are held to the full standard. */
export const NEW_TABLE_MIN_ID = 80;

export interface TableExpectation {
  /** Natural keys that must each have a unique index, in order. */
  naturalKeys?: string[][];
  /** Columns that must be declared as `enum`, not free text (S7). */
  enumFields?: string[];
  /** Append-only tables deliberately have no `updated_at` (S2, S10). */
  appendOnly?: boolean;
}

/**
 * Expectations the file itself cannot express. Keep in step with
 * docs/data-model-phase-4.md — that document is the human-readable
 * version of this manifest.
 *
 * Entries are listed for tables that do not exist yet, on purpose: the
 * audit only checks a table once its file appears, and having the
 * expectation written down first means the table cannot land without it.
 */
export const TABLE_MANIFEST: Record<string, TableExpectation> = {
  // ── Existing tables (grandfathered; findings are warnings) ──────────
  journey_cell: {naturalKeys: [['journey_map', 'stage', 'lens']]},

  // ── Phase-4 tables (full standard once their files land) ────────────
  actor_role: {naturalKeys: [['account_id', 'name_key']], enumFields: ['actor_type']},
  agent_role: {naturalKeys: [['planner_agent_id', 'actor_role_id']]},
  journey_map_version: {naturalKeys: [['journey_map_id', 'version_no']], appendOnly: true},
  // Built 2026-10-14 as live tables 119, 120, 121 (PLAN-1).
  // `name`, not `name_key`: this matches its sibling `planner_workspace`,
  // which also keys on (account_id, name). Case-insensitive template
  // names would need a normalized column on BOTH tables to stay
  // consistent — worth doing, but as one deliberate change, not as a
  // quiet divergence between two tables that look alike.
  plan_template: {naturalKeys: [['account_id', 'name']]},
  // Link tables: rows are added or removed, never edited, so they have
  // no `updated_at` (GOV-1 S10).
  plan_template_map: {naturalKeys: [['plan_template_id', 'journey_map_id']], appendOnly: true},
  planner_workspace_map: {naturalKeys: [['workspace_id', 'journey_map_id']], appendOnly: true},
  work_item: {enumFields: ['status']},
  work_task: {naturalKeys: [['work_item_id', 'stage_key', 'lens_key']], enumFields: ['status']},
  planner_task_work_task: {naturalKeys: [['work_task_id']]},
  plan_publication: {naturalKeys: [['timeline_id']], appendOnly: true},
  plan_change_log: {enumFields: ['change_type'], appendOnly: true},
  activity_log: {naturalKeys: [['client_event_id']], enumFields: ['event_type', 'source'], appendOnly: true},
  account_feature_flag: {naturalKeys: [['account_id', 'flag_key']], enumFields: ['flag_key']},

  // ── Phase-3 planner tables (PLN-1, amended by P3A-1) ────────────────
  planner_settings: {naturalKeys: [['account_id']]},
  planner_model: {naturalKeys: [['account_id', 'model_key']]},
  planner_workspace: {naturalKeys: [['account_id', 'name']]},
  planner_agent: {naturalKeys: [['workspace_id', 'name']], enumFields: ['kind']},
  planner_timeline: {naturalKeys: [['agent_id', 'planned_date']], enumFields: ['status']},
  // planner_task has no natural key on purpose: (timeline_id, seq) must not
  // be unique, because a reorder rewrites several rows and would collide
  // mid-flight. PLN-7's resequence function guarantees the ordering instead.
  planner_task: {enumFields: ['status']},
};

const FIELD_TYPES = [
  'int', 'text', 'enum', 'bool', 'json', 'decimal', 'timestamp', 'date', 'uuid',
  'email', 'password', 'object', 'vector', 'image', 'video', 'audio', 'attachment',
];

/** Returns the body of a `{ ... }` block starting at the brace at or after `from`. */
function extractBlock(text: string, from: number): {body: string; end: number} | null {
  const open = text.indexOf('{', from);
  if (open === -1) return null;
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === '{') depth++;
    else if (text[i] === '}') {
      depth--;
      if (depth === 0) return {body: text.slice(open + 1, i), end: i};
    }
  }
  return null;
}

function stripComments(text: string): string {
  return text
    .split('\n')
    .map((line) => (line.trimStart().startsWith('//') ? '' : line))
    .join('\n');
}

export function parseTableFile(text: string, fileName: string): ParsedTable {
  const source = stripComments(text);

  const nameMatch = source.match(/^\s*table\s+"?([A-Za-z0-9_]+)"?\s*\{/m);
  const name = nameMatch ? nameMatch[1] : '';

  const idMatch = fileName.match(/^(\d+)_/);
  const tableId = idMatch ? Number(idMatch[1]) : null;

  const fields: ParsedField[] = [];
  const schemaIdx = source.search(/^\s*schema\s*\{/m);
  if (schemaIdx !== -1) {
    const schemaBlock = extractBlock(source, schemaIdx);
    if (schemaBlock) {
      // Walk the schema body line by line. A field is "<type> <name>[?]",
      // optionally followed by a { ... } block that may declare `table =`.
      const body = schemaBlock.body;
      const fieldPattern = new RegExp(
        `^[ \\t]*(${FIELD_TYPES.join('|')})\\??[ \\t]+\\??([A-Za-z0-9_]+)\\??`,
        'gm',
      );
      let m: RegExpExecArray | null;
      while ((m = fieldPattern.exec(body)) !== null) {
        const [matched, type, fieldName] = m;
        const optional = matched.includes('?');

        // If this declaration opens a block, look inside it for `table =`.
        let referencesTable: string | null = null;
        const restOfLineEnd = body.indexOf('\n', m.index);
        const restOfLine = body.slice(m.index, restOfLineEnd === -1 ? undefined : restOfLineEnd);
        if (restOfLine.includes('{')) {
          const block = extractBlock(body, m.index);
          if (block) {
            const refMatch = block.body.match(/table\s*=\s*"([A-Za-z0-9_]+)"/);
            if (refMatch) referencesTable = refMatch[1];
          }
        }

        fields.push({name: fieldName, type, optional, referencesTable});
      }
    }
  }

  const indexes: ParsedIndex[] = [];
  const indexIdx = source.search(/^\s*index\s*=\s*\[/m);
  if (indexIdx !== -1) {
    const bracketStart = source.indexOf('[', indexIdx);
    let depth = 0;
    let end = bracketStart;
    for (let i = bracketStart; i < source.length; i++) {
      if (source[i] === '[') depth++;
      else if (source[i] === ']') {
        depth--;
        if (depth === 0) {
          end = i;
          break;
        }
      }
    }
    const indexBody = source.slice(bracketStart + 1, end);
    const entryPattern = /type\s*:\s*"([^"]+)"/g;
    let em: RegExpExecArray | null;
    while ((em = entryPattern.exec(indexBody)) !== null) {
      const type = em[1];
      // Collect the field names that follow this type, up to the next `type:`.
      const nextType = indexBody.indexOf('type', em.index + em[0].length);
      const segment = indexBody.slice(em.index, nextType === -1 ? undefined : nextType);
      const fieldNames = [...segment.matchAll(/name\s*:\s*"([A-Za-z0-9_]+)"/g)].map((fm) => fm[1]);
      indexes.push({type, fields: fieldNames});
    }
  }

  return {fileName, tableId, name, fields, indexes};
}

function hasPrimaryOnId(table: ParsedTable): boolean {
  return table.indexes.some((i) => i.type.includes('primary') && i.fields[0] === 'id');
}

function isIndexedFirst(table: ParsedTable, fieldName: string): boolean {
  return table.indexes.some((i) => i.fields[0] === fieldName);
}

function hasUniqueIndexFor(table: ParsedTable, key: string[]): boolean {
  return table.indexes.some(
    (i) => i.type.includes('unique') && i.fields.length === key.length && i.fields.every((f, n) => f === key[n]),
  );
}

export function auditTable(
  table: ParsedTable,
  manifest: Record<string, TableExpectation> = TABLE_MANIFEST,
): AuditFinding[] {
  const findings: AuditFinding[] = [];
  const isNew = table.tableId !== null && table.tableId >= NEW_TABLE_MIN_ID;
  const severity: Severity = isNew ? 'error' : 'warning';
  const expectation = manifest[table.name] ?? {};

  const add = (rule: string, message: string) =>
    findings.push({table: table.name || table.fileName, tableId: table.tableId, rule, severity, message});

  // S1 — primary key
  const idField = table.fields.find((f) => f.name === 'id');
  if (!idField) add('S1', 'no `id` column');
  else if (idField.type !== 'int' && idField.type !== 'uuid') add('S1', `\`id\` is \`${idField.type}\`, expected int or uuid`);
  if (!hasPrimaryOnId(table)) add('S1', 'no primary index on `id`');

  // S2 — timestamps
  if (!table.fields.some((f) => f.name === 'created_at')) add('S2', 'no `created_at` column');
  if (!expectation.appendOnly && !table.fields.some((f) => f.name === 'updated_at')) {
    add('S2', 'no `updated_at` column (add one, or mark the table append-only in the manifest)');
  }
  if (expectation.appendOnly && table.fields.some((f) => f.name === 'updated_at')) {
    add('S10', 'append-only table has an `updated_at` column');
  }

  // S3 — references declared and indexed
  for (const field of table.fields) {
    if (field.referencesTable && !isIndexedFirst(table, field.name)) {
      add('S3', `\`${field.name}\` references \`${field.referencesTable}\` but is not the first field of any index`);
    }
  }

  // S6 — natural-key uniqueness
  for (const key of expectation.naturalKeys ?? []) {
    if (!hasUniqueIndexFor(table, key)) {
      add('S6', `no unique index on (${key.join(', ')})`);
    }
  }

  // S7 — finite sets are enums
  for (const fieldName of expectation.enumFields ?? []) {
    const field = table.fields.find((f) => f.name === fieldName);
    if (!field) add('S7', `expected an enum column \`${fieldName}\`, which is missing`);
    else if (field.type !== 'enum') add('S7', `\`${fieldName}\` is \`${field.type}\`, expected enum`);
  }

  return findings;
}

export function auditAll(
  files: {fileName: string; text: string}[],
  manifest: Record<string, TableExpectation> = TABLE_MANIFEST,
): AuditFinding[] {
  return files.flatMap((f) => auditTable(parseTableFile(f.text, f.fileName), manifest));
}

export const errorsOnly = (findings: AuditFinding[]) => findings.filter((f) => f.severity === 'error');

export function formatFindings(findings: AuditFinding[]): string {
  if (findings.length === 0) return 'No findings.';
  return findings
    .map((f) => `[${f.severity}] ${f.table} (${f.rule}): ${f.message}`)
    .join('\n');
}
