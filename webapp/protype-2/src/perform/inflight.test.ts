import assert from 'node:assert/strict';
import test from 'node:test';
import {createInflight} from './inflight';

const deferred = <T>() => {
  let resolve!: (v: T) => void;
  let reject!: (e: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return {promise, resolve, reject};
};

test('UT-PERF-1-04-01: two callers asking for the same key while it is in flight share ONE request', async () => {
  const share = createInflight<string>();
  let runs = 0;
  const d = deferred<string>();
  const run = () => {
    runs += 1;
    return d.promise;
  };
  const a = share('GET /workspace/43/board', run);
  const b = share('GET /workspace/43/board', run);
  d.resolve('board');
  assert.equal(await a, 'board');
  assert.equal(await b, 'board');
  assert.equal(runs, 1);
});

test('UT-PERF-1-04-02: nothing is cached — once a request settles, the next ask goes to the network again', async () => {
  const share = createInflight<string>();
  let runs = 0;
  const run = () => {
    runs += 1;
    return Promise.resolve(`response-${runs}`);
  };
  assert.equal(await share('k', run), 'response-1');
  assert.equal(await share('k', run), 'response-2');
  assert.equal(runs, 2);
});

test('UT-PERF-1-04-03: different keys never share (a different URL, or a different signed-in user)', async () => {
  const share = createInflight<string>();
  let runs = 0;
  const run = () => {
    runs += 1;
    return Promise.resolve('x');
  };
  await Promise.all([share('GET /a\ntoken-1', run), share('GET /b\ntoken-1', run), share('GET /a\ntoken-2', run)]);
  assert.equal(runs, 3);
});

test('UT-PERF-1-04-04: a failure reaches every sharing caller, and the next ask retries instead of reusing it', async () => {
  const share = createInflight<string>();
  let runs = 0;
  const d = deferred<string>();
  const failingRun = () => {
    runs += 1;
    return d.promise;
  };
  const a = share('k', failingRun);
  const b = share('k', failingRun);
  d.reject(new Error('offline'));
  await assert.rejects(a, /offline/);
  await assert.rejects(b, /offline/);
  const retry = await share('k', () => {
    runs += 1;
    return Promise.resolve('ok');
  });
  assert.equal(retry, 'ok');
  assert.equal(runs, 2);
});
