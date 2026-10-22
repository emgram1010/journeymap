// GUARD 1 — the error-code registry, checked against the real backend.
//
// Two halves: unit cases for the extraction and comparison rules, then
// one test that runs them over every `.xs` file in the repo. That last
// one is the guard — it is what would have failed the moment O4 reused
// `E-SCHED-002`.
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  extractCodeUsages,
  stripCode,
  findRegistryProblems,
  findCodePairingProblems,
  type CatalogEntry,
} from './errorCodeRegistry';
import catalogJson from './errorCatalog.json' with {type: 'json'};

const catalog = catalogJson as unknown as Record<string, CatalogEntry>;
const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');

// ── extraction rules ─────────────────────────────────────────────────

test('UT-REG-01 pulls the code and its complete literal message', () => {
  const [u] = extractCodeUsages('        value = "That day is already live. (E-SCHED-006)"', 'x.xs');
  assert.equal(u.code, 'E-SCHED-006');
  assert.equal(u.literalMessage, 'That day is already live. (E-SCHED-006)');
});

test('UT-REG-02 refuses to guess at a concatenated message', () => {
  const [u] = extractCodeUsages(`        value = "'" ~ $t ~ "' is not published. (E-JOB-003)"`, 'x.xs');
  assert.equal(u.code, 'E-JOB-003');
  assert.equal(u.literalMessage, null, 'a message built at runtime cannot be known from source');
});

test('UT-REG-03 ignores codes that only appear in comments', () => {
  assert.deepEqual(extractCodeUsages('  // E-SCHED-006 means the day is published', 'x.xs'), []);
});

test('UT-REG-04 strips the trailing code the way the catalog stores it', () => {
  assert.equal(stripCode('Give this agent a name. (E-VAL-001)'), 'Give this agent a name.');
  assert.equal(stripCode('No code here'), 'No code here');
});

// ── comparison rules ─────────────────────────────────────────────────

const FAKE: Record<string, CatalogEntry> = {
  'E-X-001': {code: 'E-X-001', feature: 'X', user_message: 'The real meaning.'},
};

test('UT-REG-05 flags a code nobody can look up', () => {
  const p = findRegistryProblems(FAKE, [{code: 'E-X-999', literalMessage: null, file: 'a.xs', line: 1}]);
  assert.equal(p.length, 1);
  assert.equal(p[0].kind, 'missing_from_catalog');
});

test('UT-REG-06 flags a code reused for a second meaning — the O4 collision', () => {
  const p = findRegistryProblems(FAKE, [
    {code: 'E-X-001', literalMessage: 'Something completely different. (E-X-001)', file: 'a.xs', line: 1},
  ]);
  assert.equal(p.length, 1);
  assert.equal(p[0].kind, 'message_conflict');
});

test('UT-REG-07 accepts a code used exactly as the catalog describes it', () => {
  const p = findRegistryProblems(FAKE, [
    {code: 'E-X-001', literalMessage: 'The real meaning. (E-X-001)', file: 'a.xs', line: 1},
  ]);
  assert.deepEqual(p, []);
});

test('UT-REG-08 flags an entry whose code field disagrees with its key', () => {
  const p = findRegistryProblems({'E-X-001': {code: 'E-X-002', feature: 'X', user_message: 'x'}}, []);
  assert.equal(p[0].kind, 'key_mismatch');
});

test('UT-REG-09 flags a logged code that disagrees with the shown one', () => {
  const src = [
    '        var.update $reject_code {',
    '          value = "E-PLAN-004"',
    '        }',
    '',
    '        var.update $reject_msg {',
    '          value = "One of those maps is not available. (E-PLAN-015)"',
    '        }',
  ].join(String.fromCharCode(10));
  const p = findCodePairingProblems(src, 'a.xs');
  assert.equal(p.length, 1, JSON.stringify(p));
  assert.ok(p[0].detail.includes('E-PLAN-004'), p[0].detail);
});

test('UT-REG-10 accepts a matched pair', () => {
  const src = [
    '        var.update $reject_code {',
    '          value = "E-PLAN-015"',
    '        }',
    '',
    '        var.update $reject_msg {',
    '          value = "One of those maps is not available. (E-PLAN-015)"',
    '        }',
  ].join(String.fromCharCode(10));
  assert.deepEqual(findCodePairingProblems(src, 'a.xs'), []);
});

// ── the guard itself ─────────────────────────────────────────────────

function toRepoPath(f: string): string {
  return path.relative(REPO_ROOT, f).split(path.sep).join('/');
}

function xsFiles(dir: string): string[] {
  const abs = path.join(REPO_ROOT, dir);
  if (!fs.existsSync(abs)) return [];
  const out: string[] = [];
  for (const entry of fs.readdirSync(abs, {withFileTypes: true, recursive: true}) as unknown as fs.Dirent[]) {
    if (entry.isFile() && entry.name.endsWith('.xs')) {
      // `parentPath` on newer Node, `path` on older.
      const parent = (entry as unknown as {parentPath?: string; path?: string}).parentPath ?? (entry as unknown as {path: string}).path;
      out.push(path.join(parent, entry.name));
    }
  }
  return out;
}

test('GUARD-REG-01 every error code the backend emits means exactly one thing', () => {
  const files = [...xsFiles('apis'), ...xsFiles('functions')];
  assert.ok(files.length > 50, `expected to find the backend sources, found ${files.length}`);

  const usages = files.flatMap((f) =>
    extractCodeUsages(fs.readFileSync(f, 'utf8'), path.relative(REPO_ROOT, f).replace(/\\/g, '/')),
  );
  assert.ok(usages.length > 20, `expected to find error codes in the backend, found ${usages.length}`);

  const problems = [
    ...findRegistryProblems(catalog, usages),
    ...files.flatMap((f) =>
      findCodePairingProblems(fs.readFileSync(f, 'utf8'), toRepoPath(f)),
    ),
  ];
  const checkable = usages.filter((u) => u.literalMessage !== null).length;

  assert.deepEqual(
    problems,
    [],
    `\n${problems.length} error-code problem(s) across ${usages.length} usages ` +
      `(${checkable} with a comparable literal message):\n` +
      problems.map((p) => `  [${p.kind}] ${p.code} — ${p.detail}`).join('\n') +
      '\n',
  );
});
