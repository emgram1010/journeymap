import {test, expect} from '@playwright/test';

/**
 * UI-COP-13-02-01 - Health lists each AI agent with its model, and flags the older ones.
 * No test account is a platform admin (a founder decision, see health-page.spec.ts), so the browser is told
 * the signed-in user is one (auth/me) and the other Health data is stubbed. The agent list itself needs no
 * server call, so what is checked here is the real panel.
 */
test('UI-COP-13-02-01 Health shows each agent with its model and flags older ones', async ({page}) => {
  await page.route('**/auth/me', async (route) => {
    const res = await route.fetch();
    const body = await res.json();
    await route.fulfill({response: res, json: {...body, is_platform_admin: true}});
  });
  await page.route('**/ops/health', (r) => r.fulfill({json: {failures_24h: 0, open_issues_count: 0, last_heartbeat_at: new Date().toISOString()}}));
  await page.route('**/ops/issues**', (r) => r.fulfill({json: {issues: []}}));
  await page.route('**/ops/estimates**', (r) => r.fulfill({json: {since: '', count: 0, jobs: []}}));
  await page.route('**/ops/exceptions**', (r) => r.fulfill({status: 500, json: {}}));
  await page.route('**/ops/tool_calls**', (r) => r.fulfill({status: 500, json: {}}));

  await page.goto('/health');
  const panel = page.getByTestId('health-agent-models');
  await expect(panel).toBeVisible({timeout: 20_000});
  await expect(panel).toContainText(/\d of \d agents are on an older model|All \d+ agents are on a current model/);
  await expect(panel.getByTestId('agent-model-emgram_copilot')).toContainText('Sonnet 5.5');
  await expect(panel.getByTestId('agent-model-emgram_copilot_strong')).toContainText('Opus 5.5');
  await expect(panel.getByTestId('agent-model-journey_map_builder')).toContainText('older');
  await page.screenshot({path: 'e2e/screenshots/cop13-02-health-models.png'});
});
