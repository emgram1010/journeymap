import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync, readdirSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {errorCatalog, validateCatalog, findUncatalogedCodes, getCatalogEntry} from './errorCatalog';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, '..', '..', '..', '..');

test('UT-OBS-1-01: every catalog entry has all required fields and valid enums', () => {
  const issues = validateCatalog(errorCatalog);
  assert.deepEqual(issues, []);
});

test('UT-OBS-1-03: no jargon or raw codes leak into user_message', () => {
  for (const entry of Object.values(errorCatalog)) {
    assert.doesNotMatch(entry.user_message, /stack trace/i);
    assert.doesNotMatch(entry.user_message, /\bE-[A-Z]+-\d{3}\b/);
    assert.doesNotMatch(entry.user_message, /TypeError|ReferenceError/);
  }
});

test('UT-OBS-1-02: every E-XXX-NNN code referenced in the OBS-1 source files exists in the catalog', () => {
  const filesToScan = [
    ...listXsFiles(join(repoRoot, 'functions', 'ops')),
    ...listXsFiles(join(repoRoot, 'apis', 'ops')),
    join(repoRoot, 'tasks', '16_ops_heartbeat.xs'),
  ];

  const allSource = filesToScan.map((f) => readFileSync(f, 'utf8')).join('\n');
  const missing = findUncatalogedCodes(allSource, errorCatalog);
  assert.deepEqual(missing, [], `codes used but not in the catalog: ${missing.join(', ')}`);
});

test('getCatalogEntry returns undefined for an unknown or missing code', () => {
  assert.equal(getCatalogEntry('E-DOES-NOT-EXIST'), undefined);
  assert.equal(getCatalogEntry(null), undefined);
  assert.equal(getCatalogEntry(undefined), undefined);
});

test('getCatalogEntry returns the entry for a known code', () => {
  const entry = getCatalogEntry('E-OBS-001');
  assert.ok(entry);
  assert.equal(entry!.owner, 'engineer');
});

test('validateCatalog flags a missing field, a bad owner, and jargon', () => {
  const broken = {
    'E-TEST-001': {
      code: 'E-TEST-001',
      feature: 'TEST',
      user_message: 'TypeError: something broke',
      what_happened: '',
      likely_cause: 'unknown',
      owner: 'nobody',
      severity: 'error',
      fix_hint: 'retry',
    },
  } as unknown as Parameters<typeof validateCatalog>[0];

  const issues = validateCatalog(broken);
  const problems = issues.map((i) => i.problem).join(' | ');
  assert.match(problems, /missing required field "what_happened"/);
  assert.match(problems, /owner "nobody" is not one of/);
  assert.match(problems, /jargon/);
});

function listXsFiles(dir: string): string[] {
  try {
    return readdirSync(dir)
      .filter((f) => f.endsWith('.xs'))
      .map((f) => join(dir, f));
  } catch {
    return [];
  }
}
