import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// COP-11 story 03 ("existing items") - the one-off kind-of-work backfill. The rules live in XanoScript;
// these tests read the source so a later edit that drops a safety rule fails here.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const src = readFileSync(repo('functions/copilot/backfill_work_kinds.xs'), 'utf8');

test('UT-COP-11-BF-01: writes need one named account; account 0 is report-only', () => {
  assert.match(src, /precondition \(\$input\.dry_run == true \|\| \$input\.account_id != 0\)/);
});

test('UT-COP-11-BF-02: it never overwrites a kind that is already set, and never deletes or retires', () => {
  assert.match(src, /\(\$has_meta == 0\) \? "add" : \(\(\$cur_kind == ""\) \? "patch" : "keep"\)/);
  assert.ok(!/db\.del\b/.test(src), 'no delete');
  assert.ok(!/db\.(add|patch) copilot_skill \{/.test(src), 'the item itself is never written');
  assert.ok(!/is_locked: true/.test(src), 'never locks anything');
});

test('UT-COP-11-BF-03: the write pass branches on the loop item and the input only', () => {
  const pass2 = src.slice(src.indexOf('// Pass 2'));
  assert.match(pass2, /if \(\$r\.action == "add" && \$input\.dry_run == false\)/);
  assert.match(pass2, /elseif \(\$r\.action == "patch" && \$input\.dry_run == false\)/);
});

test('UT-COP-11-BF-04: every kind it can choose is on the fixed list', () => {
  const chosen = [...src.matchAll(/\? "([a-z_]+)" : \$kind/g)].map((m) => m[1]).concat(['general']);
  for (const k of chosen) assert.ok(['map_building', 'planning', 'doing_work', 'research', 'general'].includes(k), k);
  assert.match(src, /copilot\.skill\.kinds_backfilled/, 'the run is logged');
});
