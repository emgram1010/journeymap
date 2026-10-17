/**
 * health-page.spec.ts — OBS-1 (US-OBS-1-07, US-OBS-1-10)
 *
 * NOT YET RUN: like the other OBS-1 backend files, this requires the
 * OBS-1 backend (tables, functions, apis/ops/*, tasks) to actually be
 * pushed to the live Xano workspace first — ask before doing that.
 *
 * Covers the part that needs no admin test account: a logged-in,
 * non-admin user hitting /health is redirected away by AdminRoute, and
 * never sees the page or its data.
 *
 * NOT covered here (needs a decision first): "an admin sees the Health
 * page with real issues" requires ONE of the existing test accounts to
 * have is_platform_admin = true in the database. That is a founder
 * decision (it grants cross-account visibility), not something to set
 * unilaterally — write that spec once an admin test account is chosen.
 */
import {test, expect, type Page} from '@playwright/test';

const TEST_EMAIL = process.env.TEST_EMAIL ?? 'aipming51@gmail.com';
const TEST_PASSWORD = process.env.TEST_PASSWORD ?? 'Emgram2024!';

async function ensureLoggedIn(page: Page) {
  if (page.url().includes('/login') || page.url() === 'about:blank') {
    await page.goto('/');
  }
  const onLogin = await page.locator('input[type="email"]').isVisible().catch(() => false);
  if (onLogin) {
    await page.fill('input[type="email"]', TEST_EMAIL);
    await page.fill('input[type="password"]', TEST_PASSWORD);
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/(dashboard|maps|architectures)/, {timeout: 20_000});
  }
}

test('a non-admin user is redirected away from /health, never seeing it', async ({page}) => {
  await page.goto('/dashboard');
  await ensureLoggedIn(page);

  await page.goto('/health');

  // AdminRoute sends a non-admin straight to /architectures.
  await page.waitForURL(/\/architectures/, {timeout: 10_000});
  await expect(page.locator('text=System health')).not.toBeVisible();
});
