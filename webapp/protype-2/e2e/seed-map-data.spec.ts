/**
 * seed-map-data.spec.ts
 *
 * Runs a realistic PM interview to populate the journey map with real data
 * before validation tests run. Uses interview mode so the AI extracts answers
 * and writes to cells automatically.
 */
import { test, expect } from '@playwright/test';

async function openInterviewChat(page: import('@playwright/test').Page) {
  await page.goto('/');
  await page.waitForSelector('[class*="tabulator"]', { timeout: 30_000 });

  // Open chat sidebar
  const textarea = page.locator('textarea[placeholder="Type your message..."]');
  const open = await textarea.isVisible().catch(() => false);
  if (!open) {
    await page.locator('button:has(svg.lucide-message-square)').first().click();
  }
  await expect(textarea).toBeVisible({ timeout: 10_000 });

  // Switch to interview mode
  const interviewBtn = page.locator('button', { hasText: 'Interview' });
  await interviewBtn.waitFor({ timeout: 10_000 });
  await interviewBtn.click();
  await page.waitForTimeout(500);

  return textarea;
}

async function sendTurn(
  page: import('@playwright/test').Page,
  textarea: import('@playwright/test').Locator,
  message: string,
  label: string,
) {
  console.log(`\n📤 [${label}] Sending: "${message}"`);

  const responsePromise = page.waitForResponse(
    r => r.url().includes('/ai_message'),
    { timeout: 90_000 },
  );

  await textarea.fill(message);
  await textarea.press('Enter');

  const resp = await responsePromise;
  const body = await resp.json().catch(() => ({})) as Record<string, unknown>;

  await expect(textarea).not.toBeDisabled({ timeout: 90_000 });
  await page.waitForTimeout(1_500);

  const tools = ((body.tool_trace ?? []) as Array<{ tool_name: string }>).map(t => t.tool_name);
  const updates = (body.applied_updates as unknown[] ?? []).length;
  const reply = (body.reply as string ?? '').slice(0, 180);

  console.log(`✅ [${label}] Status: ${resp.status()} | Tools: ${tools.join(', ')} | Cells written: ${updates}`);
  console.log(`💬 [${label}] Reply: ${reply}...`);

  expect(resp.status(), `[${label}] API error: ${body.code} — ${body.message}`).toBe(200);
  expect(body.code, `[${label}] ERROR_FATAL: ${body.message}`).toBeUndefined();

  await page.screenshot({ path: `e2e/screenshots/seed-${label}.png` });

  return { tools, updates, reply, status: resp.status() };
}

test('seed — populate journey map via PM interview', async ({ page }) => {
  const textarea = await openInterviewChat(page);

  // ── Turn 1: kick off interview, establish context ──
  await sendTurn(page, textarea,
    "I'm a PM at a logistics startup. We're mapping the driver onboarding journey — from signup to first completed delivery. Let's fill in the map.",
    '01-kickoff');

  // ── Turn 2: describe the initiation stage ──
  await sendTurn(page, textarea,
    "In the first stage, drivers download the app, create an account, and upload their licence and vehicle docs. The main pain point is the document upload — it times out on slow connections and there's no retry. The primary owner is the Driver Ops team.",
    '02-stage1-initiation');

  // ── Turn 3: describe the verification stage ──
  await sendTurn(page, textarea,
    "Stage two is background check and document verification. It takes 3 to 5 business days. Drivers don't get status updates so they call support constantly. The customer experience here is very poor — high drop-off. Ops and Legal are joint owners.",
    '03-stage2-verification');

  // ── Turn 4: describe the training stage ──
  await sendTurn(page, textarea,
    "Third stage is in-app training — 4 short videos and a safety quiz. Most drivers complete it in under 30 minutes. The top pain point is that the quiz can only be taken on desktop, not mobile. Product owns this stage.",
    '04-stage3-training');

  // ── Turn 5: describe the activation stage ──
  await sendTurn(page, textarea,
    "The final stage is first delivery activation. Driver gets assigned their first order automatically. Pain point: drivers feel unprepared — they want a practice run first. Supporting roles include dispatch and the routing algorithm team.",
    '05-stage4-activation');

  // ── Turn 6: ask AI to review gaps and fill anything missing ──
  await sendTurn(page, textarea,
    "Can you review what we have so far and fill in any cells that are still empty based on what I've told you?",
    '06-fill-gaps');

  console.log('\n🗺️  Journey map seeded with interview data. Ready for validation tests.');
});
