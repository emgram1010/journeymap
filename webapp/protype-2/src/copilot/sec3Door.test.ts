import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// SEC-3 stories 05 and 06 - refusals are visible but cannot flood the log, and a nightly check
// proves the AI tool door is still shut. Live proof is in EPIC-SEC-3 section 7.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

test('SEC-3-05: a refused caller is logged at most 5 times per reason per hour, never with the token', () => {
  const src = read('functions/usr/mcp_caller.xs');
  const block = src.slice(src.indexOf('var $log_refusal'));
  assert.match(block, /\$cutoff \{\s*value = \$now_ms - 3600000/);
  assert.match(block, /return = \{type: "count"\}[\s\S]*?\} as \$recent/);
  assert.match(block, /if \(\$recent < 5\)/);
  const call = block.slice(block.indexOf('function.run "ops/log_event"'));
  assert.ok(!call.includes('$token') && !call.includes('$input.authorization') && !call.includes('$input.uri'), 'no token, header or address');
  assert.ok(!block.includes('redis.'), 'no redis on this plan');
});

test('SEC-3-06: the nightly audit runs the door check, which has three honest answers', () => {
  assert.ok(read('tasks/19_ops_integrity_audit.xs').includes('function.run "ops/mcp_door_check"'));
  const check = read('functions/ops/mcp_door_check.xs');
  for (const code of ['E-SEC-021', 'E-SEC-022']) assert.ok(check.includes(`"${code}"`));
  assert.ok(!/Authorization|token=/.test(check.slice(check.indexOf('stack {'))), 'the check never sends a token');
  const catalog = JSON.parse(read('webapp/protype-2/src/ops/errorCatalog.json'));
  for (const code of ['E-SEC-020', 'E-SEC-021', 'E-SEC-022']) assert.ok(catalog[code], `${code} is in the catalog`);
});
