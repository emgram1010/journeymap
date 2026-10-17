import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync, readdirSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  parseTableFile,
  auditTable,
  auditAll,
  errorsOnly,
  formatFindings,
  TABLE_MANIFEST,
  type TableExpectation,
} from './schemaAudit';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, '..', '..', '..', '..');
const tablesDir = join(repoRoot, 'static', 'tables');

/** A minimal table that satisfies every machine-checkable standard. */
const COMPLIANT = `
table widget {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int account_id? {
      table = "account"
    }

    text name? filters=trim
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
  ]
}
`;

test('parses name, id, fields and indexes from a table file', () => {
  const parsed = parseTableFile(COMPLIANT, '80_widget.xs');
  assert.equal(parsed.name, 'widget');
  assert.equal(parsed.tableId, 80);
  assert.deepEqual(
    parsed.fields.map((f) => f.name),
    ['id', 'created_at', 'updated_at', 'account_id', 'name'],
  );
  assert.equal(parsed.fields.find((f) => f.name === 'account_id')?.referencesTable, 'account');
  assert.equal(parsed.indexes.length, 2);
  assert.deepEqual(parsed.indexes[0], {type: 'primary', fields: ['id']});
});

test('UT-GOV-1-04: a fully compliant new table passes with no findings', () => {
  const findings = auditTable(parseTableFile(COMPLIANT, '80_widget.xs'), {});
  assert.deepEqual(findings, [], formatFindings(findings));
});

test('UT-GOV-1-01: a new table missing `id` fails, naming the table', () => {
  const noId = COMPLIANT.replace('    int id\n', '');
  const findings = auditTable(parseTableFile(noId, '80_widget.xs'), {});
  const s1 = findings.filter((f) => f.rule === 'S1');
  assert.ok(s1.length > 0);
  assert.equal(s1[0].severity, 'error');
  assert.equal(s1[0].table, 'widget');
});

test('UT-GOV-1-02: a new table with an unindexed reference fails', () => {
  const unindexed = COMPLIANT.replace('    {type: "btree", field: [{name: "account_id", op: "asc"}]}\n', '');
  const findings = auditTable(parseTableFile(unindexed, '80_widget.xs'), {});
  const s3 = findings.filter((f) => f.rule === 'S3');
  assert.equal(s3.length, 1);
  assert.match(s3[0].message, /account_id/);
  assert.equal(s3[0].severity, 'error');
});

test('UT-GOV-1-03: a declared natural key with no unique index fails', () => {
  const manifest: Record<string, TableExpectation> = {widget: {naturalKeys: [['account_id', 'name']]}};
  const findings = auditTable(parseTableFile(COMPLIANT, '80_widget.xs'), manifest);
  const s6 = findings.filter((f) => f.rule === 'S6');
  assert.equal(s6.length, 1);
  assert.match(s6[0].message, /account_id, name/);
});

test('a natural key WITH its unique index passes', () => {
  const withUnique = COMPLIANT.replace(
    '    {type: "btree", field: [{name: "account_id", op: "asc"}]}',
    '    {type: "btree", field: [{name: "account_id", op: "asc"}]}\n    {type: "btree|unique", field: [{name: "account_id", op: "asc"}, {name: "name", op: "asc"}]}',
  );
  const manifest: Record<string, TableExpectation> = {widget: {naturalKeys: [['account_id', 'name']]}};
  const findings = auditTable(parseTableFile(withUnique, '80_widget.xs'), manifest);
  assert.deepEqual(findings.filter((f) => f.rule === 'S6'), []);
});

test('S7: a column that should be an enum but is text fails', () => {
  const manifest: Record<string, TableExpectation> = {widget: {enumFields: ['name']}};
  const findings = auditTable(parseTableFile(COMPLIANT, '80_widget.xs'), manifest);
  const s7 = findings.filter((f) => f.rule === 'S7');
  assert.equal(s7.length, 1);
  assert.match(s7[0].message, /expected enum/);
});

test('S2: a new table with no updated_at fails unless marked append-only', () => {
  const noUpdated = COMPLIANT.replace('    date updated_at?\n\n', '');
  const failing = auditTable(parseTableFile(noUpdated, '80_widget.xs'), {});
  assert.ok(failing.some((f) => f.rule === 'S2' && /updated_at/.test(f.message)));

  const appendOnly = auditTable(parseTableFile(noUpdated, '80_widget.xs'), {widget: {appendOnly: true}});
  assert.deepEqual(appendOnly.filter((f) => f.rule === 'S2'), []);
});

test('S10: an append-only table that has updated_at is flagged', () => {
  const findings = auditTable(parseTableFile(COMPLIANT, '80_widget.xs'), {widget: {appendOnly: true}});
  assert.ok(findings.some((f) => f.rule === 'S10'));
});

test('UT-GOV-1-05: the same problem on a grandfathered table is a warning, not an error', () => {
  const noId = COMPLIANT.replace('    int id\n', '');
  const findings = auditTable(parseTableFile(noId, '9_widget.xs'), {});
  assert.ok(findings.length > 0);
  assert.ok(findings.every((f) => f.severity === 'warning'), formatFindings(findings));
  assert.deepEqual(errorsOnly(findings), []);
});

test('UT-GOV-1-06: every manifest entry names only fields the audit can check', () => {
  for (const [tableName, expectation] of Object.entries(TABLE_MANIFEST)) {
    for (const key of expectation.naturalKeys ?? []) {
      assert.ok(key.length > 0, `${tableName}: empty natural key`);
      assert.ok(
        key.every((f) => typeof f === 'string' && f.length > 0),
        `${tableName}: natural key has an empty field name`,
      );
    }
    for (const field of expectation.enumFields ?? []) {
      assert.ok(typeof field === 'string' && field.length > 0, `${tableName}: empty enum field name`);
    }
  }
});

test('FT-GOV-1-01: the real static/tables/ directory has no ERROR-level findings', () => {
  const files = readdirSync(tablesDir)
    .filter((f) => f.endsWith('.xs'))
    .map((fileName) => ({fileName, text: readFileSync(join(tablesDir, fileName), 'utf8')}));

  assert.ok(files.length > 0, 'expected to find table files to audit');

  const findings = auditAll(files);
  const errors = errorsOnly(findings);
  assert.deepEqual(errors, [], `new tables must satisfy every standard:\n${formatFindings(errors)}`);
});

test('the real table files all parse into a named table with fields', () => {
  const files = readdirSync(tablesDir).filter((f) => f.endsWith('.xs'));
  for (const fileName of files) {
    const parsed = parseTableFile(readFileSync(join(tablesDir, fileName), 'utf8'), fileName);
    assert.ok(parsed.name.length > 0, `${fileName}: could not parse a table name`);
    assert.ok(parsed.fields.length > 0, `${fileName}: parsed zero fields`);
    assert.ok(
      parsed.fields.some((f) => f.name === 'id'),
      `${fileName}: parsed no id column`,
    );
  }
});
