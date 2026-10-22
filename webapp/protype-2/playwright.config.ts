import {defineConfig} from '@playwright/test';
import {STORAGE_STATE} from './e2e/global-setup';

// FOUND 2026-10-15 (APP-1/E2E-1): this pointed at 5173 (Vite's
// historical default), but package.json's own `dev` script hardcodes
// `--port=3000`. `webServer` was checking a port the dev server never
// actually binds, so `npx playwright test` could never reliably find
// or start it from a clean state — an inconclusive run of an existing
// spec was the first sign of this. Pointed at the port the app
// actually runs on, rather than changing the dev script (which other
// tooling may depend on).
export default defineConfig({
  testDir: './e2e',
  // O14 — one signed-in session for the whole suite, built once before
  // anything runs. 26 specs had been failing on the sign-in page
  // because there was no shared fixture at all: most assumed the app
  // had no auth, one grew its own form login, and the three newest
  // each hand-rolled token injection. See e2e/global-setup.ts.
  globalSetup: './e2e/global-setup.ts',
  timeout: 60_000,
  expect: {timeout: 10_000},
  fullyParallel: false,
  // O14 — ONE worker. `fullyParallel: false` only serialises tests
  // WITHIN a file; separate files still ran concurrently, and once the
  // auth fixture let all 35 specs actually boot the app they overwhelmed
  // a single dev server and a single live Xano workspace. The app's own
  // boot check (`AuthContext` → `/auth/me`) clears the stored token when
  // it fails, so the symptom was specs landing back on the sign-in page
  // — the very thing the fixture had just fixed. Serial is the honest
  // setting for a suite sharing one backend.
  workers: 1,
  retries: 0,
  use: {
    baseURL: 'http://localhost:3000',
    storageState: STORAGE_STATE,
    headless: true,
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'npm run dev',
    port: 3000,
    reuseExistingServer: true,
    timeout: 30_000,
  },
});
