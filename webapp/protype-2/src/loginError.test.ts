import {test} from 'node:test';
import assert from 'node:assert/strict';
import {loginErrorMessage, GENERIC_LOGIN_ERROR} from './loginError';

// SEC-2 (US-SEC-2-04). The login form used to answer every failure with
// "Invalid email or password." — correct for a wrong password, and wrong for
// somebody whose password is right but who has been switched off: they would
// retype it forever. Only refusals the server deliberately explains are shown;
// everything else stays generic, so the form never confirms an email exists.

const SWITCHED_OFF = 'This account has been switched off. Ask your admin to turn it back on. (E-USR-005)';

test('a switched-off person sees the server\'s own sentence', () => {
  assert.equal(loginErrorMessage({serverMessage: SWITCHED_OFF}), SWITCHED_OFF);
});

test('the code is found in the technical message when serverMessage is missing', () => {
  const technical = `Xano POST /auth/login failed (403): {"code":"ERROR_CODE_ACCESS_DENIED","message":"${SWITCHED_OFF}"}`;
  assert.equal(loginErrorMessage({serverMessage: null, message: technical}), SWITCHED_OFF);
});

test('a wrong password stays generic', () => {
  assert.equal(loginErrorMessage({serverMessage: 'Invalid Credentials.'}), GENERIC_LOGIN_ERROR);
});

test('an unknown code stays generic — only listed codes are ever shown', () => {
  assert.equal(loginErrorMessage({serverMessage: 'Something internal. (E-XYZ-999)'}), GENERIC_LOGIN_ERROR);
});

test('a network failure, a string, null and undefined all stay generic', () => {
  assert.equal(loginErrorMessage(new TypeError('Failed to fetch')), GENERIC_LOGIN_ERROR);
  assert.equal(loginErrorMessage('boom'), GENERIC_LOGIN_ERROR);
  assert.equal(loginErrorMessage(null), GENERIC_LOGIN_ERROR);
  assert.equal(loginErrorMessage(undefined), GENERIC_LOGIN_ERROR);
});
