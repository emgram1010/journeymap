import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {connectionEntryProblem, connectionStateLabel} from './connectionsModel';

// COP-6 story 01 (library + per-business switch) and the parts of 02/04 that need no login yet.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

test('COP-6: a library entry needs a short key, a name, and a short description (screen mirrors server)', () => {
  assert.equal(connectionEntryProblem('booking-tool', 'Booking tool', ''), null);
  assert.match(connectionEntryProblem('', 'Booking tool', '') ?? '', /E-COP-064/);
  assert.match(connectionEntryProblem('Booking Tool', 'Booking tool', '') ?? '', /E-COP-064/, 'lower-case letters, digits and dashes only');
  assert.match(connectionEntryProblem('booking-tool', '', '') ?? '', /E-COP-064/);
  assert.match(connectionEntryProblem('booking-tool', 'x'.repeat(81), '') ?? '', /E-COP-064/);
  assert.match(connectionEntryProblem('booking-tool', 'Booking', 'x'.repeat(301)) ?? '', /E-COP-064/);
});

test('COP-6: the screen says plainly what state a connection is in', () => {
  assert.equal(connectionStateLabel({is_on: false, has_login: false, failing_since: 0, last_ok_at: 0}), 'Off - needs a login first');
  assert.equal(connectionStateLabel({is_on: false, has_login: true, failing_since: 0, last_ok_at: 0}), 'Off');
  assert.equal(connectionStateLabel({is_on: true, has_login: true, failing_since: 0, last_ok_at: 1_800_000_000_000}), 'On');
  assert.equal(connectionStateLabel({is_on: true, has_login: true, failing_since: 1_800_000_000_000, last_ok_at: 0}), 'On - failing');
});

test('COP-6: switching on needs a working login; the server says so (governance)', () => {
  const src = read('apis/members_accounts/658_copilot_connection_switch_POST.xs');
  assert.ok(src.includes('usr/assert_team_admin'), 'account admins only');
  assert.ok(src.includes('copilot/identity_for_user'), 'never an AI identity');
  assert.ok(src.includes('E-COP-062'), 'no working login -> refused');
  assert.ok(src.includes('E-COP-035'), 'another account\'s business looks not found');
});

test('COP-6: the list never returns a login, only whether one exists', () => {
  const src = read('apis/members_accounts/656_copilot_connections_GET.xs');
  assert.ok(!src.includes('secret_value'), 'the login column is never read here');
  assert.ok(src.includes('has_login'), 'only a yes/no');
});

test('COP-6: one gate check answers "may the copilot use this connection in this business?"', () => {
  const src = read('functions/copilot/connection_reachable.xs');
  assert.ok(src.includes('E-COP-060'), 'off -> not switched on');
  assert.match(src, /journey_architecture_id == \$input\.architecture_id/, 'only the pinned business\'s switch is read');
});
