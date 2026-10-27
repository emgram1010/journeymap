// CAT-1 — Unit tests for the catalog validators. Backend twin is tested
// live in workflow_tests/29_catalog.xs (see that file's header for how,
// since it cannot be executed as a workflow_test from a session).
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  normaliseKey,
  storedKey,
  validateKey,
  validateLabel,
  validateUnit,
  validateSizeLabel,
  validateExternalRef,
} from './catalogValidation';

const __dirname = dirname(fileURLToPath(import.meta.url));

test('UT-CAT-1-01: normaliseKey slugifies a label into a key suggestion', () => {
  assert.equal(normaliseKey('Chair Resin '), 'chair-resin');
  assert.equal(normaliseKey('  6-ft Banquet Table!!'), '6-ft-banquet-table');
  assert.equal(normaliseKey('Oversized Tic-Tac-Toe'), 'oversized-tic-tac-toe');
  assert.equal(normaliseKey('---already-a-key---'), 'already-a-key');
  assert.equal(normaliseKey(''), '');
});

test('UT-CAT-1-01b: storedKey mirrors the table column filter (trim + lower only, no slugify)', () => {
  assert.equal(storedKey('Chair Resin '), 'chair resin');
  assert.equal(storedKey('  CHAIR-RESIN  '), 'chair-resin');
});

test('validateKey accepts a well-formed key', () => {
  assert.deepEqual(validateKey('chair-resin'), {valid: true});
  assert.deepEqual(validateKey('table-6ft'), {valid: true});
  assert.deepEqual(validateKey('ab'), {valid: true}); // minimum length
  assert.deepEqual(validateKey('a'.repeat(40)), {valid: true}); // maximum length
});

test('validateKey trims and lowercases before checking, matching the stored value', () => {
  assert.deepEqual(validateKey('  Chair-Resin  '), {valid: true});
});

test('validateLabel accepts ordinary text and rejects HTML / empty / too-long', () => {
  assert.deepEqual(validateLabel('6-ft Banquet Table'), {valid: true});
  assert.deepEqual(validateLabel(''), {valid: false, code: 'E-CAT-003'});
  assert.deepEqual(validateLabel('   '), {valid: false, code: 'E-CAT-003'});
  assert.deepEqual(validateLabel('a'.repeat(81)), {valid: false, code: 'E-CAT-003'});
  assert.deepEqual(validateLabel('<script>alert(1)</script>'), {valid: false, code: 'E-CAT-003'});
});

test('validateUnit accepts each/set/pair and rejects anything else', () => {
  assert.deepEqual(validateUnit('each'), {valid: true});
  assert.deepEqual(validateUnit('set'), {valid: true});
  assert.deepEqual(validateUnit('pair'), {valid: true});
  assert.deepEqual(validateUnit('box'), {valid: false, code: 'E-CAT-004'});
  assert.deepEqual(validateUnit(''), {valid: false, code: 'E-CAT-004'});
});

test('validateSizeLabel and validateExternalRef are optional and bounded', () => {
  assert.deepEqual(validateSizeLabel(null), {valid: true});
  assert.deepEqual(validateSizeLabel(''), {valid: true});
  assert.deepEqual(validateSizeLabel('6ft'), {valid: true});
  assert.deepEqual(validateSizeLabel('a'.repeat(21)), {valid: false, code: 'E-CAT-009'});

  assert.deepEqual(validateExternalRef(undefined), {valid: true});
  assert.deepEqual(validateExternalRef('TBL-6'), {valid: true});
  assert.deepEqual(validateExternalRef('a'.repeat(61)), {valid: false, code: 'E-CAT-010'});
  assert.deepEqual(validateExternalRef('<b>x</b>'), {valid: false, code: 'E-CAT-010'});
});

// UT-CAT-1-02 / UT-CAT-1-G01 — the junk corpus must be rejected end to end,
// field by field, with the right code every time.
test('UT-CAT-1-02 / UT-CAT-1-G01: the junk corpus is rejected with the right code', () => {
  const junkPath = join(__dirname, '..', 'fixtures', 'catalog-junk.json');
  const junk = JSON.parse(readFileSync(junkPath, 'utf8')) as {
    keys: {value: string; expectValid: boolean}[];
    labels: {value: string; expectValid: boolean}[];
    units: {value: string | null; expectValid: boolean}[];
  };

  for (const {value, expectValid} of junk.keys) {
    const result = validateKey(value);
    assert.equal(result.valid, expectValid, `key ${JSON.stringify(value)} expected valid=${expectValid}`);
    if (!expectValid) assert.equal((result as {code: string}).code, 'E-CAT-001');
  }

  for (const {value, expectValid} of junk.labels) {
    const result = validateLabel(value);
    assert.equal(result.valid, expectValid, `label ${JSON.stringify(value)} expected valid=${expectValid}`);
    if (!expectValid) assert.equal((result as {code: string}).code, 'E-CAT-003');
  }

  for (const {value, expectValid} of junk.units) {
    const result = validateUnit(value as string);
    assert.equal(result.valid, expectValid, `unit ${JSON.stringify(value)} expected valid=${expectValid}`);
    if (!expectValid) assert.equal((result as {code: string}).code, 'E-CAT-004');
  }
});
