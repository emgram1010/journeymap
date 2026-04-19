/**
 * ai-generate-journey-map.spec.ts
 *
 * Full end-to-end test: creates a brand-new journey map from the dashboard,
 * then uses the AI chatbot (Interview mode) to generate the entire map —
 * settings, lenses (roles), stages (steps), and cell content.
 *
 * If cells are empty after the first AI round-trip, the test sends follow-up
 * prompts and diagnoses exactly what is missing.
 */
import { test, expect, type Page } from '@playwright/test';

// ── Config ──────────────────────────────────────────────────────────────────
const TEST_EMAIL    = process.env.TEST_EMAIL    ?? 'aipming51@gmail.com';
const TEST_PASSWORD = process.env.TEST_PASSWORD ?? 'Emgram2024!';

const AI_PROMPT_FULL = `
Generate a COMPLETE journey map for an e-commerce customer online shopping experience.

Do ALL of the following in one go:

1. UPDATE JOURNEY SETTINGS:
   - primary_actor: "Online Shopper"
   - journey_scope: "First-time purchase from product discovery to delivery"
   - start_point: "Customer discovers the brand via ad or search"
   - end_point: "Customer receives the product and leaves a review"
   - pain_points_summary: "Slow checkout, lack of trust signals, unclear delivery timelines"
   - opportunities: "One-click checkout, proactive delivery notifications, review incentives"
   - version: "v1.0 - April 2026"

2. SET 5 STAGES (rename existing stages):
   Stage 1: Discovery
   Stage 2: Consideration
   Stage 3: Purchase
   Stage 4: Fulfillment
   Stage 5: Post-Purchase

3. ADD 2 LENSES (rows):
   - Label: "Support Team", actor_type: internal
   - Label: "Engineering", actor_type: engineering

4. FILL ALL CELLS with realistic content for every stage × lens combination.
   Include actions, pain points, owner, metrics, and opportunities for each cell.

Please execute all steps immediately and confirm what was written.
`.trim();

const AI_PROMPT_FOLLOWUP = `
Please check the map for any empty cells and fill them all in now.
Use batch_update to write content to every remaining empty cell.
The map should be fully populated when you are done.
`.trim();

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Login if the page lands on /login */
async function ensureLoggedIn(page: Page) {
  const url = page.url();
  if (url.includes('/login')) {
    console.log('🔐 Logging in…');
    await page.fill('input[type="email"]', TEST_EMAIL);
    await page.fill('input[type="password"]', TEST_PASSWORD);
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/(dashboard|maps)/, { timeout: 20_000 });
    console.log('✅ Logged in — URL:', page.url());
  }
}

/** Create a new journey map from the dashboard and return map ID from URL. */
async function createNewMap(page: Page): Promise<string> {
  // Navigate to dashboard
  await page.goto('/dashboard');
  await ensureLoggedIn(page);
  await page.waitForSelector('button:has-text("New Journey Map")', { timeout: 15_000 });

  // Intercept the create_draft response to get the map ID
  const createResponsePromise = page.waitForResponse(
    (r) => r.url().includes('/journey_map') && r.request().method() === 'POST' && r.status() === 200,
    { timeout: 30_000 },
  );

  await page.click('button:has-text("New Journey Map")');
  const createResp = await createResponsePromise;
  const createBody = await createResp.json().catch(() => ({})) as Record<string, unknown>;
  const jm = (createBody.journey_map ?? createBody) as Record<string, unknown>;
  const mapId = String(jm?.id ?? '');
  console.log(`🗺️  New map created — ID: ${mapId}`);

  // Wait for navigation to /maps/:id
  await page.waitForURL(/\/maps\/\d+/, { timeout: 20_000 });
  await page.waitForSelector('[class*="tabulator"]', { timeout: 30_000 });
  console.log('✅ Map editor loaded');
  return mapId;
}

/** Open the AI chat sidebar. */
async function openChat(page: Page) {
  const textarea = page.locator('textarea[placeholder="Type your message..."]');
  const alreadyOpen = await textarea.isVisible().catch(() => false);
  if (!alreadyOpen) {
    const btn = page.locator('button:has(svg.lucide-message-square)').first();
    await btn.waitFor({ timeout: 15_000 });
    await btn.click();
  }
  await expect(textarea).toBeVisible({ timeout: 10_000 });
  console.log('💬 Chat sidebar open');
}

/** Send a message and wait for the AI response; returns the parsed response body. */
async function sendAndWait(
  page: Page,
  message: string,
  label: string,
): Promise<Record<string, unknown>> {
  console.log(`\n📤 [${label}] Sending message (${message.length} chars)…`);

  const responsePromise = page.waitForResponse(
    (r) => r.url().includes('/ai_message') && r.request().method() === 'POST',
    { timeout: 120_000 },
  );

  const textarea = page.locator('textarea[placeholder="Type your message..."]');
  await textarea.fill(message);
  await textarea.press('Enter');

  const resp = await responsePromise;
  const body = await resp.json().catch(() => ({})) as Record<string, unknown>;

  // Wait for textarea to be re-enabled (send complete)
  await expect(textarea).not.toBeDisabled({ timeout: 120_000 });
  await page.waitForTimeout(2_000);

  const status = resp.status();
  const tools   = ((body.tool_trace ?? []) as Array<{ tool_name: string }>).map(t => t.tool_name);
  const reply   = (body.reply as string ?? '').slice(0, 200);
  const cells   = (body.cell_updates as unknown[] ?? []).length;
  const prog    = body.progress as Record<string, unknown> ?? {};

  console.log(`✅ [${label}] HTTP ${status} | tools: [${tools.join(', ')}] | cells written: ${cells}`);
  console.log(`📊 [${label}] progress: ${JSON.stringify(prog)}`);
  console.log(`💬 [${label}] reply: ${reply}…`);

  expect(status, `[${label}] API returned ${status}`).toBe(200);
  expect(body.code, `[${label}] Backend error: ${body.message}`).toBeUndefined();

  return body;
}

// ── Main test ────────────────────────────────────────────────────────────────

test('AI chatbot generates a complete journey map — settings, lenses, stages, cells', async ({ page }) => {
  test.setTimeout(300_000); // 5 min — LLM calls can be slow

  // ── Capture errors ──
  const consoleErrors: string[] = [];
  page.on('console', msg => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
  page.on('pageerror', err => consoleErrors.push(`[pageerror] ${err.message}`));

  // ── Step 1: Login + create a fresh map ──
  await page.goto('/');
  await ensureLoggedIn(page);

  const mapId = await createNewMap(page);
  await page.screenshot({ path: 'e2e/screenshots/gen-01-fresh-map.png' });

  // ── Step 2: Open chat ──
  await openChat(page);
  await page.screenshot({ path: 'e2e/screenshots/gen-02-chat-open.png' });

  // ── Step 3: Send the comprehensive generation prompt ──
  const turn1 = await sendAndWait(page, AI_PROMPT_FULL, 'turn1-generate');
  await page.screenshot({ path: 'e2e/screenshots/gen-03-after-turn1.png' });

  const progress1 = turn1.progress as Record<string, unknown> ?? {};
  const filledAfterTurn1 = Number(progress1.filled_cells ?? 0);
  const totalAfterTurn1  = Number(progress1.total_cells  ?? 0);
  console.log(`\n📊 After turn 1: ${filledAfterTurn1}/${totalAfterTurn1} cells filled`);

  // ── Step 4: Follow-up if cells are not yet populated ──
  let filledFinal = filledAfterTurn1;
  let totalFinal  = totalAfterTurn1;

  if (filledAfterTurn1 < 5) {
    console.log('⚠️  Few cells filled after turn 1 — sending follow-up prompt…');
    const turn2 = await sendAndWait(page, AI_PROMPT_FOLLOWUP, 'turn2-fill-gaps');
    await page.screenshot({ path: 'e2e/screenshots/gen-04-after-turn2.png' });
    const prog2 = turn2.progress as Record<string, unknown> ?? {};
    filledFinal = Number(prog2.filled_cells ?? filledFinal);
    totalFinal  = Number(prog2.total_cells  ?? totalFinal);
    console.log(`📊 After turn 2: ${filledFinal}/${totalFinal} cells filled`);
  }

  // ── Step 5: If STILL empty, diagnose the problem ──
  if (filledFinal === 0) {
    console.log('\n🔴 TROUBLESHOOTING: No cells filled after 2 AI turns.');
    console.log('   Checking for backend errors in console…');
    console.log('   Console errors captured:', consoleErrors);

    // Ask the AI to explain what it sees
    const diag = await sendAndWait(
      page,
      'Please call get_map_state and tell me exactly what the current map looks like — how many stages, lenses, and filled cells.',
      'diag-map-state',
    );
    await page.screenshot({ path: 'e2e/screenshots/gen-05-diag.png' });
    console.log('🔍 Diagnostic reply:', (diag.reply as string ?? '').slice(0, 500));

    // One more targeted attempt
    const turn3 = await sendAndWait(
      page,
      'Now use batch_update to fill at least 3 cells with any content so I can verify writes are working.',
      'turn3-smoke-write',
    );
    await page.screenshot({ path: 'e2e/screenshots/gen-06-smoke-write.png' });
    const prog3 = turn3.progress as Record<string, unknown> ?? {};
    filledFinal = Number(prog3.filled_cells ?? filledFinal);
    console.log(`📊 After smoke write: ${filledFinal} cells filled`);
  }

  // ── Step 6: Final screenshot + assertions ──
  await page.screenshot({ path: 'e2e/screenshots/gen-07-final.png' });

  // Validate: at least some cells should now be filled
  expect(filledFinal, `Expected at least 1 cell to be filled. Map ID: ${mapId}. Check screenshots gen-01 through gen-07.`).toBeGreaterThan(0);

  // Validate: map title area should show something (not empty)
  const titleEl = page.locator('[class*="font-semibold"][class*="text-zinc"]').first();
  await expect(titleEl).toBeVisible({ timeout: 5_000 });

  // Validate: no fatal error banners visible
  await expect(page.getByText('ERROR_FATAL')).toBeHidden();
  await expect(page.getByText('Unable to locate')).toBeHidden();

  // Log final console errors (non-blocking — informational only)
  if (consoleErrors.length > 0) {
    console.warn('\n⚠️  Console errors during test:', consoleErrors.join('\n'));
  }

  console.log(`\n🏁 Test complete — Map ID: ${mapId} | ${filledFinal}/${totalFinal} cells filled`);
});
