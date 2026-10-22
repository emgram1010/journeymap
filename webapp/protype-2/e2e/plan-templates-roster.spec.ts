/**
 * plan-templates-roster.spec.ts — PLAN-2 / PLAN-3 (E2E-PLAN-2-01,
 * E2E-PLAN-3-01), written as gap-fix #5 after the Opus review.
 *
 * The whole loop through the real UI: open the Agents screen, build a
 * template in "Manage Templates", add an eligible agent to its roster,
 * create a plan from it, and see that agent on the new plan's board.
 *
 * AUTH: same token-injection approach as perform-sessions-mobile.spec.ts
 * (the shared TEST_EMAIL login fixture is broken — see that file's
 * header). Set E2E_AUTH_TOKEN (or PERFORM_TEST_AUTH_TOKEN) to an admin
 * account's bearer token that has at least one eligible agent; the
 * spec skips cleanly without one.
 *
 * WRITES REAL DATA: each run leaves one template and one plan, both
 * named "E2E roster <timestamp>", in that account.
 */
import {test, expect, type Page} from '@playwright/test';

const AUTH_TOKEN = process.env.E2E_AUTH_TOKEN ?? process.env.PERFORM_TEST_AUTH_TOKEN;

async function signIn(page: Page): Promise<boolean> {
  if (!AUTH_TOKEN) return false;
  await page.goto('/');
  await page.evaluate((token) => localStorage.setItem('authToken', token), AUTH_TOKEN);
  return true;
}

test('E2E-PLAN-2-01: the Agents screen opens and lists the account\'s agents', async ({page}) => {
  test.skip(!(await signIn(page)), 'No auth token — see file header.');
  await page.goto('/planner');
  await page.locator('#agent-profiles-btn').click();
  const modal = page.locator('#agent-profiles-modal');
  await expect(modal).toBeVisible();
  await expect(modal.getByText('Current agents')).toBeVisible();
  await expect(modal.getByText('Eligible').first()).toBeVisible();
});

test('E2E-PLAN-3-01: build a template with an agent, create a plan, agent is on the board', async ({page}) => {
  test.skip(!(await signIn(page)), 'No auth token — see file header.');
  const name = `E2E roster ${Date.now()}`;

  await page.goto('/planner');
  await page.locator('#workspace-switcher-btn').click();
  await page.locator('#manage-templates-dropdown-btn').click();

  const templates = page.locator('#templates-modal');
  await expect(templates).toBeVisible();
  await templates.getByPlaceholder('e.g. Weekly Ops').fill(name);
  await templates.getByRole('button', {name: 'Create'}).click();

  // The new template opens expanded; its second <select> is the agent picker.
  const row = templates.locator('li', {hasText: name});
  const agentSelect = row.locator('select').nth(1);
  await expect(agentSelect).toBeVisible();
  const agentName = (await agentSelect.locator('option').nth(1).textContent())?.trim() ?? '';
  expect(agentName, 'needs at least one eligible agent in this account').not.toBe('');
  await agentSelect.selectOption({index: 1});
  await row.getByTitle('Add agent').click();
  await expect(row.getByText('1 agent')).toBeVisible();

  await templates.getByRole('button', {name: 'Close'}).click();

  await page.locator('#workspace-switcher-btn').click();
  await page.locator('#create-workspace-dropdown-btn').click();
  await page.locator('#new-workspace-name-input').fill(name);
  const templateValue = await page.locator('#new-workspace-template-select option', {hasText: name}).getAttribute('value');
  await page.locator('#new-workspace-template-select').selectOption(templateValue ?? '');
  await expect(page.getByText(`Agents: ${agentName}`)).toBeVisible();
  await page.locator('#confirm-create-workspace-btn').click();

  await expect(page.locator('#workspace-switcher-btn')).toContainText(name);
  await expect(page.getByText(agentName).first()).toBeVisible();
});
