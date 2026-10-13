import assert from 'node:assert/strict';
import test from 'node:test';
import {fieldRules, validateRegistryShape} from './fieldRules';
import {errorCatalog} from '../ops/errorCatalog';

test('UT-VAL-1-08 (registry shape): every rule key matches its entity.field, enums have values, every rule has error codes', () => {
  const problems = validateRegistryShape(fieldRules);
  assert.deepEqual(problems, []);
});

test('UT-VAL-1-08: every error code a rule can produce exists in the catalog', () => {
  const missing: string[] = [];
  for (const [key, rule] of Object.entries(fieldRules)) {
    for (const code of Object.values(rule.errorCodes)) {
      if (code && !(code in errorCatalog)) missing.push(`${key} -> ${code}`);
    }
  }
  assert.deepEqual(missing, [], `codes used by a rule but missing from the catalog: ${missing.join(', ')}`);
});

test('FT-VAL-1-06 (endpoint inventory): ops/event has a rule for every input it accepts', () => {
  const opsEventInputs = ['feature', 'step', 'outcome', 'severity', 'error_code', 'message', 'entity_type', 'entity_id', 'correlation_id', 'duration_ms'];
  for (const field of opsEventInputs) {
    assert.ok(fieldRules[`ops_event.${field}`], `missing a rule for ops_event.${field}`);
  }
});

test('FT-VAL-1-06 (endpoint inventory): feature_flag has a rule for every input it accepts', () => {
  for (const field of ['account_id', 'flag_key', 'note']) {
    assert.ok(fieldRules[`feature_flag.${field}`], `missing a rule for feature_flag.${field}`);
  }
});
