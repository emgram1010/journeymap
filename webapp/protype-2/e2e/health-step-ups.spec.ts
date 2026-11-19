import {test, expect} from '@playwright/test';

/**
 * UI-COP-13-05-01 - Health shows how often the copilot used the stronger model, per day and business.
 * No test account is a platform admin (a founder decision), so the browser is told the user is one and the
 * Health data is stubbed; the live endpoint is proven separately (EPIC-COP-13 Test results).
 */
test('UI-COP-13-05-01 Health shows stronger-model use per day and business', async ({page}) => {
  await page.route('**/auth/me', async (route) => {
    const res = await route.fetch();
    await route.fulfill({response: res, json: {...(await res.json()), is_platform_admin: true}});
  });
  await page.route('**/ops/health', (r) => r.fulfill({json: {failures_24h: 0, open_issues_count: 0, last_heartbeat_at: new Date().toISOString()}}));
  await page.route('**/ops/issues**', (r) => r.fulfill({json: {issues: []}}));
  await page.route('**/ops/estimates**', (r) => r.fulfill({json: {since: '', count: 0, jobs: []}}));
  await page.route('**/ops/exceptions**', (r) => r.fulfill({status: 500, json: {}}));
  await page.route('**/ops/tool_calls**', (r) => r.fulfill({status: 500, json: {}}));
  await page.route('**/ops/step_ups**', (r) => r.fulfill({json: {days: 7, rows: [
    {day: 20775, journey_architecture_id: 49, business: 'Bike repairs', requested: 1, capped: 0, granted: 0, ran: 0, approved: 0, declined: 1, expired: 0, waiting: 0},
    {day: 20776, journey_architecture_id: 49, business: 'Bike repairs', requested: 2, capped: 1, granted: 1, ran: 1, approved: 1, declined: 0, expired: 0, waiting: 0},
  ]}}));

  await page.goto('/health');
  const panel = page.getByTestId('health-step-ups');
  await expect(panel).toBeVisible({timeout: 20_000});
  await expect(panel).toContainText('3 requests to use the stronger model in the last 7 days: 1 approved, 1 declined, 1 refused by the daily limit.');
  const items = panel.locator('li');
  await expect(items.first()).toContainText('Thu 19 Nov - Bike repairs: 2 asked, 1 approved, 1 refused by the daily limit, 1 re-done');
  await expect(items.nth(1)).toContainText('Wed 18 Nov - Bike repairs: 1 asked, 1 declined');
  await page.screenshot({path: 'e2e/screenshots/cop13-05-health-step-ups.png', fullPage: true});
});
