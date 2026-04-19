import { test, expect } from '@playwright/test';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

type TurnResult = {
  status: number;
  reply: string;
  toolsUsed: string[];
  appliedUpdates: unknown[];
  error?: string;
};

async function openFreshChat(page: import('@playwright/test').Page, mode: 'chat' | 'interview' = 'chat') {
  await page.goto('/');
  await page.waitForSelector('[class*="tabulator"]', { timeout: 30_000 });

  // Open sidebar
  const textarea = page.locator('textarea[placeholder="Type your message..."]');
  const open = await textarea.isVisible().catch(() => false);
  if (!open) {
    await page.locator('button:has(svg.lucide-message-square)').first().click();
  }
  await expect(textarea).toBeVisible({ timeout: 10_000 });

  // Start a NEW conversation so the AI has zero prior context and MUST call tools
  const newConvBtn = page.locator('button', { hasText: 'New Conversation' });
  if (await newConvBtn.isVisible().catch(() => false)) {
    await newConvBtn.click();
    await page.waitForTimeout(600);
  }

  // Set mode
  if (mode === 'interview') {
    const interviewBtn = page.locator('button', { hasText: 'Interview' });
    await interviewBtn.waitFor({ timeout: 10_000 });
    await interviewBtn.click();
    await page.waitForTimeout(500);
  } else {
    const chatBtn = page.locator('button', { hasText: 'Chat' });
    await chatBtn.waitFor({ timeout: 10_000 });
    await chatBtn.click();
    await page.waitForTimeout(500);
  }

  await expect(textarea).toBeVisible({ timeout: 5_000 });
  return textarea;
}

async function sendAndWait(
  page: import('@playwright/test').Page,
  textarea: import('@playwright/test').Locator,
  message: string,
): Promise<TurnResult> {
  let status = 0;
  let body: Record<string, unknown> = {};

  // One-shot response capture for this turn
  const responsePromise = page.waitForResponse(
    r => r.url().includes('/ai_message'),
    { timeout: 90_000 },
  );

  await textarea.fill(message);
  await textarea.press('Enter');

  const resp = await responsePromise;
  status = resp.status();
  try { body = await resp.json(); } catch { /* ignore */ }

  // Wait for textarea to re-enable (agent finished)
  await expect(textarea).not.toBeDisabled({ timeout: 90_000 });
  await page.waitForTimeout(1_000);

  const toolsUsed: string[] = ((body.tool_trace ?? []) as Array<{ tool_name: string }>)
    .map(t => t.tool_name);

  return {
    status,
    reply: (body.reply as string) ?? '',
    toolsUsed,
    appliedUpdates: (body.applied_updates as unknown[]) ?? [],
    error: body.code ? `${body.code}: ${body.message}` : undefined,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

test.describe('AI Chat — tool & context validation', () => {

  test('T1 · map state context — AI reads the live map before answering', async ({ page }) => {
    const textarea = await openFreshChat(page, 'chat');
    const result = await sendAndWait(page, textarea,
      "What does my current journey map look like? How many stages and lenses do I have?");

    expect(result.error, result.error).toBeUndefined();
    expect(result.status).toBe(200);
    expect(result.reply.length).toBeGreaterThan(0);

    // Agent must call get_map_state to answer this — it cannot know without looking
    expect(result.toolsUsed, `Expected get_map_state tool call. Got: ${result.toolsUsed}`).toContain('get_map_state');

    // Reply should reference stages or lenses specifically
    const mentionsStructure = /stage|lens|column|row/i.test(result.reply);
    expect(mentionsStructure, `Reply doesn't mention map structure: "${result.reply.slice(0, 200)}"`).toBe(true);

    await page.screenshot({ path: 'e2e/screenshots/t1-map-state.png' });
  });

  test('T2 · gap analysis — AI identifies empty cells', async ({ page }) => {
    const textarea = await openChat(page);
    const result = await sendAndWait(page, textarea,
      "Where are the biggest gaps in my journey map? What's missing?");

    expect(result.error, result.error).toBeUndefined();
    expect(result.status).toBe(200);

    // Agent should use get_gaps tool
    expect(result.toolsUsed, `Expected get_gaps tool. Got: ${result.toolsUsed}`).toContain('get_gaps');

    const mentionsGaps = /gap|empty|missing|fill|blank|incomplete/i.test(result.reply);
    expect(mentionsGaps, `Reply doesn't address gaps: "${result.reply.slice(0, 200)}"`).toBe(true);

    await page.screenshot({ path: 'e2e/screenshots/t2-gap-analysis.png' });
  });

  test('T3 · interview mode — AI asks a focused question and writes to cells', async ({ page }) => {
    const textarea = await openChat(page);

    // Switch to interview mode first
    const interviewBtn = page.locator('button', { hasText: 'Interview' });
    await interviewBtn.waitFor({ timeout: 10_000 });
    await interviewBtn.click();
    await page.waitForTimeout(500);

    const result = await sendAndWait(page, textarea,
      "Let's start a PM interview. I'm building a journey map for an AI agent onboarding flow.");

    expect(result.error, result.error).toBeUndefined();
    expect(result.status).toBe(200);

    // In interview mode the AI should ask a follow-up question
    const asksQuestion = /\?/.test(result.reply);
    expect(asksQuestion, `Interview mode should ask a question. Reply: "${result.reply.slice(0, 200)}"`).toBe(true);

    await page.screenshot({ path: 'e2e/screenshots/t3-interview-mode.png' });
  });

  test('T4 · cell-level context — AI reasons about a specific stage/lens', async ({ page }) => {
    const textarea = await openChat(page);
    const result = await sendAndWait(page, textarea,
      "Tell me about Stage 1. What's filled in there and what's still empty?");

    expect(result.error, result.error).toBeUndefined();
    expect(result.status).toBe(200);

    // Should call get_slice to answer a stage-specific question
    const usedSlice = result.toolsUsed.includes('get_slice') || result.toolsUsed.includes('get_map_state');
    expect(usedSlice, `Expected get_slice or get_map_state. Got: ${result.toolsUsed}`).toBe(true);

    await page.screenshot({ path: 'e2e/screenshots/t4-cell-context.png' });
  });

  test('T5 · no errors on any turn — error banners never appear', async ({ page }) => {
    const textarea = await openChat(page);

    const questions = [
      "What's the overall completion percentage of my map?",
      "Which lens has the most data filled in?",
    ];

    for (const q of questions) {
      const result = await sendAndWait(page, textarea, q);
      expect(result.error, `Error on "${q}": ${result.error}`).toBeUndefined();
      expect(result.status, `Non-200 on "${q}"`).toBe(200);
    }

    await expect(page.getByText('ERROR_FATAL')).toBeHidden();
    await expect(page.getByText('Unable to locate var')).toBeHidden();
    await expect(page.getByText('Not numeric')).toBeHidden();

    await page.screenshot({ path: 'e2e/screenshots/t5-no-errors.png' });
  });

});
