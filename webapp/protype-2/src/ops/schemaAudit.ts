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
  // US-DEL-1-07 — a MARKER, not a record: a row means "deleted", and
  // restoring removes it. `appendOnly` here is about the SHAPE (no
  // `updated_at`, because a row is never edited), not about permanence
  // — the permanent record of the action is in event_log.
  journey_map_deleted: {naturalKeys: [['journey_map_id']], appendOnly: true},
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
  // Built 2026-10-17 as live table 130 (PLAN-3). Same link-table shape
  // as plan_template_map one line up — a row is added or removed,
  // never edited.
  plan_template_agent: {naturalKeys: [['plan_template_id', 'agent_profile_id']], appendOnly: true},
  planner_workspace_map: {naturalKeys: [['workspace_id', 'journey_map_id']], appendOnly: true},
  work_item: {enumFields: ['status']},
  work_task: {naturalKeys: [['work_item_id', 'stage_key', 'lens_key']], enumFields: ['status']},
  // Built 2026-10-15 as live table 124 (SCHED-1). A link row is
  // created or removed, never edited, so it carries no `updated_at`.
  planner_task_work_task: {naturalKeys: [['work_task_id']], appendOnly: true},
  // COP-1: a run ticket and the AI audit trail are written once and never edited.
  tool_run_ticket: {naturalKeys: [['ticket']], appendOnly: true},
  tool_call_log: {appendOnly: true},
  // COP-1: one copilot per account; one identity per user. Has updated_at (the cap changes).
  ai_identity: {naturalKeys: [['user_id'], ['account_id']]},
  // COP-2: one level per (business, action type); the decision/run race guard is written once;
  // the canon row is transient (written and deleted in one function call).
  copilot_action_level: {naturalKeys: [['journey_architecture_id', 'action_type']], enumFields: ['level']},
  copilot_action: {enumFields: ['status']},
  copilot_action_claim: {naturalKeys: [['copilot_action_id', 'kind']], enumFields: ['kind'], appendOnly: true},
  copilot_json_canon: {appendOnly: true},
  // COP-5 story 05: one row per scheduled run. Written when the run starts and closed ONCE when
  // it ends (`finished_at` is that moment), never edited after - so no `updated_at`, like a ticket.
  // The unique `lock_key` is the 'two runs never overlap' guard.
  copilot_run: {naturalKeys: [['lock_key']], enumFields: ['trigger', 'status'], appendOnly: true},
  // COP-8 story 03 (R15): which run minted a ticket, and which run a tool call was made in.
  // Written once by run_for_business / the gate, never edited - so no `updated_at`.
  copilot_run_ticket: {naturalKeys: [['tool_run_ticket_id']], appendOnly: true},
  tool_call_run: {naturalKeys: [['tool_call_log_id']], appendOnly: true},
  // COP-3: written once; the business of a conversation never changes.
  copilot_home: {naturalKeys: [['account_id'], ['journey_architecture_id']], appendOnly: true},
  copilot_conversation: {naturalKeys: [['agent_conversation_id']], appendOnly: true},
  // COP-4: goals, map labels (one per map) and notes, all scoped by business.
  copilot_goal: {enumFields: ['status']},
  copilot_map_profile: {naturalKeys: [['journey_map_id']], enumFields: ['kind', 'made_by']},
  copilot_note: {},
  // COP-9: the skill library. Items are edited in place (their history is the version table);
  // versions and "skill used" rows are written once; the per-business switch is edited in place.
  copilot_skill: {naturalKeys: [['journey_map_id']], enumFields: ['kind', 'status', 'scope_type']},
  copilot_skill_version: {naturalKeys: [['skill_id', 'version_no']], enumFields: ['change', 'changed_by'], appendOnly: true},
  copilot_skill_off: {naturalKeys: [['skill_id', 'journey_architecture_id']]},
  copilot_skill_use: {appendOnly: true},
  // COP-11: the lock + kind of work (1:1 side table, edited in place) and the per-account limits.
  copilot_skill_meta: {naturalKeys: [['skill_id']], enumFields: ['work_kind']},
  copilot_library_setting: {naturalKeys: [['account_id']]},
  plan_publication: {naturalKeys: [['timeline_id', 'version']], appendOnly: true},
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

  // ── CAT-1 (phase-6): item-type / method catalogs ────────────────────
  // Built 2026-10-24 as local files 135/136; Xano assigns the real ids.
  item_type: {naturalKeys: [['account_id', 'key']], enumFields: ['unit']},
  method: {naturalKeys: [['account_id', 'key']]},

  // ── RATE-1 (phase-6): the published rate card ───────────────────────
  // Written only by publish, never edited, never deleted (history table).
  stage_rate: {
    naturalKeys: [['journey_map_version_id', 'stage_key', 'quantity_key', 'method_key']],
    enumFields: ['source'],
    appendOnly: true,
  },

  // ── EST-1 (phase-6): the counts on a job ────────────────────────────
  work_item_line: {naturalKeys: [['work_item_id', 'item_type_id']]},

  // ── EXC-1 (phase-7): work that left the happy path ──────────────────
  // One row per spawn, never edited (bar one bool set once), never deleted.
  work_item_exception: {
    naturalKeys: [['child_work_item_id']],
    enumFields: ['link_type', 'reason_code', 'source'],
    appendOnly: true,
  },

  // ── Epic-27 (2026-11-21): tags, items on jobs, AI members, orders ───
  map_tag: {naturalKeys: [['account_id', 'name_key']]},
  // A tag link is added or removed, never edited.
  journey_map_tag: {naturalKeys: [['journey_map_id', 'map_tag_id']], appendOnly: true},
  // Replaced as a set when the order changes, never edited.
  work_item_unmatched_line: {appendOnly: true},
  ai_member_profile: {naturalKeys: [['user_id']]},
  // A token is never edited: only revoked_at and last_used_at are stamped
  // (same shape as work_item_exception's one bool set once).
  agent_access_token: {appendOnly: true},
  work_item_origin: {naturalKeys: [['account_id', 'source_system', 'external_id']], enumFields: ['order_flag']},
  order_route: {naturalKeys: [['account_id', 'source_system', 'match_fulfilment']]},
  // One row per order received; kept 30 days, never edited.
  order_inbox: {enumFields: ['outcome'], appendOnly: true},
  order_route_live_day: {naturalKeys: [['route_id']]},
  // One row per job added to a live day (D-11); never edited, never deleted.
  live_day_addition: {appendOnly: true},
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
    // ITEM-1 (2026-10-24) — collect every `type:` match's position FIRST,
    // then slice segments between consecutive matches. The previous
    // approach re-searched for the bare substring "type" via indexOf to
    // find each segment's end, which also matches "type" embedded inside
    // a column name like `item_type_id` — truncating the segment before
    // its own `name:` value and silently losing that field from the
    // index. Found live: journey_lens_item's own (journey_lens,
    // item_type_id) unique index audited as covering only journey_lens,
    // and a trailing single-column index on item_type_id audited as
    // covering no fields at all, both because of this substring match.
    const typeMatches = [...indexBody.matchAll(entryPattern)];
    for (let i = 0; i < typeMatches.length; i++) {
      const em = typeMatches[i];
      const type = em[1];
      const start = em.index! + em[0].length;
      const end2 = i + 1 < typeMatches.length ? typeMatches[i + 1].index! : indexBody.length;
      const segment = indexBody.slice(start, end2);
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
