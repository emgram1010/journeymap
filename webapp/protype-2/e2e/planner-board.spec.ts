/**
 * planner-board.spec.ts — BOARD-1 (US-BOARD-1-01/02), drag source moved
 * by QUE-1 (US-QUE-1-02/05, 2026-10-30).
 *
 * THE DRAG ITSELF. The sibling specs prove the click path ("Place…")
 * and the card semantics end to end; this one proves the gesture the
 * epic exists for — drag a card onto a day — and the one refusal with
 * its own client-side sentence: a published day.
 *
 * QUE-1 MOVED THE SOURCE, NOT THE RULE. BOARD-1 dragged straight from
 * the Jobs column; QUE-1 removed that shortcut (D-2: work moves jobs
 * list → Unscheduled → a day, one direction) — a role line with no day
 * shows automatically in Unscheduled (Q-1), and that is now the only
 * place a card can be dragged from. The drop side (the day column, the
 * published-day refusal) is untouched.
 *
 * E2E-BOARD-1-01: drag a waiting card from Unscheduled onto an
 *   unpublished day column → the card leaves Unscheduled, the slot
 *   appears with its provenance.
 * E2E-BOARD-1-02: drop a card on a PUBLISHED day → the sentence shows,
 *   the card is still in Unscheduled, nothing was scheduled.
 *
 * AUTH: token injection, same as the sibling specs. Set E2E_AUTH_TOKEN
 * (or PERFORM_TEST_AUTH_TOKEN); the spec skips cleanly without one.
 *
 * WRITES REAL DATA: leaves one job named "E2E board <timestamp>" in the
 * first plan that has a map, plus its steps and (01's) one slot.
 * Nothing is deleted (every delete needs the founder's approval).
 */
import {test, expect, type Page} from '@playwright/test';

const AUTH_TOKEN = process.env.E2E_AUTH_TOKEN ?? process.env.PERFORM_TEST_AUTH_TOKEN;
const PLANNER_API = process.env.VITE_XANO_PLANNER_BASE_URL ?? 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:PE5iDldw';

async function signIn(page: Page): Promise<boolean> {
  if (!AUTH_TOKEN) return false;
  await page.goto('/');
  await page.evaluate((token) => localStorage.setItem('authToken', token), AUTH_TOKEN);
  return true;
}

test('E2E-BOARD-1-01/02: drag a card onto a day; a published day refuses with a sentence', async ({page}) => {
  test.skip(!(await signIn(page)), 'No auth token — see file header.');
  const auth = {Authorization: `Bearer ${AUTH_TOKEN}`};

  // A plan with a map, same deterministic pick as the sibling specs.
  const plans = (await (await page.request.get(`${PLANNER_API}/workspace`, {headers: auth})).json())
    .workspaces as Array<{workspace: {id: number}}>;
  let planId: number | null = null;
  for (const entry of plans) {
    const res = await page.request.get(`${PLANNER_API}/workspace/${entry.workspace.id}/map`, {headers: auth});
    if (((await res.json()).maps as unknown[]).length > 0) {
      planId = entry.workspace.id;
      break;
    }
  }
  test.skip(planId === null, 'No plan in this account has a map attached — add one in Workspace Settings first.');

  await page.goto('/planner');
  await page.locator('#workspace-switcher-btn').click();
  await page.locator(`#workspace-item-${planId}`).click();

  // A fresh job so Unscheduled has a card that is provably this test's.
  const title = `E2E board ${Date.now()}`;
  const modal = page.locator('#jobs-modal');
  await page.locator('[data-testid="jobs-column-new-job"]').click();
  await expect(modal.locator('#new-job-map-select')).toBeVisible();
  await page.waitForLoadState('networkidle');
  await modal.locator('#new-job-title-input').fill(title);
  await modal.locator('#create-job-btn').click();
  await expect(modal.getByText(title, {exact: false}).first()).toBeVisible();
  await modal.getByRole('button', {name: 'Done'}).click();
  await expect(modal).toHaveCount(0);

  // QUE-1 — found in Unscheduled, not the Jobs column (that list is now
  // view-only, every job in the plan — see US-QUE-1-03/04).
  const unscheduled = page.locator('#backlog-drawer-container');
  const jobGroup = unscheduled.getByTestId('unscheduled-job-group').filter({hasText: title}).first();
  await expect(jobGroup).toBeVisible();
  const card = jobGroup.getByTestId('unscheduled-card').first();
  const cardsBefore = await jobGroup.getByTestId('unscheduled-card').count();

  // ── 01: drag onto the first agent's (unpublished) day ────────────────
  //
  // The drop target is whatever the first column offers: an existing
  // task card, the empty-day button, or the "Add task" button of an
  // agent with no day yet — all three accept a job-card payload.
  const dropTarget = page
    .locator('[id^="dayboard-task-"], [id^="create-timeline-"], #day-board-view button:has-text("Add task")')
    .first();
  await expect(dropTarget).toBeVisible();
  await card.getByTestId('unscheduled-card-handle').dragTo(dropTarget);

  await expect(page.locator('#board-notice-toast')).toContainText(/placed as one card/, {timeout: 30_000});
  await page.waitForLoadState('networkidle');
  await expect(jobGroup.getByTestId('unscheduled-card')).toHaveCount(cardsBefore - 1, {timeout: 20_000});
  await expect(
    page.getByTestId('dayboard-job-provenance').filter({hasText: title}).first(),
  ).toBeVisible();

  // ── 02: a published day refuses and the card stays ───────────────────
  //
  // Only runs when the plan actually shows a published column today —
  // publishing a day just to refuse a drop would freeze real test data
  // for every later run. The refusal rule itself is unit-tested
  // (UT-BOARD-1-06); this asserts the sentence reaches the screen.
  const publishedColumn = page.locator('#day-board-view').getByText('Published', {exact: true}).first();
  if ((await publishedColumn.count()) > 0 && (await jobGroup.getByTestId('unscheduled-card').count()) > 0) {
    const remaining = jobGroup.getByTestId('unscheduled-card').first();
    const lockedCard = page
      .locator('[id^="dayboard-task-"]')
      .filter({has: page.locator('.lucide-lock')})
      .first();
    if ((await lockedCard.count()) > 0) {
      const countBefore = await jobGroup.getByTestId('unscheduled-card').count();
      await remaining.getByTestId('unscheduled-card-handle').dragTo(lockedCard);
      await expect(page.locator('#action-error-toast')).toContainText(/published and frozen/);
      await expect(jobGroup.getByTestId('unscheduled-card')).toHaveCount(countBefore);
    }
  }
});
