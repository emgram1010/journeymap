import assert from 'node:assert/strict';
import test from 'node:test';
import {fingerprint} from './fingerprint';

test('UT-OBS-1-04: same feature/step/code always produces the same fingerprint', () => {
  const a = fingerprint({feature: 'PUB-1', step: 'publish_version', errorCode: 'E-PUB-001'});
  const b = fingerprint({feature: 'PUB-1', step: 'publish_version', errorCode: 'E-PUB-001'});
  assert.equal(a, b);
});

test('fingerprint is stable regardless of extra surrounding context', () => {
  const direct = fingerprint({feature: 'LOG-1', step: 'record_event', errorCode: 'E-LOG-002'});
  const fromEventObject = fingerprint({
    feature: 'LOG-1',
    step: 'record_event',
    errorCode: 'E-LOG-002',
    // @ts-expect-error — extra fields on the input object must not affect the result
    unrelatedField: 'anything',
  });
  assert.equal(direct, fromEventObject);
});

test('missing error code falls back to "none"', () => {
  assert.equal(fingerprint({feature: 'OBS-1', step: 'heartbeat'}), 'OBS-1::heartbeat::none');
  assert.equal(fingerprint({feature: 'OBS-1', step: 'heartbeat', errorCode: null}), 'OBS-1::heartbeat::none');
});

test('different inputs produce different fingerprints', () => {
  const a = fingerprint({feature: 'PUB-1', step: 'publish_version', errorCode: 'E-PUB-001'});
  const b = fingerprint({feature: 'PUB-1', step: 'publish_version', errorCode: 'E-PUB-002'});
  const c = fingerprint({feature: 'PUB-1', step: 'readiness_check', errorCode: 'E-PUB-001'});
  assert.notEqual(a, b);
  assert.notEqual(a, c);
});
