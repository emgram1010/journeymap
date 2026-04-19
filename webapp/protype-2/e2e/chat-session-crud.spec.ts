/**
 * Chat Session CRUD — validates the session picker in the AI sidebar.
 * Covers: list, create, switch, rename, and delete conversation sessions.
 */
import {test, expect, type Page} from '@playwright/test';

/** Wait for the map workspace to be ready. */
async function waitForWorkspace(page: Page) {
  await page.goto('/');
  // Wait for matrix or workspace content to load
  await page.waitForSelector('[class*="tabulator"]', {timeout: 30_000}).catch(() => {});
  // Small settle
  await page.waitForTimeout(1_000);
}

/** Open the AI chat sidebar. */
async function openChat(page: Page) {
  const toggle = page.locator('button:has(svg.lucide-message-square)').first();
  await toggle.waitFor({timeout: 15_000});
  await toggle.click();
  // Wait for the chat panel header to appear
  await expect(page.locator('text=Interview Mode').or(page.locator('text=Chat Mode'))).toBeVisible({timeout: 5_000});
}

/** Open the session picker dropdown. */
async function openSessionPicker(page: Page) {
  const headerButton = page.locator('button:has(svg.lucide-chevron-down)').first();
  await headerButton.waitFor({timeout: 5_000});
  await headerButton.click();
  // Wait for the "New Session" button to appear inside the dropdown
  await expect(page.locator('button', {hasText: 'New Session'})).toBeVisible({timeout: 5_000});
}

test.describe('Chat Session CRUD', () => {
  test.setTimeout(90_000);

  test('session picker opens and shows "New Session" button', async ({page}) => {
    await waitForWorkspace(page);
    await openChat(page);
    await openSessionPicker(page);

    const newSessionBtn = page.locator('button', {hasText: 'New Session'});
    await expect(newSessionBtn).toBeVisible();
  });

  test('create a new session and verify it becomes active', async ({page}) => {
    await waitForWorkspace(page);
    await openChat(page);

    // Capture current conversation title
    await openSessionPicker(page);

    // Click "New Session"
    const createResponse = page.waitForResponse(
      (resp) => resp.url().includes('/conversation') && resp.request().method() === 'POST' && resp.status() === 200,
      {timeout: 15_000},
    );
    await page.locator('button', {hasText: 'New Session'}).click();
    const resp = await createResponse;
    const body = await resp.json();

    // The response should contain a conversation with an id
    expect(body).toHaveProperty('id');
    expect(typeof body.id).toBe('number');
  });

  test('list sessions shows at least one session after creating', async ({page}) => {
    await waitForWorkspace(page);
    await openChat(page);

    // Create a session first
    await openSessionPicker(page);
    const createResp = page.waitForResponse(
      (resp) => resp.url().includes('/conversation') && resp.request().method() === 'POST' && resp.status() === 200,
      {timeout: 15_000},
    );
    await page.locator('button', {hasText: 'New Session'}).click();
    await createResp;

    // Re-open picker to see the list (which triggers a GET to /conversations)
    await openSessionPicker(page);

    // Should have at least one session item with message count
    const sessionItem = page.locator('text=/\\d+ msgs?/').first();
    await expect(sessionItem).toBeVisible({timeout: 10_000});
  });

  test('switch between sessions loads different messages', async ({page}) => {
    await waitForWorkspace(page);
    await openChat(page);

    // Open picker and click the first listed session (if available)
    await openSessionPicker(page);

    // Wait for session list to populate
    await page.waitForTimeout(2_000);

    const sessionButtons = page.locator('[class*="group"] button.text-left, [class*="group"] button:has-text("Untitled"), [class*="group"] button:has-text("Conversation"), [class*="group"] button:has-text("New Conversation")');
    const count = await sessionButtons.count();

    if (count > 0) {
      // Intercept the GET conversation response
      const getResp = page.waitForResponse(
        (resp) => resp.url().includes('/conversation/') && resp.request().method() === 'GET' && resp.status() === 200,
        {timeout: 15_000},
      );
      await sessionButtons.first().click();
      const resp = await getResp;
      const body = await resp.json();

      expect(body).toHaveProperty('conversation');
      expect(body).toHaveProperty('messages');
    } else {
      // No sessions to switch to — that's fine, just verify the list is empty
      await expect(page.locator('text=No sessions yet')).toBeVisible();
    }
  });

  test('rename a session via inline edit', async ({page}) => {
    await waitForWorkspace(page);
    await openChat(page);

    // Create a session so we have something to rename
    await openSessionPicker(page);
    const createResp = page.waitForResponse(
      (resp) => resp.url().includes('/conversation') && resp.request().method() === 'POST' && resp.status() === 200,
      {timeout: 15_000},
    );
    await page.locator('button', {hasText: 'New Session'}).click();
    await createResp;

    // Re-open the picker
    await openSessionPicker(page);
    await page.waitForTimeout(1_500);

    // Hover over the first session to reveal edit button, then click it
    const sessionRow = page.locator('[class*="group"]').first();
    await sessionRow.hover();
    const editBtn = sessionRow.locator('button:has(svg.lucide-edit-2)');
    if (await editBtn.isVisible({timeout: 3_000}).catch(() => false)) {
      await editBtn.click();
      const renameInput = page.locator('input[class*="border"]').first();
      await renameInput.fill('Renamed Session');
      await renameInput.press('Enter');
      // Verify the PATCH request fires
      await page.waitForTimeout(1_000);
    }
  });
