import assert from 'node:assert/strict';
import test from 'node:test';
import {buildErrorResponse, lintErrorResponse, statusForCode} from './errorResponse';

test('buildErrorResponse produces the standard shape with nulls for omitted optionals', () => {
  const r = buildErrorResponse('E-VAL-001', 'This is required.');
  assert.deepEqual(r, {code: 'E-VAL-001', field: null, message: 'This is required.', reference: null});
});

test('buildErrorResponse carries field and reference when given', () => {
  const r = buildErrorResponse('E-VAL-002', 'Too long.', {field: 'name', reference: 'abc-123'});
  assert.deepEqual(r, {code: 'E-VAL-002', field: 'name', message: 'Too long.', reference: 'abc-123'});
});

test('FT-VAL-1-05: a clean response has no lint issues', () => {
  const issues = lintErrorResponse({code: 'E-VAL-001', field: 'name', message: 'This is required.', reference: 'abc-123'});
  assert.deepEqual(issues, []);
});

test('FT-VAL-1-05: catches a missing field in the shape', () => {
  const issues = lintErrorResponse({code: 'E-VAL-001', message: 'x', reference: null});
  assert.ok(issues.some((i) => i.field === 'field'));
});

test('FT-VAL-1-05: catches a stack-trace-shaped message', () => {
  const issues = lintErrorResponse({
    code: 'E-GOV-006',
    field: null,
    message: 'TypeError: cannot read property at Object.foo (/app/node_modules/x.js:12)',
    reference: null,
  });
  assert.ok(issues.length > 0);
});

test('FT-VAL-1-05: catches a raw Xano error_type leaking through', () => {
  const issues = lintErrorResponse({code: 'E-GOV-001', field: null, message: 'ERROR_CODE_ACCESS_DENIED', reference: null});
  assert.ok(issues.length > 0);
});

test('FT-VAL-1-05: non-object body is flagged', () => {
  assert.ok(lintErrorResponse('just a string').length > 0);
  assert.ok(lintErrorResponse(null).length > 0);
});

test('statusForCode maps the known families to the expected HTTP status', () => {
  assert.equal(statusForCode('E-GOV-005'), 409);
  assert.equal(statusForCode('E-GOV-001'), 403);
  assert.equal(statusForCode('E-OBS-001'), 403);
  assert.equal(statusForCode('E-VAL-001'), 422);
});
