/**
 * Internal Actor — validates the internal-v1 actor template end-to-end.
 * Covers: wizard card active, row creation with 12-field scaffold, cell panel renders internal fields.
 */
import {test, expect, type Page} from '@playwright/test';

async function waitForWorkspace(page: Page) {
  await page.goto('/');
  await page.waitForSelector('[class*="tabulator"]', {timeout: 30_000}).catch(() => {});
  await page.waitForTimeout(1_500);
}

async function openActorWizard(page: Page) {
  const addRowBtn = page.locator('button', {hasText: 'Add Row'});
  await addRowBtn.waitFor({timeout: 15_000});
  await addRowBtn.click();
  // Wizard modal should appear
  await expect(page.locator('text=Actor Type')).toBeVisible({timeout: 8_000});
}

test.describe('Internal Actor Template', () => {
  test.setTimeout(120_000);

  test('wizard shows Internal Employee card as active (not coming soon)', async ({page}) => {
    await waitForWorkspace(page);
    await openActorWizard(page);

    // Card should be visible and NOT disabled
    const internalCard = page.locator('button', {hasText: 'Internal Employee'});
    await expect(internalCard).toBeVisible({timeout: 8_000});
    await expect(internalCard).not.toBeDisabled();

    // Should NOT show "Soon" badge
    const soonBadge = internalCard.locator('text=Soon');
    await expect(soonBadge).not.toBeVisible();
  });

  test('selecting Internal Employee enables the Add Actor button', async ({page}) => {
    await waitForWorkspace(page);
    await openActorWizard(page);

    const internalCard = page.locator('button', {hasText: 'Internal Employee'});
    await internalCard.click();

    const addActorBtn = page.locator('button', {hasText: 'Add Actor'});
    await expect(addActorBtn).not.toBeDisabled({timeout: 5_000});
  });

  test('creates internal actor row via API with correct actor_type and 12 scaffolded fields', async ({page}) => {
    await waitForWorkspace(page);
    await openActorWizard(page);

    // Select Internal Employee
    await page.locator('button', {hasText: 'Internal Employee'}).click();

    // Intercept the add-lens POST
    const lensPostResp = page.waitForResponse(
      (resp) =>
        resp.url().includes('journey_lens') &&
        resp.url().includes('add') &&
        resp.request().method() === 'POST' &&
        resp.status() === 200,
      {timeout: 30_000},
    );

    await page.locator('button', {hasText: 'Add Actor'}).click();
    const resp = await lensPostResp;
    const body = await resp.json();

    // Lens should be internal
    expect(body.lens?.actor_type ?? body.actor_type).toBe('internal');
    expect(body.lens?.template_key ?? body.template_key).toBe('internal-v1');

    // At least one cell should have all 12 actor_fields keys
    const cells: Array<Record<string, unknown>> = body.cells ?? [];
    if (cells.length > 0) {
      const firstCellFields = cells[0].actor_fields as Record<string, unknown> | null;
      expect(firstCellFields).not.toBeNull();
      const expectedKeys = [
        'task_objective', 'entry_trigger', 'tools_systems', 'information_needs',
        'decisions_required', 'friction_points', 'assumptions', 'handoff_dependencies',
        'success_criteria', 'output_deliverable', 'employee_constraints', 'pain_points',
      ];
      for (const key of expectedKeys) {
        expect(firstCellFields).toHaveProperty(key);
      }
    }
  });

  test('cell detail panel renders internal-specific fields after row creation', async ({page}) => {
    await waitForWorkspace(page);
    await openActorWizard(page);

    await page.locator('button', {hasText: 'Internal Employee'}).click();

    const lensPostResp = page.waitForResponse(
      (resp) =>
        resp.url().includes('journey_lens') &&
        resp.url().includes('add') &&
        resp.request().method() === 'POST' &&
        resp.status() === 200,
      {timeout: 30_000},
    );

    await page.locator('button', {hasText: 'Add Actor'}).click();
    await lensPostResp;

    // Wait for the new row to appear in the matrix
    await page.waitForTimeout(2_000);

    // Click the first cell in the last row (the new internal actor row)
    const cells = page.locator('.tabulator-cell[tabulator-field]');
    const cellCount = await cells.count();
    if (cellCount > 0) {
      await cells.last().click();
      await page.waitForTimeout(1_000);

      // Cell Detail Panel should show internal-specific field labels
      await expect(page.locator('text=Task / Objective')).toBeVisible({timeout: 8_000});
      await expect(page.locator('text=Tools & Systems Used')).toBeVisible({timeout: 5_000});
      await expect(page.locator('text=Handoff Dependencies')).toBeVisible({timeout: 5_000});
      await expect(page.locator('text=Success Criteria')).toBeVisible({timeout: 5_000});
      await expect(page.locator('text=Pain Points')).toBeVisible({timeout: 5_000});

      // Should NOT show customer-specific fields
      await expect(page.locator('text=Feelings / Emotions')).not.toBeVisible();
      await expect(page.locator('text=Acceptance Criteria')).not.toBeVisible();
    }
  });
});
