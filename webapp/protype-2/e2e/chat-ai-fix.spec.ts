import { test, expect } from '@playwright/test';

test('chat sends message and gets real AI response without errors', async ({ page }) => {
  // ── Capture all console errors ──
  const consoleErrors: string[] = [];
  page.on('console', msg => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', err => consoleErrors.push(`[pageerror] ${err.message}`));

  // ── Capture AI message request + response (Xano is cross-origin) ──
  let aiRequestMade = false;
  let aiResponseBody: unknown = null;
  let aiResponseStatus = 0;

  page.on('request', req => {
    if (req.url().includes('/ai_message') && req.method() === 'POST') {
      aiRequestMade = true;
    }
  });

  page.on('response', async resp => {
    if (resp.url().includes('/ai_message')) {
      aiResponseStatus = resp.status();
      try { aiResponseBody = await resp.json(); } catch { /* ignore */ }
    }
  });

  // ── Navigate ──
  await page.goto('/');
  await page.waitForSelector('[class*="tabulator"]', { timeout: 30_000 });

  // ── Open chat sidebar if not already open ──
  const textarea = page.locator('textarea[placeholder="Type your message..."]');
  const sidebarAlreadyOpen = await textarea.isVisible().catch(() => false);
  if (!sidebarAlreadyOpen) {
    const chatBtn = page.locator('button:has(svg.lucide-message-square)').first();
    await chatBtn.waitFor({ timeout: 15_000 });
    await chatBtn.click();
  }
  // Wait for the chat input to be ready
  await expect(textarea).toBeVisible({ timeout: 10_000 });

  // ── Screenshots before send ──
  await page.screenshot({ path: 'e2e/screenshots/chat-1-open.png' });

  // ── Type and send message ──
  await textarea.fill('help me create a user journey on creating an ai agent driving journey map');
  await textarea.press('Enter');

  await page.screenshot({ path: 'e2e/screenshots/chat-2-sent.png' });

  // ── Wait for AI response: the textarea re-enables when sending is done ──
  await expect(page.locator('textarea[placeholder="Type your message..."]'))
    .not.toBeDisabled({ timeout: 90_000 });

  // Give the response time to render
  await page.waitForTimeout(2_000);
  await page.screenshot({ path: 'e2e/screenshots/chat-3-response.png' });

  // ── Assertions ──

  // 1. A request was made to the AI endpoint
  expect(aiRequestMade, 'No request was sent to /ai_message').toBe(true);

  // 2. The backend did NOT return a 500
  expect(aiResponseStatus, `AI endpoint returned ${aiResponseStatus} — expected 200`).toBe(200);

  // 3. Response body has no error code
  const body = aiResponseBody as Record<string, unknown> | null;
  expect(body?.code, `Backend error: ${body?.code} — ${body?.message}`).toBeUndefined();

  // 4. Response contains a reply
  expect(typeof body?.reply, 'reply field missing from response').toBe('string');
  expect((body?.reply as string).length, 'reply is empty').toBeGreaterThan(0);

  // 5. No visible error banner on screen
  await expect(page.getByText('Not numeric')).toBeHidden();
  await expect(page.getByText('ERROR_FATAL')).toBeHidden();
  await expect(page.getByText('Unable to locate var')).toBeHidden();
});
