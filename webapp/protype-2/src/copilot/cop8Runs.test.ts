import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {HISTORY_TABLE_NAMES} from '../ops/historyTables';

// COP-8 stories 02 and 03 - server rules that live in XanoScript. These read the source files, so a
// later edit that quietly drops a rule fails here. Live behaviour is proven in the epic's Test results.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

// ── Story 02: a deleted business gets no scheduled runs ─────────────────────

test('COP8-02: the business list leaves out soft-deleted and missing businesses before any run', () => {
  const src = read('functions/copilot/run_for_account.xs');
  assert.match(src, /db\.query journey_architecture \{\s*where = \$db\.journey_architecture\.account_id == \$input\.account_id/, 'live businesses are read for THIS account');
  assert.match(src, /db\.query journey_architecture_deleted \{/, 'soft-delete markers are read');
  assert.match(src, /var \$live_arch_ids \{\s*value = \[-1\]/, 'the live list is seeded with a sentinel (never empty)');
  assert.match(src, /var \$deleted_arch_ids \{\s*value = \[-1\]/, 'the deleted list is seeded with a sentinel (never empty)');
  const onQuery = src.match(/db\.query copilot_action_level \{\s*where = ([^\n]*)\n\s*sort/);
  assert.ok(onQuery, 'the list of switched-on businesses is one query');
  assert.ok(onQuery![1].includes('journey_architecture_id in $live_arch_ids'), 'only businesses that still exist');
  assert.ok(onQuery![1].includes('journey_architecture_id not in $deleted_arch_ids'), 'never a soft-deleted one, written `not in` (CLAUDE.md)');
  assert.ok(!/!\s*\(\$db\.copilot_action_level\.journey_architecture_id in/.test(src), 'never the broken !(... in ...) form');
  const filterAt = src.indexOf('not in $deleted_arch_ids');
  const runAt = src.indexOf('function.run "copilot/run_for_business"');
  assert.ok(filterAt > 0 && runAt > filterAt, 'the filter is applied before run_for_business is ever called');
});

test('COP8-02: the level row is kept (nothing deleted) and the skip is counted in the tick event', () => {
  const acct = read('functions/copilot/run_for_account.xs');
  assert.ok(!/db\.(del|patch) copilot_action_level/.test(acct), 'the stored level is never deleted or changed, so a restore brings it back');
  assert.match(acct, /var \$skipped_deleted \{\s*value = \$on_all_count - \$on_count/);
  assert.match(acct, /response = \{[^}]*skipped_deleted: \$skipped_deleted/);
  const tick = read('functions/copilot/scheduled_run.xs');
  assert.match(tick, /value = \$skipped_deleted \+ \$ra\.skipped_deleted/, 'every account adds its skipped count');
  const tickEvent = tick.slice(tick.indexOf('step          : "run_tick"'));
  assert.match(tickEvent, /metadata\s*: \{[^}]*skipped_deleted: \$skipped_deleted/, 'the run_tick event carries the count');
});

// ── Story 03: every refused copilot call points to its run ──────────────────

test('COP8-03: both side tables exist, hold ids only, are unique on their key and append-only', () => {
  const ticket = read('static/tables/159_copilot_run_ticket.xs');
  assert.match(ticket, /table copilot_run_ticket \{/);
  assert.match(ticket, /\{type: "btree\|unique", field: \[\{name: "tool_run_ticket_id"/);
  assert.ok(!/text ticket/.test(ticket), 'never stores the ticket text');
  const call = read('static/tables/160_tool_call_run.xs');
  assert.match(call, /table tool_call_run \{/);
  assert.match(call, /\{type: "btree\|unique", field: \[\{name: "tool_call_log_id"/);
  for (const f of ['copilot_run_id', 'pin_architecture_id']) assert.ok(call.includes(`int ${f}?`), f);
  for (const t of [ticket, call]) assert.ok(!t.includes('updated_at'), 'append-only: no updated_at');
  assert.ok(HISTORY_TABLE_NAMES.has('copilot_run_ticket'));
  assert.ok(HISTORY_TABLE_NAMES.has('tool_call_run'));
});

test('COP8-03: run_for_business links its ticket to its run right after minting, without stopping the run', () => {
  const src = read('functions/copilot/run_for_business.xs');
  assert.match(read('functions/usr/mint_tool_ticket.xs'), /response = \{[^}]*ticket_id: \$row\.id/, 'mint returns the row id');
  const mintAt = src.indexOf('function.run "usr/mint_tool_ticket"');
  const linkAt = src.indexOf('db.add copilot_run_ticket');
  const agentAt = src.indexOf('ai.agent.run');
  assert.ok(mintAt > 0 && linkAt > mintAt && agentAt > linkAt, 'mint -> link -> agent');
  assert.match(src, /data = \{copilot_run_id: \$run_id, tool_run_ticket_id: \$ticket\.ticket_id\}/);
  const linkBlock = src.slice(src.lastIndexOf('try_catch', linkAt), agentAt);
  assert.ok(linkBlock.includes('E-COP-076'), 'a failed link is logged with E-COP-076 and the run goes on');
});

test('COP8-03: refused_count counts only this run (via tool_call_run), never a parallel chat', () => {
  const src = read('functions/copilot/run_for_business.xs');
  assert.match(src, /db\.query tool_call_run \{\s*where = \$db\.tool_call_run\.copilot_run_id == \$run_id/);
  assert.match(src, /db\.query tool_call_log \{\s*where = \$db\.tool_call_log\.id in \$run_call_ids && \$db\.tool_call_log\.verdict == "refused"/);
  assert.ok(!/tool_call_log\.created_at >= \$started_ms/.test(src), 'the old time-window count is gone');
});

test('COP8-03: the gate writes the link after the audit row, never blocks, and logs E-COP-076 on failure', () => {
  const src = read('functions/journey/tool_gate.xs');
  const auditAt = src.indexOf('db.add tool_call_log');
  const linkAt = src.indexOf('db.add tool_call_run');
  const firstPrecondition = src.indexOf('precondition (');
  assert.ok(auditAt > 0 && linkAt > auditAt, 'the link comes after the audit row');
  assert.ok(linkAt < firstPrecondition, 'and before any refusal is raised, so refused calls are linked too');
  assert.match(src, /var\.update \$audit_id \{\s*value = \$_audit\.id/);
  assert.match(src, /db\.query copilot_run_ticket \{\s*where = \$db\.copilot_run_ticket\.tool_run_ticket_id == \$link_ticket_id/, 'only tickets of a scheduled run are linked');
  assert.match(src, /data = \{tool_call_log_id: \$audit_id, copilot_run_id: \$link_run_id, pin_architecture_id: \$pin\}/);
  const block = src.slice(src.indexOf('var $link_wanted'), firstPrecondition);
  assert.ok(block.includes('try_catch'), 'the whole link step is inside try_catch');
  assert.ok(block.includes('error_code    : "E-COP-076"'), 'a failure is logged, not raised');
  assert.ok(!/precondition|var\.update \$ok|var\.update \$verdict|var\.update \$code/.test(block), 'the link step never touches the verdict');
});

test('COP8-01 support: the run instruction says how to report an E-COP-075 refusal', () => {
  const src = read('functions/copilot/run_for_business.xs');
  assert.ok(src.includes('(E-COP-075), say so in your report under Failed or blocked and do not retry.'));
});
