/**
 * ai-agent-actor-fields.spec.ts
 *
 * Regression test for: AI Agent actor cell fields not being populated.
 *
 * Flow:
 * 1. Login + create a fresh map
 * 2. Add an AI Agent lens row via the actor wizard
 * 3. Click the first cell in the new row (selects it as context for chat)
 * 4. Open chat and ask the AI to fill in the AI Agent fields
 * 5. Assert update_actor_cell_fields was called (tool_trace)
 * 6. Assert the correct snake_case keys were written (not human labels)
 * 7. Fetch the cell directly from Xano and confirm actor_fields are populated
 */
import { test, expect, type Page } from '@playwright/test';

const TEST_EMAIL    = process.env.TEST_EMAIL    ?? 'aipming51@gmail.com';
const TEST_PASSWORD = process.env.TEST_PASSWORD ?? 'Emgram2024!';
const XANO_BASE     = 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:ER4MRRWZ';

const AI_AGENT_FIELD_KEYS = [
  'ai_model_agent', 'input_data', 'decision_output', 'confidence_threshold',
  'escalation_logic', 'failure_scenarios', 'performance_metrics',
];

// ── Helpers ──────────────────────────────────────────────────────────────────

async function ensureLoggedIn(page: Page) {
  if (page.url().includes('/login') || page.url() === 'about:blank') {
    await page.goto('/');
  }
  const onLogin = await page.locator('input[type="email"]').isVisible().catch(() => false);
  if (onLogin) {
    await page.fill('input[type="email"]', TEST_EMAIL);
    await page.fill('input[type="password"]', TEST_PASSWORD);
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/(dashboard|maps)/, { timeout: 20_000 });
  }
}

async function createFreshMap(page: Page): Promise<string> {
  await page.goto('/dashboard');
  await ensureLoggedIn(page);
  await page.waitForSelector('button:has-text("New Journey Map")', { timeout: 15_000 });

  const createResp = page.waitForResponse(
    (r) => r.url().includes('/journey_map') && r.request().method() === 'POST' && r.status() === 200,
    { timeout: 30_000 },
  );
  await page.click('button:has-text("New Journey Map")');
  const resp = await createResp;
  const body = await resp.json().catch(() => ({})) as Record<string, unknown>;
  const jm = (body.journey_map ?? body) as Record<string, unknown>;
  const mapId = String(jm?.id ?? '');
  console.log(`🗺️  Map created — ID: ${mapId}`);

  await page.waitForURL(/\/maps\/\d+/, { timeout: 20_000 });
  await page.waitForSelector('[class*="tabulator"]', { timeout: 30_000 });
  return mapId;
}

async function addAiAgentLens(page: Page): Promise<number | null> {
  const addRowBtn = page.locator('button', { hasText: 'Add Row' });
  await addRowBtn.waitFor({ timeout: 15_000 });

  const lensResp = page.waitForResponse(
    (r) => r.url().includes('journey_lens') && r.url().includes('add')
      && r.request().method() === 'POST' && r.status() === 200,
    { timeout: 30_000 },
  );

  await addRowBtn.click();
  await expect(page.locator('text=Actor Type')).toBeVisible({ timeout: 8_000 });

  const aiCard = page.locator('button', { hasText: 'AI Agent' });
  await aiCard.waitFor({ timeout: 8_000 });
  await aiCard.click();

  await expect(page.locator('button', { hasText: 'Add Actor' })).not.toBeDisabled({ timeout: 5_000 });
  await page.locator('button', { hasText: 'Add Actor' }).click();

  const resp = await lensResp;
  const body = await resp.json().catch(() => ({})) as Record<string, unknown>;
  const lensId = (body.lens as Record<string, unknown> | undefined)?.id ?? body.id;
  console.log(`🤖 AI Agent lens added — lens ID: ${lensId}`);

  // Return the first cell id from the scaffolded cells
  const cells = (body.cells ?? []) as Array<Record<string, unknown>>;
  const firstCellId = cells[0]?.id as number | undefined ?? null;
  console.log(`📦 First cell ID: ${firstCellId}`);
  return firstCellId;
}

async function sendAndWait(page: Page, message: string): Promise<Record<string, unknown>> {
  const textarea = page.locator('textarea[placeholder="Type your message..."]');
  const isOpen = await textarea.isVisible().catch(() => false);
  if (!isOpen) {
    await page.locator('button:has(svg.lucide-message-square)').first().click();
    await expect(textarea).toBeVisible({ timeout: 10_000 });
  }

  const respPromise = page.waitForResponse(
    (r) => r.url().includes('/ai_message') && r.request().method() === 'POST',
    { timeout: 120_000 },
  );
  await textarea.fill(message);
  await textarea.press('Enter');

  const resp = await respPromise;
  await expect(textarea).not.toBeDisabled({ timeout: 120_000 });
  await page.waitForTimeout(2_000);

  return resp.json().catch(() => ({})) as Promise<Record<string, unknown>>;
}
