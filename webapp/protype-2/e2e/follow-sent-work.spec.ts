/**
 * follow-sent-work.spec.ts — EXC-2 (US-EXC-2-03/04/05): opening a sent
 * job's read-only view from a chip, and the reachability of every new
 * tappable thing.
 *
 * FIXTURES: reuses EXC-1's "safe to delete" maps (219 parent → 220
 * Repair, via the Triage stage's exception link) exactly as
 * `exceptions.spec.ts` does — see that file's header for the map
 * layout. Each run makes its own plan/parent/child and archives/cancels
 * them at the end (standing permission for test fixtures).
 *
 * AUTH: same token injection as the other specs; skips cleanly without
 * one.
 *
 * WHY THIS RUNS THE SEND FROM THE PLANNER, NOT /perform: same reason as
 * `exceptions.spec.ts` — the only two users in account 2 are real people,
 * and /perform only shows an agent's own published day. There is still
 * no dedicated test login for the performer app this session, so
 * E2E-EXC-2-01/02 (the performer-side "sent" chip and "Came from" chip,
 * at 375 px on /perform) are NOT covered here — flagged in the epic's
 * Test Results as a gap, exactly like EXC-1's E2E-EXC-1-02/03/04/06
 * header already flags for the send flow itself. What IS covered here,
 * on the SAME shared components (D-2 — `JobPeekSheet` and the chip
 * button are not different code between modules, only their trigger
 * screen differs): the exception chip is a real, reachable button; it
 * carries a progress short-label; tapping it opens `JobPeekSheet`
 * read-only with the child's steps and a "Now" marker; the sheet's
 * footer Close is reachable and returns cleanly.
 */
import {test, expect, type Locator, type Page} from '@playwright/test';

const AUTH_TOKEN = process.env.E2E_AUTH_TOKEN ?? process.env.PERFORM_TEST_AUTH_TOKEN;
const PLANNER_API = process.env.VITE_XANO_PLANNER_BASE_URL ?? 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:PE5iDldw';
const PARENT_MAP = 219;
const NO_ITEMS_MAP_TITLE = /RATE-1 FT-08 no-Items-row/;

async function signIn(page: Page): Promise<boolean> {
  if (!AUTH_TOKEN) return false;
  await page.goto('/');
  await page.evaluate((token) => localStorage.setItem('authToken', token), AUTH_TOKEN);
  return true;
}

/** Same hit-test as exceptions.spec.ts (E2E-EXC-1-06 / E2E-EXC-2-05): the
 * element at its own centre must be the button, unclipped by any scroll
 * box up to the first `position: fixed` ancestor, and on screen. */
async function expectHittable(button: Locator) {
  await expect(button).toBeVisible();
  const verdict = await button.evaluate((el) => {
    const r = el.getBoundingClientRect();
    const atCentre = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    let clipped = 0;
    for (let p = el.parentElement; p; p = p.parentElement) {
      const style = getComputedStyle(p);
      if (!(style.overflow === 'visible' && style.overflowY === 'visible')) {
        const pr = p.getBoundingClientRect();
        clipped = Math.max(clipped, pr.top - r.top, r.bottom - pr.bottom, 0);
      }
      if (style.position === 'fixed') break;
    }
    return {
      hit: atCentre === el || el.contains(atCentre),
      clipped,
      inViewport: r.top >= 0 && r.bottom <= window.innerHeight,
    };
  });
  expect(verdict.hit, 'the button itself is what a tap at its centre lands on').toBe(true);
  expect(verdict.clipped, 'no scroll box clips the button').toBe(0);
  expect(verdict.inViewport, 'the button is on screen without scrolling').toBe(true);
}

test.describe('EXC-2 — sent chip opens the read-only view (US-EXC-2-03/04)', () => {
  test('E2E-EXC-2-03/04 (desktop, planner path): the exception chip is a reachable button with a progress label, and opens JobPeekSheet', async ({page}) => {
    test.setTimeout(180_000);
    test.skip(!(await signIn(page)), 'No auth token — see file header.');
    const auth = {Authorization: `Bearer ${AUTH_TOKEN}`};

    const stamp = Date.now();
    const plan = await (await page.request.post(`${PLANNER_API}/workspace`, {headers: auth, data: {name: `EXC-2 e2e ${stamp}`}})).json();
    const PLAN_ID: number = plan.workspace.id;
    await page.request.post(`${PLANNER_API}/workspace/${PLAN_ID}/map`, {headers: auth, data: {map_ids: [PARENT_MAP]}});
    const title = `EXC-2 e2e parent ${stamp}`;
    const created = await (
      await page.request.post(`${PLANNER_API}/work_item`, {headers: auth, data: {workspace_id: PLAN_ID, journey_map_id: PARENT_MAP, title}})
    ).json();
    const parentId: number = created.work_item.id;
    await page.request.put(`${PLANNER_API}/work-item/${parentId}/lines`, {headers: auth, data: {lines: [{item_type_id: 13, quantity: 2}]}});

    await page.goto('/planner');
    await page.locator('#workspace-switcher-btn').click();
    await page.locator(`#workspace-item-${PLAN_ID}`).click();
    await page.locator('#jobs-btn').click();
    const modal = page.locator('#jobs-modal');
    await expect(modal).toBeVisible();
    await page.waitForLoadState('networkidle');

    const row = modal.locator(`#job-row-${parentId}`);
    await row.getByText(title).click();
    const sendButton = row.getByTestId('exception-send-button');
    await sendButton.scrollIntoViewIfNeeded();
    await sendButton.click();

    const sheet = page.getByTestId('exception-sheet');
    await expect(sheet).toBeVisible();
    await sheet.locator('label', {hasText: NO_ITEMS_MAP_TITLE}).locator('input[type=radio]').check();
    await sheet.getByTestId('exception-reason-something_went_wrong').click();
    await sheet.getByRole('button', {name: /More FT Active Item/}).click();
    const confirm = sheet.getByTestId('exception-confirm');
    const listReloaded = page.waitForResponse((r) => r.url().includes(`/workspace/${PLAN_ID}/backlog_work`), {timeout: 60_000});
    await confirm.click();
    await expect(sheet).toHaveCount(0);
    const toast = row.getByTestId('exception-toast');
    const childId = Number((await toast.textContent())!.match(/#(\d+)\)/)![1]);
    await listReloaded;

    // US-EXC-2-03: the chip is a real button, carries "0 of N", and is reachable.
    const chip = row.getByTestId('exception-chip');
    await expect(chip).toHaveText(/1 → #\d+ · .* · 0 of \d+/);
    await expect(chip).toHaveAttribute('aria-label', `Open sent job #${childId}`);
    await chip.scrollIntoViewIfNeeded();
    await expectHittable(chip);

    // Tapping it opens the shared, read-only JobPeekSheet (D-2) — same
    // component the performer's chip and "Came from" chip open.
    await chip.click();
    const peek = page.getByTestId('job-peek-sheet');
    await expect(peek).toBeVisible();
    await expect(peek.getByTestId('job-peek-title')).not.toBeEmpty();
    await expect(peek.getByTestId('job-peek-progress')).toContainText('0 of');
    await expect(peek.getByTestId('job-peek-steps')).toBeVisible();
    await expect(peek.getByTestId('job-peek-step').first()).toContainText('Now');
    // Read-only: no action button anywhere in the sheet.
    await expect(peek.getByRole('button', {name: /^(Start|Done|Block|Skip|Resume|Reopen)$/})).toHaveCount(0);

    const close = peek.getByTestId('job-peek-footer-close');
    await expectHittable(close);
    await close.click();
    await expect(peek).toHaveCount(0);
    // Closing returns to the planner exactly where it was (nothing changed).
    await expect(row.getByTestId('exception-chip')).toBeVisible();

    for (const id of [childId, parentId]) {
      await page.request.post(`${PLANNER_API}/work_item/${id}/cancel`, {headers: auth, data: {}});
    }
    await page.request.post(`${PLANNER_API}/workspace/${PLAN_ID}/archive`, {headers: auth, data: {is_archived: true}});
  });
});
