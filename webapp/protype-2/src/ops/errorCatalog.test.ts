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

// Every backend directory that may raise a user-visible error code.
//
// This list started as OBS-1's own three directories, which left PUB-1's
// and STAGE-1's codes unscanned — E-PUB-001/003/004/005 and E-STAGE-001
// were live in endpoints with no catalog entry, so the Health page could
// not explain them and a user quoting that Reference would have got
// nothing. Found while starting PLN-3. Add new directories here as they
// appear; the point of the test is defeated if the list goes stale.
const BACKEND_CODE_DIRS = [
  ['functions', 'ops'],
  ['functions', 'guards'],
  ['functions', 'pub'],
  ['functions', 'planner'],
  ['apis', 'ops'],
  ['apis', 'planner'],
  ['apis', 'journey_map'],
  // USR-1 (2026-10-22): the team-management guards and endpoints. Added with
  // the directories rather than after them, so E-USR-* can never go live
  // uncataloged the way E-PUB-* and E-STAGE-* did.
  ['functions', 'usr'],
  ['apis', 'members_accounts'],
  // CAT-1 (2026-10-24): the item-type / method catalog. Added with the
  // directories rather than after them, for the same reason USR-1 was.
  ['functions', 'catalog'],
  ['apis', 'catalog'],
  // EXC-1 (2026-10-26): the exception spawn's functions, and the two
  // functions extracted for it (create_job, refresh_job_slots).
  ['functions', 'exceptions'],
  ['functions', 'jobs'],
  ['functions', 'estimate'],
];

test('UT-OBS-1-02: every E-XXX-NNN code referenced in the backend source files exists in the catalog', () => {
  const filesToScan = [
    ...BACKEND_CODE_DIRS.flatMap((parts) => listXsFiles(join(repoRoot, ...parts))),
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
