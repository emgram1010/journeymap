import {defineConfig} from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  timeout: 60_000,
  expect: {timeout: 10_000},
  fullyParallel: false,
  retries: 0,
  use: {
    baseURL: 'http://localhost:3001',
    headless: false,
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3001',
    reuseExistingServer: true,
    timeout: 30_000,
  },
});
