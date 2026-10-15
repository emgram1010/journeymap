import {defineConfig} from '@playwright/test';

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
  timeout: 60_000,
  expect: {timeout: 10_000},
  fullyParallel: false,
  retries: 0,
  use: {
    baseURL: 'http://localhost:3000',
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
