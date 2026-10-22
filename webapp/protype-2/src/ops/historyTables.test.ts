// US-DEL-1-02 — nothing deletes the record.
//
// GUARD-DEL-1-01 at the bottom is the one that matters: it scans every
// .xs file in the repo. It exists because the protection it enforces
// was, until this was written, nothing but luck.
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {findHistoryDeletes, HISTORY_TABLES, HISTORY_TABLE_NAMES, ALLOWED_DELETES} from './historyTables';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');

function toRepoPath(f: string): string {
  return path.relative(REPO_ROOT, f).split(path.sep).join('/');
}

function xsFiles(dir: string): string[] {
  const abs = path.join(REPO_ROOT, dir);
  if (!fs.existsSync(abs)) return [];
  const out: string[] = [];
  for (const entry of fs.readdirSync(abs, {withFileTypes: true, recursive: true}) as unknown as fs.Dirent[]) {
    if (entry.isFile() && entry.name.endsWith('.xs')) {
      const parent =
        (entry as unknown as {parentPath?: string; path?: string}).parentPath ??
        (entry as unknown as {path: string}).path;
      out.push(path.join(parent, entry.name));
    }
  }
  return out;
}

// ── the rule itself ──────────────────────────────────────────────────

test('UT-DEL-1-02a every history table says why in plain words', () => {
  assert.ok(HISTORY_TABLES.length >= 5);
  for (const t of HISTORY_TABLES) {
    assert.ok(t.why.length > 40, `${t.table} needs a real reason, not a label`);
  }
});

test('UT-DEL-1-02b catches a delete against a history table', () => {
  const v = findHistoryDeletes('        db.del journey_map_version {', 'a.xs');
  assert.equal(v.length, 1);
  assert.equal(v[0].table, 'journey_map_version');
  assert.ok(v[0].why.includes('instructions'), v[0].why);
});

test('UT-DEL-1-02c does not confuse journey_map with journey_map_version', () => {
  // The map itself is deletable; its versions are not. A prefix match
  // would flag the legitimate delete and get this guard switched off.
  assert.deepEqual(findHistoryDeletes('        db.del journey_map {', 'a.xs'), []);
});

test('UT-DEL-1-02d ignores a table that is only mentioned in a comment', () => {
  assert.deepEqual(findHistoryDeletes('  // never db.del journey_map_version here', 'a.xs'), []);
});

test('UT-DEL-1-02e leaves deletable link tables alone', () => {
  // planner_task_work_task is append-only in SHAPE but legitimately
  // deleted when a job step is unscheduled (O4). Shape and history are
  // different questions.
  assert.equal(HISTORY_TABLE_NAMES.has('planner_task_work_task'), false);
  assert.deepEqual(findHistoryDeletes('        db.del planner_task_work_task {', 'a.xs'), []);
});

test('UT-DEL-1-02f an allowed delete is allowed only in its own file', () => {
  const allowed = ALLOWED_DELETES[0];
  assert.deepEqual(findHistoryDeletes(`        db.del ${allowed.table} {`, allowed.file), []);
  // The same statement anywhere else is still a violation — the
  // exception is the FILE, not the table.
  assert.equal(findHistoryDeletes(`        db.del ${allowed.table} {`, 'somewhere/else.xs').length, 1);
});

test('UT-DEL-1-02g every allowed delete says why', () => {
  for (const a of ALLOWED_DELETES) {
    assert.ok(HISTORY_TABLE_NAMES.has(a.table), `${a.table} is not a history table`);
    assert.ok(a.why.length > 40, `${a.file} needs a real reason`);
  }
});

// ── the guard ────────────────────────────────────────────────────────

test('GUARD-DEL-1-01 nothing in the backend deletes the record', () => {
  const files = [...xsFiles('apis'), ...xsFiles('functions'), ...xsFiles('tasks')];
  assert.ok(files.length > 50, `expected to find the backend sources, found ${files.length}`);

  const violations = files.flatMap((f) => findHistoryDeletes(fs.readFileSync(f, 'utf8'), toRepoPath(f)));

  assert.deepEqual(
    violations,
    [],
    '\nSomething deletes a table that holds the record:\n' +
      violations.map((v) => `  ${v.file}:${v.line}  db.del ${v.table}\n      ${v.why}`).join('\n') +
      '\n',
  );
});
