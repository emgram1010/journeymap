import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync, readdirSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {toMinutes, WORKDAY_MINUTES} from './durationModel';
import goldenFixtures from './fixtures/duration-golden.json';

const __dirname = dirname(fileURLToPath(import.meta.url));

test('WORKDAY_MINUTES is 480 (8 hours)', () => {
  assert.equal(WORKDAY_MINUTES, 480);
});

test('UT-TIME-1-01: 15 minutes -> 15', () => {
  assert.equal(toMinutes(15, 'minutes'), 15);
});

test('UT-TIME-1-02: 2 hours -> 120', () => {
  assert.equal(toMinutes(2, 'hours'), 120);
});

test('UT-TIME-1-03: 1 day -> 480', () => {
  assert.equal(toMinutes(1, 'days'), 480);
});

test('UT-TIME-1-04: 1 week -> 2400', () => {
  assert.equal(toMinutes(1, 'weeks'), 2400);
});

test('UT-TIME-1-05: 0.5 hours -> 30 (fractions supported)', () => {
  assert.equal(toMinutes(0.5, 'hours'), 30);
});

test('UT-TIME-1-06: 1.5 minutes -> 2 (half-up)', () => {
  assert.equal(toMinutes(1.5, 'minutes'), 2);
});

test('UT-TIME-1-07: 0 minutes -> 0 (valid, not null)', () => {
  assert.equal(toMinutes(0, 'minutes'), 0);
});

test('UT-TIME-1-08: null, undefined, "" -> null', () => {
  assert.equal(toMinutes(null, 'minutes'), null);
  assert.equal(toMinutes(undefined, 'minutes'), null);
  assert.equal(toMinutes('', 'minutes'), null);
});

test('UT-TIME-1-09: -5 minutes -> null', () => {
  assert.equal(toMinutes(-5, 'minutes'), null);
});

test('UT-TIME-1-10: unit "fortnights" -> null', () => {
  assert.equal(toMinutes(2, 'fortnights'), null);
});

test('UT-TIME-1-11: value "abc" -> null', () => {
  assert.equal(toMinutes('abc', 'minutes'), null);
});

test('a null/undefined/empty unit is rejected even with a valid value', () => {
  assert.equal(toMinutes(15, null), null);
  assert.equal(toMinutes(15, undefined), null);
  assert.equal(toMinutes(15, ''), null);
});

test('toMinutes is pure: same input always produces the same output', () => {
  assert.equal(toMinutes(3, 'hours'), toMinutes(3, 'hours'));
});

test('FT-TIME-1-01 (frontend half): every golden fixture matches', () => {
  for (const c of goldenFixtures as {label: string; value: number | string | null; unit: string | null; expected: number | null}[]) {
    assert.equal(toMinutes(c.value, c.unit), c.expected, c.label);
  }
});

// TIME-1 (FT-TIME-1-04): actual_duration is a user-entered observed baseline
// (US-TIME-1-03), not an execution actual — LOG-1/APP-1 don't exist yet, so
// nothing should be writing to it except the known map-editing path. This is
// a tripwire: when an execution module is built, it must NOT start writing
// here, and if some other new file starts touching this field, this test
// fails and forces a conscious decision instead of a silent drift.
test('FT-TIME-1-04: only the known map-editing files reference actual_duration/actualDuration', () => {
  const allowlist = new Set([
    join(__dirname, 'App.tsx'),
    join(__dirname, 'StageEditPanel.tsx'),
    join(__dirname, 'types.ts'),
    join(__dirname, 'xano.ts'),
    join(__dirname, 'durationModel.test.ts'),
  ]);

  const pattern = /actual_duration|actualDuration/;
  const offenders: string[] = [];

  for (const file of listSourceFiles(__dirname)) {
    if (allowlist.has(file)) continue;
    const content = readFileSync(file, 'utf8');
    if (pattern.test(content)) offenders.push(file);
  }

  assert.deepEqual(offenders, [], `unexpected actual_duration reference(s): ${offenders.join(', ')}`);
});

function listSourceFiles(dir: string): string[] {
  const skipDirs = new Set(['node_modules', 'dist', '.git']);
  let out: string[] = [];
  for (const entry of readdirSync(dir, {withFileTypes: true})) {
    if (entry.isDirectory()) {
      if (skipDirs.has(entry.name)) continue;
      out = out.concat(listSourceFiles(join(dir, entry.name)));
    } else if (/\.(ts|tsx)$/.test(entry.name)) {
      out.push(join(dir, entry.name));
    }
  }
  return out;
}
