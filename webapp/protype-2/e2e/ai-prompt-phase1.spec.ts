/**
 * Phase 1 QA — Prompt simulation suite (US-AI-2.01 + US-AI-2.07)
 *
 * These tests hit the LIVE Xano AI endpoint. Assertions are heuristic because
 * LLM output is non-deterministic. We intercept the API response JSON to
 * inspect word count, cell_updates, and banned patterns.
 */
import {test, expect, type Page} from '@playwright/test';

const AI_MESSAGE_URL = '**/journey_map/*/ai_message';

// ── Helpers ────────────────────────────────────────────────────────────────

/** Open the chat sidebar and wait for the map to finish loading. */
async function openChat(page: Page) {
  await page.goto('/');
  // Wait for the matrix to render (a sign the map bundle is loaded)
  await page.waitForSelector('[class*="tabulator"]', {timeout: 30_000}).catch(() => {
    // fallback: wait for any journey-map content to appear
  });
  // Click the floating AI toggle button to open chat
  const toggle = page.locator('button:has(svg.lucide-message-square)').first();
  await toggle.waitFor({timeout: 15_000});
  await toggle.click();
  // Ensure chat panel is visible
  await expect(page.locator('text=AI Interviewer')).toBeVisible({timeout: 5_000});
}

/** Type a message and send it, returning the intercepted API response body. */
async function sendAndCapture(page: Page, message: string) {
  const textarea = page.locator('textarea[placeholder="Type your message..."]');
  await textarea.fill(message);

  // Set up response interception BEFORE pressing Enter
  const responsePromise = page.waitForResponse(
    (resp) => resp.url().includes('/ai_message') && resp.request().method() === 'POST',
    {timeout: 90_000},
  );

  await textarea.press('Enter');
  const response = await responsePromise;
  const body = await response.json();
  return body as {
    reply: string;
    cell_updates: unknown[];
    progress: {total_cells: number; filled_cells: number; percentage: number};
  };
}

function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

const BANNED_PATTERNS = [
  /\d+\s*%\s*(complete|filled|done|progress)/i,
  /\d+\s*of\s*\d+\s*cells/i,
  /i'?ve updated/i,
  /here'?s what i wrote/i,
  /following cells/i,
];

// ── Tests ──────────────────────────────────────────────────────────────────

test.describe('Phase 1 — Prompt quality (2.01 + 2.07)', () => {
  // Generous timeout for AI round-trips
  test.setTimeout(120_000);

  test('Scenario 1 — Vague answerer: AI should probe, NOT write cell', async ({page}) => {
    await openChat(page);
    const body = await sendAndCapture(page, 'confusion');

    // Quality gate should fire → no cells written
    expect(body.cell_updates.length).toBe(0);
    // Reply should still be concise
    expect(wordCount(body.reply)).toBeLessThanOrEqual(100);
    // Should not contain banned stats patterns
    for (const pat of BANNED_PATTERNS) {
      expect(body.reply).not.toMatch(pat);
    }
  });

  test('Scenario 2 — Detailed answerer: AI writes cells, reply < 80 words', async ({page}) => {
    await openChat(page);
    const body = await sendAndCapture(
      page,
      'Delivery drivers wait an average of 23 minutes at restaurant pickup, which delays the next 3 stops. This happens on about 40% of orders during lunch rush. The dispatch team owns this stage.',
    );

    // Detailed answer should pass quality gate → cells written
    expect(body.cell_updates.length).toBeGreaterThan(0);
    // Reply brevity check
    expect(wordCount(body.reply)).toBeLessThanOrEqual(80);
    // No banned patterns
    for (const pat of BANNED_PATTERNS) {
      expect(body.reply).not.toMatch(pat);
    }
  });

  test('Scenario 3 — "Just write it" override', async ({page}) => {
    await openChat(page);

    // First: send a vague answer → expect probe, no write
    const first = await sendAndCapture(page, 'slow');
    expect(first.cell_updates.length).toBe(0);

    // Second: override → expect write
    const second = await sendAndCapture(page, 'just write it');
    expect(second.cell_updates.length).toBeGreaterThan(0);
  });

  test('Scenario 4 — Info dumper: multiple cells, short reply', async ({page}) => {
    await openChat(page);
    const body = await sendAndCapture(
      page,
      'During order initiation the customer places an order via the mobile app. The restaurant confirms within 2 minutes. Main pain point is the app crashes on Android 12 about 15% of the time. The key variable is crash-free session rate. If initiation fails the downstream dispatch and pickup stages both break.',
    );

    // Should write multiple cells from a dense answer
    expect(body.cell_updates.length).toBeGreaterThanOrEqual(2);
    expect(wordCount(body.reply)).toBeLessThanOrEqual(80);
    for (const pat of BANNED_PATTERNS) {
      expect(body.reply).not.toMatch(pat);
    }
  });

  test('Scenario 5 — Mode switcher: chat mode should NOT mutate cells', async ({page}) => {
    await openChat(page);

    // Switch to Chat mode
    const chatBtn = page.locator('button', {hasText: 'Chat'});
    await chatBtn.click();

    const body = await sendAndCapture(
      page,
      'What is a journey map used for in product management?',
    );

    // Chat mode → zero cell mutations
    expect(body.cell_updates.length).toBe(0);
    expect(wordCount(body.reply)).toBeLessThanOrEqual(120);
  });
});
