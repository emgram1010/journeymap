import assert from 'node:assert/strict';
import {readdirSync, readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {loginProblem} from './connectionsModel';

// COP-6 story 02 - logins are write-only and encrypted. Founder decision 2026-11-16: encrypted in Xano.
// These read the source files, so a later edit that quietly leaks a login fails here. Live behaviour
// is proven by product/stories/Epic-23/tests/cop6_login_probe.py.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');
const ENDPOINT = 'apis/members_accounts/659_copilot_connection_login_POST.xs';

test('COP-6-02: the login rule matches the server (E-COP-068) and never trims the value', () => {
  assert.match(loginProblem('') ?? '', /E-COP-068/);
  assert.match(loginProblem('   ') ?? '', /E-COP-068/);
  assert.match(loginProblem('x'.repeat(4001)) ?? '', /E-COP-068/);
  assert.equal(loginProblem(' key-with-spaces '), null);
  assert.equal(loginProblem('x'.repeat(4000)), null);
});

test('COP-6-02: the login input is marked sensitive, so request history masks it', () => {
  assert.match(read(ENDPOINT), /text login\? \{\s*sensitive = true\s*\}/);
  assert.match(read('functions/copilot/login_seal.xs'), /text value\? \{\s*sensitive = true\s*\}/);
});

test('COP-6-02: the endpoint answers only whether a login is stored, and never logs the value', () => {
  const src = read(ENDPOINT);
  const resp = src.slice(src.indexOf('response = {'));
  assert.ok(!/[^_]login:/.test(resp) && !resp.includes('$sealed') && !resp.includes('$input.login'), 'no login in the response');
  for (const call of src.match(/function\.run "ops\/log_event" \{[\s\S]*?\} as \$\w+/g) ?? []) {
    assert.ok(!call.includes('$input.login') && !call.includes('$sealed'), 'no login in an event');
  }
  assert.ok(src.includes('secret_value: $sealed'), 'only the sealed value is stored');
  assert.ok(!src.includes('secret_value: $input.login'), 'the plain login is never stored');
});

test('COP-6-02: sealing needs a real key from the environment, never the database', () => {
  const seal = read('functions/copilot/login_seal.xs');
  assert.ok(seal.includes('$env.COPILOT_SECRET_KEY'));
  assert.match(seal, /\(\$key\|strlen\) >= 32/, 'a short or missing key stores nothing');
  assert.ok(seal.includes('jwe_encode:{}:$key:"A256KW":"A256GCM"'), 'authenticated encryption');
  const src = read(ENDPOINT);
  assert.match(src, /precondition \(\$key_missing == false\)/, 'E-COP-067 stops the save');
  assert.ok(src.indexOf('outcome: "failure"') < src.indexOf('precondition ($key_missing == false)'), 'the refusal is logged first');
});

test('COP-6-02: removing deletes the login and switches the connection off in one transaction', () => {
  const src = read(ENDPOINT);
  const tx = src.slice(src.indexOf('db.transaction {'));
  assert.ok(tx.includes('db.del copilot_connection_secret'));
  assert.ok(tx.includes('data = {is_on: false'));
});

test('COP-6-02: opening a login is server-only and answers nothing on a failure', () => {
  const open = read('functions/copilot/login_open.xs');
  assert.ok(open.includes('value: (($code == "") ? $value : "")'));
  assert.ok(open.includes('"E-COP-069"'));
  // No endpoint calls it: an endpoint that did could hand the value back. Connection tools (story 03)
  // may call it, and must attach the value to the outgoing request only.
  for (const group of readdirSync(repo('apis'))) {
    for (const f of readdirSync(repo(`apis/${group}`)).filter((n) => n.endsWith('.xs'))) {
      assert.ok(!read(`apis/${group}/${f}`).includes('copilot/login_open'), `${group}/${f} must not open a login`);
    }
  }
  const catalog = JSON.parse(read('webapp/protype-2/src/ops/errorCatalog.json'));
  for (const code of ['E-COP-067', 'E-COP-068', 'E-COP-069']) assert.ok(catalog[code], `${code} is in the catalog`);
});
