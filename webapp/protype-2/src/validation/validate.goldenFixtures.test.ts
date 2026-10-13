// VAL-1 (US-VAL-1-10) — Proves the frontend's validate() and the
// backend's validate_field.xs behave the same way, by recording what
// the frontend produces for a shared set of cases. These expectations
// were also run directly against the live function
// (runWorkspaceFunction, 2026-10-13) and matched exactly — see the
// epic's Test Results for the session transcript. There is no CI
// pipeline that calls the live backend automatically (that needs an
// authenticated Xano call this repo doesn't have a runner for), so
// this file is the frontend half: it locks in the fixtures so a future
// change to validate.ts that disagrees with the already-verified
// backend behaviour fails loudly, right here.
import assert from 'node:assert/strict';
import test from 'node:test';
import {validate, type FieldRule} from './validate';

interface GoldenCase {
  label: string;
  raw: string;
  rule: FieldRule;
  expected: {ok: boolean; value?: string | number; code?: string};
}

const GOLDEN_CASES: GoldenCase[] = [
  {
    label: 'empty required text',
    raw: '',
    rule: {entity: 't', field: 'name', label: 'Name', type: 'text', required: true, errorCodes: {required: 'E-VAL-001'}},
    expected: {ok: false, code: 'E-VAL-001'},
  },
  {
    label: 'over-length text',
    raw: 'abcdef',
    rule: {entity: 't', field: 'name', label: 'Name', type: 'text', required: true, maxLength: 5, errorCodes: {tooLong: 'E-VAL-002'}},
    expected: {ok: false, code: 'E-VAL-002'},
  },
  {
    label: 'html in text',
    raw: '<script>alert(1)</script>',
    rule: {entity: 't', field: 'name', label: 'Name', type: 'text', required: true, noHtml: true, errorCodes: {html: 'E-VAL-005'}},
    expected: {ok: false, code: 'E-VAL-005'},
  },
  {
    label: 'enum not allowed',
    raw: 'maybe',
    rule: {entity: 't', field: 'outcome', label: 'Outcome', type: 'enum', required: true, allowedValues: ['success', 'rejected', 'failure'], errorCodes: {notAllowed: 'E-VAL-004'}},
    expected: {ok: false, code: 'E-VAL-004'},
  },
  {
    label: 'enum allowed',
    raw: 'success',
    rule: {entity: 't', field: 'outcome', label: 'Outcome', type: 'enum', required: true, allowedValues: ['success', 'rejected', 'failure'], errorCodes: {}},
    expected: {ok: true, value: 'success'},
  },
  {
    label: 'int with trailing letters',
    raw: '12abc',
    rule: {entity: 't', field: 'id', label: 'Entity id', type: 'int', required: true, errorCodes: {invalid: 'E-VAL-003'}},
    expected: {ok: false, code: 'E-VAL-003'},
  },
  {
    label: 'int below min',
    raw: '-1',
    rule: {entity: 't', field: 'id', label: 'Entity id', type: 'int', required: true, min: 0, errorCodes: {outOfRange: 'E-VAL-003'}},
    expected: {ok: false, code: 'E-VAL-003'},
  },
  {
    label: 'int in range',
    raw: '42',
    rule: {entity: 't', field: 'id', label: 'Entity id', type: 'int', required: true, min: 0, errorCodes: {}},
    expected: {ok: true, value: 42},
  },
];

for (const c of GOLDEN_CASES) {
  test(`UT-VAL-1-10 golden fixture (also verified live against validate_field.xs, 2026-10-13): ${c.label}`, () => {
    const result = validate(c.raw, c.rule);
    assert.equal(result.ok, c.expected.ok);
    if (result.ok && c.expected.value !== undefined) assert.equal(result.value, c.expected.value);
    if (!result.ok && c.expected.code !== undefined) assert.equal(result.code, c.expected.code);
  });
}
