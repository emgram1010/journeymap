import assert from 'node:assert/strict';
import test from 'node:test';
import {runFormValidation, isFormValid, firstError, errorCount, applyServerRejection} from './formValidation';
import type {FieldRule} from './validate';

const rules: Record<string, FieldRule> = {
  name: {entity: 't', field: 'name', label: 'Name', type: 'text', required: true, maxLength: 20, errorCodes: {required: 'E-VAL-001', tooLong: 'E-VAL-002'}},
  count: {entity: 't', field: 'count', label: 'Count', type: 'int', required: false, min: 0, errorCodes: {invalid: 'E-VAL-003'}},
};

test('a fully valid form has no errors', () => {
  const state = runFormValidation({name: 'Sales Coordinator', count: '3'}, rules);
  assert.equal(isFormValid(state), true);
  assert.equal(errorCount(state), 0);
});

test('a missing required field is reported with its message and code', () => {
  const state = runFormValidation({name: '', count: '3'}, rules);
  assert.equal(isFormValid(state), false);
  assert.equal(state.name.error, 'Name is required.');
  assert.equal(state.name.code, 'E-VAL-001');
});

test('firstError returns the first failing field in rule order', () => {
  const state = runFormValidation({name: '', count: 'abc'}, rules);
  const err = firstError(state);
  assert.equal(err?.key, 'name');
});

test('errorCount counts every failing field', () => {
  const state = runFormValidation({name: '', count: 'abc'}, rules);
  assert.equal(errorCount(state), 2);
});

test('E2E-VAL-1-01 style: user input is preserved in state.value even when invalid', () => {
  const state = runFormValidation({name: '   ', count: ''}, rules);
  assert.equal(state.name.value, '   ');
});

test('applyServerRejection sets the error on the named field without touching its value or other fields', () => {
  const state = runFormValidation({name: 'Taken Name', count: '3'}, rules);
  const updated = applyServerRejection(state, {field: 'name', code: 'E-VAL-006', message: 'That name is already used.'});
  assert.equal(updated.name.error, 'That name is already used.');
  assert.equal(updated.name.code, 'E-VAL-006');
  assert.equal(updated.name.value, 'Taken Name');
  assert.deepEqual(updated.count, state.count);
});

test('applyServerRejection with an unknown field name is a no-op', () => {
  const state = runFormValidation({name: 'x', count: '3'}, rules);
  const updated = applyServerRejection(state, {field: 'nonexistent', code: 'E-VAL-001', message: 'x'});
  assert.deepEqual(updated, state);
});

test('applyServerRejection with a null field (banner-level error) leaves all field state untouched', () => {
  const state = runFormValidation({name: 'x', count: '3'}, rules);
  const updated = applyServerRejection(state, {field: null, code: 'E-GOV-006', message: 'Something went wrong.'});
  assert.deepEqual(updated, state);
});
