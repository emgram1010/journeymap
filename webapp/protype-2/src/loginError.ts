/**
 * SEC-2 (US-SEC-2-04) — what the login form says when sign-in fails.
 *
 * Almost always the generic line: a login form must not confirm that an email
 * exists, so a wrong password and an unknown email read the same.
 *
 * The exception is a refusal the server issues AFTER the password has been
 * checked and found correct. Those carry a catalog code, and the person needs
 * to be told — "switched off" is not something retyping a password fixes.
 * Only codes listed here are ever shown; anything else stays generic, so a new
 * server message can never leak through this form by accident.
 *
 * Pure, and duck-typed on purpose: no import of `xano.ts`, so it is testable
 * without a browser and cannot create an import cycle.
 */
export const GENERIC_LOGIN_ERROR = 'Invalid email or password.';

/** Refusals that mean "your password was right, but…". PADM-2 adds E-PADM-005 here. */
const EXPLAINED_CODES = ['E-USR-005'];

export function loginErrorMessage(err: unknown): string {
  if (err == null || typeof err !== 'object') return GENERIC_LOGIN_ERROR;
  const {serverMessage, message} = err as {serverMessage?: unknown; message?: unknown};

  for (const code of EXPLAINED_CODES) {
    const tag = `(${code})`;
    if (typeof serverMessage === 'string' && serverMessage.includes(tag)) return serverMessage;
    if (typeof message === 'string' && message.includes(tag)) {
      // Fall back to the technical string: pull out the sentence that ends in the code.
      const end = message.indexOf(tag) + tag.length;
      const start = message.lastIndexOf('"', message.indexOf(tag)) + 1;
      return message.slice(start, end);
    }
  }
  return GENERIC_LOGIN_ERROR;
}
