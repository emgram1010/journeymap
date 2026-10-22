// O14 (2026-10-17) — One signed-in session for every spec.
//
// THE PROBLEM THIS FIXES. 26 of the 35 Playwright specs had been
// failing for some time, every one of them on the sign-in page, and
// the reason was not one broken fixture — it was that there was no
// fixture at all:
//
//   - Most specs (cell-identifiers, chat-*, internal-actor, seed-map-
//     data, ai-*) just call `page.goto('/')` and assume they land in
//     the app. They were written before the app had auth, and have
//     been landing on /login ever since.
//   - One spec (health-page) grew its own inline form login with a
//     hardcoded email and password.
//   - The three specs written most recently each hand-rolled token
//     injection into localStorage.
//
// Three different answers, two of which never worked. This is the one
// answer: a `storageState` built once, before any spec runs, and
// applied by `playwright.config.ts` to every page in the suite. The
// specs themselves need no login code at all.
//
// NO PASSWORD ANYWHERE. The session comes from a bearer token in
// `E2E_AUTH_TOKEN`, which is how the three working specs already did
// it. Getting one needs no password either — run
// `Getting Started Template/generate_magic_link` for the test user and
// POST the token it returns to `reset/magic-link-login` (CLAUDE.md
// documents this; a token minted directly by `security.create_auth_token`
// is rejected by the live API).
//
// WITHOUT A TOKEN, NOTHING PRETENDS TO PASS. An empty state is written
// and every spec lands on /login exactly as it does today — the suite
// stays honestly red rather than silently green. The message below is
// printed once so the cause is never a mystery again.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const STORAGE_STATE = path.join(HERE, '.auth', 'state.json');

/** The app reads both of these on boot (`AuthContext`, `xano.ts::getAuthToken`). */
function stateFor(token: string | undefined, origin: string) {
  if (!token) return {cookies: [], origins: []};
  return {
    cookies: [],
    origins: [
      {
        origin,
        localStorage: [{name: 'authToken', value: token}],
      },
    ],
  };
}

export default async function globalSetup() {
  const token = process.env.E2E_AUTH_TOKEN ?? process.env.PERFORM_TEST_AUTH_TOKEN;
  const origin = process.env.E2E_BASE_URL ?? 'http://localhost:3000';

  fs.mkdirSync(path.dirname(STORAGE_STATE), {recursive: true});
  fs.writeFileSync(STORAGE_STATE, JSON.stringify(stateFor(token, origin), null, 2));

  if (!token) {
    console.warn(
      '\n[e2e] No E2E_AUTH_TOKEN set — every spec will land on the sign-in page.\n' +
        '      Generate one with a magic link (no password needed):\n' +
        '        1. run the Xano function "Getting Started Template/generate_magic_link" for the test user\n' +
        '        2. POST {magic_token, email} to  <auth base>/reset/magic-link-login\n' +
        '        3. export E2E_AUTH_TOKEN=<the authToken it returns>\n',
    );
  }
}
