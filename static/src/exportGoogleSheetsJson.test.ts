// US-GSE-1-04 — Pure-builder unit tests. No DOM, no network.
// Locks the spreadsheet contract: every row carries the exact same keys in the
// same order, multi-values flatten with " • ", duplicate lens labels get
// disambiguated, and empty cells fall back to flattened actorFields.

import assert from 'node:assert/strict';
import test from 'node:test';
import {
  APPS_SCRIPT_IMPORT_CODE,
  buildGoogleSheetsRows,
  serializeGoogleSheetsJson,
} from './exportGoogleSheetsJson';
import type {Lens, MatrixCell, Stage} from './types';

const stage = (id: string, label: string, extra: Partial<Stage> = {}): Stage => ({
  id, label, displayOrder: Number(id.replace(/\D/g, '')) || 0, ...extra,
});
const lens = (id: string, label: string, extra: Partial<Lens> = {}): Lens => ({
  id, label, displayOrder: Number(id.replace(/\D/g, '')) || 0, ...extra,
});
const cell = (stageId: string, lensId: string, content: string, extra: Partial<MatrixCell> = {}): MatrixCell => ({
  id: `${stageId}-${lensId}`, stageId, lensId, content, status: 'draft', ...extra,
});

test('every row has the exact same keys in the same order', () => {
  const rows = buildGoogleSheetsRows({
    mapTitle: 'Test',
    stages: [stage('s1', 'Awareness'), stage('s2', 'Consideration')],
    lenses: [lens('l1', 'Customer'), lens('l2', 'Internal')],
    cells: [cell('s1', 'l1', 'hello')],
  });
  assert.equal(rows.length, 2);
  const keys = Object.keys(rows[0]);
  for (const r of rows) assert.deepEqual(Object.keys(r), keys, 'key order must be identical across rows');
  assert.deepEqual(keys, ['Map', 'Stage #', 'Stage', 'Stage Goal', 'Owned By', 'Customer', 'Internal']);
});

test('empty cells render as em-dash, populated cells carry trimmed content', () => {
  const rows = buildGoogleSheetsRows({
    mapTitle: 'M',
    stages: [stage('s1', 'A')],
    lenses: [lens('l1', 'Customer'), lens('l2', 'Internal')],
    cells: [cell('s1', 'l1', '  trimmed  ')],
  });
  assert.equal(rows[0]['Customer'], 'trimmed');
  assert.equal(rows[0]['Internal'], '—');
});

test('actorFields fallback flattens with " • " when content is empty', () => {
  const rows = buildGoogleSheetsRows({
    mapTitle: 'M',
    stages: [stage('s1', 'A')],
    lenses: [lens('l1', 'Customer')],
    cells: [cell('s1', 'l1', '', {actorFields: {emotions: 'anxious', friction_points: 'slow login', empty: null}})],
  });
  assert.equal(rows[0]['Customer'], 'Emotions: anxious • Friction Points: slow login');
});

test('actorFields fallback drops numeric _value mirror fields', () => {
  const rows = buildGoogleSheetsRows({
    mapTitle: 'M',
    stages: [stage('s1', 'A')],
    lenses: [lens('l1', 'Financial')],
    cells: [cell('s1', 'l1', '', {actorFields: {revenue_at_risk: '$10k', revenue_at_risk_value: 10000}})],
  });
  assert.equal(rows[0]['Financial'], 'Revenue At Risk: $10k');
});

test('duplicate lens labels are disambiguated with (2), (3)', () => {
  const rows = buildGoogleSheetsRows({
    mapTitle: 'M',
    stages: [stage('s1', 'A')],
    lenses: [lens('l1', 'Internal'), lens('l2', 'Internal'), lens('l3', 'Internal')],
    cells: [cell('s1', 'l1', 'one'), cell('s1', 'l2', 'two'), cell('s1', 'l3', 'three')],
  });
  assert.deepEqual(Object.keys(rows[0]).slice(-3), ['Internal', 'Internal (2)', 'Internal (3)']);
  assert.equal(rows[0]['Internal'], 'one');
  assert.equal(rows[0]['Internal (2)'], 'two');
  assert.equal(rows[0]['Internal (3)'], 'three');
});

test('Owned By resolves primary_actor_lens key to lens label, falls back to dash', () => {
  const rows = buildGoogleSheetsRows({
    mapTitle: 'M',
    stages: [
      stage('s1', 'A', {primaryActorLens: 'customer-key', stageGoal: 'Sign up'}),
      stage('s2', 'B'),
    ],
    lenses: [lens('l1', 'Customer', {key: 'customer-key'})],
    cells: [],
  });
  assert.equal(rows[0]['Owned By'], 'Customer');
  assert.equal(rows[0]['Stage Goal'], 'Sign up');
  assert.equal(rows[1]['Owned By'], '—');
  assert.equal(rows[1]['Stage Goal'], '—');
});

test('stages are emitted in displayOrder regardless of input order', () => {
  const rows = buildGoogleSheetsRows({
    mapTitle: 'M',
    stages: [stage('s3', 'Third', {displayOrder: 3}), stage('s1', 'First', {displayOrder: 1}), stage('s2', 'Second', {displayOrder: 2})],
    lenses: [lens('l1', 'X')],
    cells: [],
  });
  assert.deepEqual(rows.map((r) => r['Stage']), ['First', 'Second', 'Third']);
  assert.deepEqual(rows.map((r) => r['Stage #']), ['1', '2', '3']);
});

test('serializeGoogleSheetsJson produces valid JSON that round-trips', () => {
  const rows = buildGoogleSheetsRows({
    mapTitle: 'M',
    stages: [stage('s1', 'Stage "with" quotes\nand newline')],
    lenses: [lens('l1', 'Customer')],
    cells: [cell('s1', 'l1', 'value with \\backslash and "quotes"')],
  });
  const json = serializeGoogleSheetsJson(rows);
  const parsed = JSON.parse(json) as Record<string, string>[];
  assert.deepEqual(parsed, rows);
});

test('APPS_SCRIPT_IMPORT_CODE includes importJSON entrypoint and formatting calls', () => {
  assert.match(APPS_SCRIPT_IMPORT_CODE, /function importJSON\(\)/);
  assert.match(APPS_SCRIPT_IMPORT_CODE, /function writeJSON\(jsonText\)/);
  assert.match(APPS_SCRIPT_IMPORT_CODE, /showModalDialog/);
  assert.match(APPS_SCRIPT_IMPORT_CODE, /google\.script\.run/);
  assert.doesNotMatch(APPS_SCRIPT_IMPORT_CODE, /ui\.prompt\(/);
  assert.match(APPS_SCRIPT_IMPORT_CODE, /setFrozenRows\(1\)/);
  assert.match(APPS_SCRIPT_IMPORT_CODE, /setFontWeight\('bold'\)/);
  assert.match(APPS_SCRIPT_IMPORT_CODE, /setWrap\(true\)/);
  assert.match(APPS_SCRIPT_IMPORT_CODE, /autoResizeColumn/);
});

test('handles zero stages and zero lenses gracefully', () => {
  assert.deepEqual(buildGoogleSheetsRows({mapTitle: 'M', stages: [], lenses: [], cells: []}), []);
  const rows = buildGoogleSheetsRows({mapTitle: 'M', stages: [stage('s1', 'A')], lenses: [], cells: []});
  assert.equal(rows.length, 1);
  assert.deepEqual(Object.keys(rows[0]), ['Map', 'Stage #', 'Stage', 'Stage Goal', 'Owned By']);
});
