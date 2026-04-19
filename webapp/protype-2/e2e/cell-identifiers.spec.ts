/**
 * Cell Identifiers — validates that selected-cell context reaches the AI endpoint.
 *
 * Bug under test: when a user clicks a matrix cell the UI shows a blue context
 * chip in the composer bar, but the POST to /ai_message never includes the
 * selected cell information — so the agent cannot know which cell the user is
 * referring to.
 *
 * These tests intercept the outgoing request body to prove the gap.
 */
import {test, expect, type Page} from '@playwright/test';

// ── Helpers ────────────────────────────────────────────────────────────────

/** Wait for the map workspace to be ready. */
async function waitForWorkspace(page: Page) {
  await page.goto('/');
  await page.waitForSelector('[class*="tabulator"]', {timeout: 30_000}).catch(() => {});
  await page.waitForTimeout(1_000);
}

/** Open the chat sidebar. */
async function openChat(page: Page) {
  const toggle = page.locator('button:has(svg.lucide-message-square)').first();
  await toggle.waitFor({timeout: 15_000});
  await toggle.click();
  await expect(page.locator('text=AI Interviewer')).toBeVisible({timeout: 5_000});
}

/** Click the first matrix cell and return its data-cell-id. */
async function selectFirstCell(page: Page): Promise<string> {
  const cell = page.locator('.jm-grid-cell[data-cell-id]').first();
  await cell.waitFor({timeout: 10_000});
  const cellId = await cell.getAttribute('data-cell-id');
  await cell.click();
  // Wait for selection to register (animation-frame schedule)
  await page.waitForTimeout(500);
  return cellId ?? '';
}

/**
 * Send a message and capture both the request body and response body from the
 * /ai_message endpoint.
 */
async function sendAndCaptureRequest(page: Page, message: string) {
  const textarea = page.locator('textarea[placeholder="Type your message..."]');
  await textarea.fill(message);

  // Intercept the request+response
  const responsePromise = page.waitForResponse(
    (resp) => resp.url().includes('/ai_message') && resp.request().method() === 'POST',
    {timeout: 90_000},
  );

  await textarea.press('Enter');
  const response = await responsePromise;

  // Extract the request body that was actually sent
  const requestBody = response.request().postDataJSON() as Record<string, unknown>;
  const responseBody = await response.json();

  return {requestBody, responseBody};
}

// ── Tests ──────────────────────────────────────────────────────────────────

test.describe('Cell Identifiers — selected cell context', () => {
  test.setTimeout(120_000);

  test('US-CI-01 — clicking a cell loads stage/lens reference and shorthand into the chat sidebar', async ({page}) => {
    await waitForWorkspace(page);
    await openChat(page);

    const cellId = await selectFirstCell(page);
    expect(cellId).toBeTruthy();

    // The blue context chip should appear with the cell reference text (e.g. "Awareness × Customer Actions")
    const chip = page.locator('.bg-blue-50.border-blue-200');
    await expect(chip).toBeVisible({timeout: 5_000});

    // Should show a shorthand like "S1-L1"
    const shorthand = chip.locator('span.text-blue-500');
    await expect(shorthand).toBeVisible({timeout: 3_000});
    const shorthandText = await shorthand.textContent();
    expect(shorthandText).toMatch(/^S\d+-L\d+$/);
  });

  test('US-CI-02 — selecting a cell then sending a message: request body should include selected cell context', async ({page}) => {
    await waitForWorkspace(page);
    await openChat(page);

    // Select a cell first
    const cellId = await selectFirstCell(page);
    expect(cellId).toBeTruthy();

    // Verify the chip is visible (cell is selected in UI)
    const chip = page.locator('.bg-blue-50.border-blue-200');
    await expect(chip).toBeVisible({timeout: 5_000});

    // Now send a message asking about the selected cell
    const {requestBody} = await sendAndCaptureRequest(
      page,
      'What is the context of this cell? Tell me which stage and lens it belongs to.',
    );

    // ── BUG ASSERTION ──
    // The request body SHOULD contain a selected_cell (or equivalent) field
    // so the AI agent knows which cell the user is looking at.
    // This assertion is expected to FAIL until the bug is fixed.
    expect(requestBody).toHaveProperty('selected_cell');

    // If the field exists, it should contain meaningful identifiers
    if (requestBody.selected_cell) {
      const sc = requestBody.selected_cell as Record<string, unknown>;
      expect(sc).toHaveProperty('stage_key');
      expect(sc).toHaveProperty('lens_key');
    }
  });

  test('US-CI-03 — sending a message with NO cell selected should NOT include selected cell context', async ({page}) => {
    await waitForWorkspace(page);
    await openChat(page);

    // Do NOT click any cell — send message immediately
    const {requestBody} = await sendAndCaptureRequest(
      page,
      'What is a journey map?',
    );

    // When no cell is selected, selected_cell should be absent or null
    const hasCellContext = requestBody.selected_cell !== undefined && requestBody.selected_cell !== null;
    expect(hasCellContext).toBe(false);
  });
});