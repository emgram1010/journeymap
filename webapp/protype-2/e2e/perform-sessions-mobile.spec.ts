/**
 * perform-sessions-mobile.spec.ts — APP-2 (US-APP-2-08, US-APP-2-09)
 *
 * Covers the layout/navigation acceptance criteria that don't depend on
 * a particular account having seeded session data: no horizontal
 * scroll at phone width, the mobile nav's tap targets and its two-taps
 * reach to every layer, and that the desktop sidebar is untouched at
 * >= 768px.
 *
 * AUTH: the repo's shared TEST_EMAIL/TEST_PASSWORD UI-login fixture
 * (same one health-page.spec.ts uses) was found broken in this
 * environment while building this spec — the existing health-page spec
 * fails at the same `waitForURL` login step with no change of mine, so
 * this predates APP-2, and that fixture's `isVisible()` login-form
 * check also races the SPA's own redirect (true before the redirect
 * has happened, not just before login completes), so it isn't reused
 * here even as a fallback. Instead this file injects a real bearer
 * token straight into localStorage (the `authToken` key
 * `xano.ts::getAuthToken` reads) from `PERFORM_TEST_AUTH_TOKEN`, and
 * skips with a clear reason when that's not set. Get a token without
 * handling a password, same technique CLAUDE.md documents for backend
 * HTTP testing: run `Getting Started Template/generate_magic_link` for
 * a test user via the Xano MCP, then POST its token to
 * `reset/magic-link-login`.
 *
 * NOT COVERED HERE: the interactive Today -> Session -> Step flow
 * against real published jobs (session grouping, notes, the Blocked/
 * Skip reason pickers, double-tap idempotency) — that was verified
 * once, by hand, against the founder's own seeded test data (map 205 /
 * job 9, the Nguyen wedding) over real HTTP and in a real browser
 * session instead. See the epic's Test Results for what that covered.
 */
import {test, expect, type Page} from '@playwright/test';

const AUTH_TOKEN = process.env.PERFORM_TEST_AUTH_TOKEN;

async function ensureLoggedIn(page: Page): Promise<boolean> {
  if (!AUTH_TOKEN) return false;
  await page.goto('/');
  await page.evaluate((token) => localStorage.setItem('authToken', token), AUTH_TOKEN);
  return true;
}

const PHONE_VIEWPORTS = [
  {width: 375, height: 812},
  {width: 390, height: 844},
];

for (const viewport of PHONE_VIEWPORTS) {
  test.describe(`US-APP-2-08/-09 mobile layout @ ${viewport.width}x${viewport.height}`, () => {
    test.use({viewport});

    test('no horizontal scroll, and the mobile menu reaches every layer in two taps', async ({page}) => {
      await page.goto('/dashboard');
      const loggedIn = await ensureLoggedIn(page);
      test.skip(!loggedIn, 'No working auth fixture available — see file header.');
      await page.goto('/perform');
      await page.waitForLoadState('networkidle');

      const hasHorizontalScroll = await page.evaluate(
        () => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
      );
      expect(hasHorizontalScroll).toBe(false);

      // The desktop sidebar is hidden below `md` (correct — /perform is
      // phone-first), so the hamburger is the only way to reach the
      // other two layers.
      await expect(page.locator('#app-sidebar')).toBeHidden();

      const menuButton = page.getByRole('button', {name: /open menu/i});
      await expect(menuButton).toBeVisible();
      const box = await menuButton.boundingBox();
      expect(box).not.toBeNull();
      expect(box!.width).toBeGreaterThanOrEqual(44);
      expect(box!.height).toBeGreaterThanOrEqual(44);

      await menuButton.click(); // tap 1 of 2
      const plannerLink = page.getByRole('link', {name: 'Planner'});
      await expect(plannerLink).toBeVisible();
      await expect(page.getByRole('link', {name: 'Intelligent Layer'})).toBeVisible();
      await expect(page.getByRole('link', {name: 'Execution'})).toBeVisible();

      await plannerLink.click(); // tap 2 of 2
      await page.waitForURL(/\/planner/);
    });
  });
}

test.describe('US-APP-2-09 desktop sidebar unchanged at >= 768px', () => {
  test.use({viewport: {width: 1024, height: 800}});

  test('sidebar is visible and the mobile hamburger does not appear', async ({page}) => {
    await page.goto('/dashboard');
    const loggedIn = await ensureLoggedIn(page);
    test.skip(!loggedIn, 'No working auth fixture available — see file header.');
    await page.goto('/perform');
    await expect(page.locator('#app-sidebar')).toBeVisible();
    await expect(page.getByRole('button', {name: /open menu/i})).toBeHidden();
  });
});
