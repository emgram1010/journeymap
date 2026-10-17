import assert from 'node:assert/strict';
import test from 'node:test';
import {validate, validateRangeOrder, type FieldRule} from './validate';
import {TEXT_JUNK_CASES, NUMBER_JUNK_CASES, INVALID_DATES, VALID_DATES} from './junkCorpus';

const REQUIRED_TEXT: FieldRule = {
  entity: 'test',
  field: 'name',
  label: 'Name',
  type: 'text',
  required: true,
  maxLength: 10000,
  normalize: ['trim'],
  errorCodes: {required: 'E-VAL-001', tooLong: 'E-VAL-002'},
};

test('UT-VAL-1-01: normalize collapses spaces, strips control and zero-width characters', () => {
  const rule: FieldRule = {...REQUIRED_TEXT, normalize: ['trim', 'collapseSpaces', 'stripControl']};
  const result = validate('  hello\u0000   world​  ', rule);
  assert.deepEqual(result, {ok: true, value: 'hello world'});
});

test('UT-VAL-1-02: a required field rejects every empty/whitespace case with the field\'s code', () => {
  for (const value of ['', '   ', '\t\n\t']) {
    const result = validate(value, REQUIRED_TEXT);
    assert.equal(result.ok, false);
    if (!result.ok) assert.equal(result.code, 'E-VAL-001');
  }
});

test('UT-VAL-1-03: over-length by one character is rejected; the exact limit is accepted', () => {
  const rule: FieldRule = {...REQUIRED_TEXT, maxLength: 5};
  const atLimit = validate('abcde', rule);
  assert.equal(atLimit.ok, true);
  const overLimit = validate('abcdef', rule);
  assert.equal(overLimit.ok, false);
  if (!overLimit.ok) assert.equal(overLimit.code, 'E-VAL-002');
});

test('UT-VAL-1-04: HTML in a name is rejected', () => {
  const rule: FieldRule = {...REQUIRED_TEXT, noHtml: true, errorCodes: {...REQUIRED_TEXT.errorCodes, html: 'E-VAL-005'}};
  const script = validate('<script>alert(1)</script>', rule);
  assert.equal(script.ok, false);
  const bold = validate('<b>bold</b>', rule);
  assert.equal(bold.ok, false);
  const clean = validate('Sales Coordinator', rule);
  assert.equal(clean.ok, true);
});

test('UT-VAL-1-05: enum accepts a listed value and rejects one that is not listed', () => {
  const rule: FieldRule = {
    entity: 'test',
    field: 'outcome',
    label: 'Outcome',
    type: 'enum',
    required: true,
    allowedValues: ['success', 'rejected', 'failure'],
    errorCodes: {required: 'E-VAL-001', notAllowed: 'E-VAL-004'},
  };
  assert.equal(validate('success', rule).ok, true);
  const bad = validate('maybe', rule);
  assert.equal(bad.ok, false);
  if (!bad.ok) assert.equal(bad.code, 'E-VAL-004');
});

test('UT-VAL-1-06: integer rules over the number junk corpus', () => {
  const rule: FieldRule = {entity: 't', field: 'n', label: 'N', type: 'int', required: true, errorCodes: {required: 'E-VAL-001', invalid: 'E-VAL-003'}};
  for (const c of NUMBER_JUNK_CASES) {
    const result = validate(c.raw, rule);
    if (c.expectedValid === null) {
      assert.equal(result.ok, false, `${c.label} (${c.raw}) should be rejected`);
    } else if (Number.isInteger(c.expectedValid)) {
      assert.deepEqual(result, {ok: true, value: c.expectedValid}, `${c.label} (${c.raw})`);
    } else {
      // A decimal like 1.5 is not a valid INTEGER, even though it parses as a number.
      assert.equal(result.ok, false, `${c.label} (${c.raw}) is not a whole number`);
    }
  }
});

test('decimal rules accept the same corpus\'s fractional values', () => {
  const rule: FieldRule = {entity: 't', field: 'n', label: 'N', type: 'decimal', required: true, errorCodes: {required: 'E-VAL-001', invalid: 'E-VAL-003'}};
  const decimalCase = NUMBER_JUNK_CASES.find((c) => c.label === 'decimal')!;
  assert.deepEqual(validate(decimalCase.raw, rule), {ok: true, value: 1.5});
});

test('UT-VAL-1-07: time HH:MM and date validity, including a leap day', () => {
  const timeRule: FieldRule = {entity: 't', field: 'start', label: 'Start time', type: 'time', required: true, errorCodes: {required: 'E-VAL-001', invalid: 'E-VAL-003'}};
  assert.equal(validate('08:00', timeRule).ok, true);
  assert.equal(validate('23:59', timeRule).ok, true);
  assert.equal(validate('24:00', timeRule).ok, false);
  assert.equal(validate('8:00', timeRule).ok, false);
  assert.equal(validate('08:60', timeRule).ok, false);

  const dateRule: FieldRule = {entity: 't', field: 'd', label: 'Date', type: 'date', required: true, errorCodes: {required: 'E-VAL-001', invalid: 'E-VAL-003'}};
  for (const d of VALID_DATES) assert.equal(validate(d, dateRule).ok, true, `${d} should be valid`);
  for (const d of INVALID_DATES) assert.equal(validate(d, dateRule).ok, false, `${d} should be invalid`);
});

test('UT-VAL-1-09: the full text junk corpus run through a required-text rule matches its expectation', () => {
  // noHtml: true because the corpus's two HTML cases are only meant to
  // be rejected when a field opts into that check — exactly how the
  // real registry uses it (see fieldRules.json: name/title-shaped
  // fields set noHtml, a free-form notes field might not).
  const rule: FieldRule = {...REQUIRED_TEXT, noHtml: true, errorCodes: {...REQUIRED_TEXT.errorCodes, html: 'E-VAL-005'}};
  for (const c of TEXT_JUNK_CASES) {
    const result = validate(c.value, rule);
    const actual = result.ok ? 'accept' : 'reject';
    assert.equal(actual, c.expectedForRequiredText, `${c.label}: expected ${c.expectedForRequiredText}, got ${actual}`);
  }
});

test('an optional field accepts an empty value without checking length/pattern', () => {
  const optional: FieldRule = {...REQUIRED_TEXT, required: false, maxLength: 3};
  assert.deepEqual(validate('', optional), {ok: true, value: ''});
  assert.deepEqual(validate('   ', optional), {ok: true, value: ''});
});

test('validateRangeOrder rejects an inverted range and accepts an ordered one', () => {
  const inverted = validateRangeOrder('2026-02-10', '2026-02-01', 'start', 'end', 'E-VAL-003');
  assert.equal(inverted.ok, false);
  const ordered = validateRangeOrder('2026-02-01', '2026-02-10', 'start', 'end', 'E-VAL-003');
  assert.equal(ordered.ok, true);
});

test('does not mutate the rule object', () => {
  const rule = {...REQUIRED_TEXT};
  const frozen = Object.freeze({...rule});
  assert.doesNotThrow(() => validate('hello', frozen));
});
