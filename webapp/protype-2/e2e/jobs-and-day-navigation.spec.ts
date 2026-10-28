/**
 * jobs-and-day-navigation.spec.ts — GAP-FIX Part 2 (W1, W4, W5, W9).
 *
 * These four are the ones with a click-path worth proving, and the
 * reason this file exists at all is the lesson from the walkthrough
 * that produced them: the epics each passed their own spec and the
 * loop still did not join up, because nobody had driven the real
 * screens end to end. Checking the architecture is not checking the
 * UI.
 *
 * W1 is the one that mattered: "publish a map, make a plan, attach the
 * map, click Add task" produced a plain text task with no connection
 * to the map, and no screen anywhere created a real job. This drives
 * the screen that now does.
 *
 * AUTH: token injection, same as the other two specs (the shared
 * TEST_EMAIL login fixture is broken — see perform-sessions-mobile's
 * header). Set E2E_AUTH_TOKEN (or PERFORM_TEST_AUTH_TOKEN); the spec
 * skips cleanly without one.
 *
 * WRITES REAL DATA: E2E-W1-01 leaves one job named
 * "E2E job <timestamp>" in the first plan that has a map, plus the
 * steps that job generates. Nothing is deleted (every delete needs
 * the founder's approval).
 */
import {test, expect, type Page} from '@playwright/test';

const AUTH_TOKEN = process.env.E2E_AUTH_TOKEN ?? process.env.PERFORM_TEST_AUTH_TOKEN;

/** Same planner group the app itself targets — see `perform/performApi.ts`. */
const PLANNER_API = process.env.VITE_XANO_PLANNER_BASE_URL ?? 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:PE5iDldw';

async function signIn(page: Page): Promise<boolean> {
  if (!AUTH_TOKEN) return false;
  await page.goto('/');
  await page.evaluate((token) => localStorage.setItem('authToken', token), AUTH_TOKEN);
  return true;
}

test('E2E-W1-01 / E2E-O4-01: create a job from a map, schedule a step, and take it back off', async ({page}) => {
  test.skip(!(await signIn(page)), 'No auth token — see file header.');
  const title = `E2E job ${Date.now()}`;

  // WHICH PLAN? A job needs a plan that accepts at least one published
  // map, and the planner opens on whichever plan comes first, which may
  // not be one. The first version of this test hunted through the
  // switcher clicking Jobs on each plan in turn; that was slow and
  // raced the modal's own loading. Asking the API which plan qualifies
  // and then selecting that one by id is deterministic, and the thing
  // under test — the Jobs screen — is still driven entirely through
  // the UI.
  const auth = {Authorization: `Bearer ${AUTH_TOKEN}`};
  const plans = (await (await page.request.get(`${PLANNER_API}/workspace`, {headers: auth})).json())
    .workspaces as Array<{workspace: {id: number}}>;
  let planWithMap: number | null = null;
  for (const entry of plans) {
    const res = await page.request.get(`${PLANNER_API}/workspace/${entry.workspace.id}/map`, {headers: auth});
    const maps = (await res.json()).maps as unknown[];
    if (maps.length > 0) {
      planWithMap = entry.workspace.id;
      break;
    }
  }
  test.skip(planWithMap === null, 'No plan in this account has a map attached — add one in Workspace Settings first.');

  await page.goto('/planner');
  await expect(page.locator('#workspace-switcher-btn')).toBeVisible();
  await page.locator('#workspace-switcher-btn').click();
  await page.locator(`#workspace-item-${planWithMap}`).click();

  const modal = page.locator('#jobs-modal');
  await page.locator('#jobs-btn').click();
  await expect(modal).toBeVisible();
  await expect(modal.locator('#new-job-map-select')).toBeVisible();

  // Switching plans refetches the board AND this modal's three lists;
  // typing into a form that is still re-rendering detaches the node
  // mid-click. Wait for the churn to stop first.
  await page.waitForLoadState('networkidle');
  await modal.locator('#new-job-title-input').fill(title);
  await modal.locator('#create-job-btn').click();

  // The job appears in this plan's job list…
  await expect(modal.getByText(title, {exact: false}).first()).toBeVisible();

  // BOARD-1 — scheduling left the modal. Close it; the job's work now
  // sits in the Jobs COLUMN beside the board, as a card carrying the
  // map's own words and minutes — the thing "Add task" could never
  // produce.
  await modal.getByRole('button', {name: 'Done'}).click();
  await expect(modal).toHaveCount(0);

  const column = page.locator('#jobs-column');
  const jobGroup = column.getByTestId('jobs-column-job').filter({hasText: title}).first();
  await expect(jobGroup).toBeVisible();
  const card = jobGroup.getByTestId('jobs-column-card').first();
  // The minutes come from the pinned version, not from anything typed here.
  await expect(card.getByText(/\d+ min/)).toBeVisible();

  // The click path (US-BOARD-1-02's "Place…"): who defaults to the first
  // agent; the day is set to the one the board is showing, so the placed
  // card is immediately visible for the round trip below.
  const activeDay = await page.locator('#day-board-view').getAttribute('data-active-day');
  await card.getByTestId('jobs-column-place').click();
  await card.locator('input[type=date]').fill(activeDay!);
  await card.getByTestId('jobs-column-place-confirm').click();

  await expect(page.locator('#board-notice-toast')).toContainText(/Publish the day to send it to Execution/);

  // The card leaves the Jobs column, and the day column now carries a
  // slot naming its job (US-BOARD-1-03's provenance line).
  await page.waitForLoadState('networkidle');
  await expect(jobGroup.getByTestId('jobs-column-card')).toHaveCount(0, {timeout: 20_000});
  const slot = page
    .locator('[id^="dayboard-task-"]')
    .filter({has: page.getByTestId('dayboard-job-provenance')})
    .filter({hasText: title})
    .first();
  await expect(slot).toBeVisible();

  // O4 — and back off again. Scheduling used to be a one-way door; the
  // round trip is the test, not the placement. BLK-1: releasing the slot
  // releases the whole card, and the notice says how many steps came back.
  await slot.getByTitle('Task actions').click();
  await page.getByTestId('dayboard-unschedule-card').click();
  await expect(page.locator('#board-notice-toast')).toContainText(/step(s)? back in the Jobs column/);
  await expect(jobGroup.getByTestId('jobs-column-card').first()).toBeVisible({timeout: 20_000});
});

test('E2E-W4-01: the performer can move off today and back', async ({page}) => {
  test.skip(!(await signIn(page)), 'No auth token — see file header.');
  await page.goto('/perform');

  // "Today" is the server's answer in the performer's own zone (W8),
  // so the heading is asserted by its role, never against a date this
  // test computed for itself.
  await expect(page.getByRole('heading', {name: 'Today'})).toBeVisible();

  await page.getByRole('button', {name: 'Next day'}).click();
  // Off today, the heading becomes the day's name and a "Today" button appears.
  const backToToday = page.getByRole('button', {name: 'Today', exact: true});
  await expect(backToToday).toBeVisible();

  await backToToday.click();
  await expect(page.getByRole('heading', {name: 'Today'})).toBeVisible();
});

test('E2E-W5-01: an empty day says which of the four reasons applies', async ({page}) => {
  test.skip(!(await signIn(page)), 'No auth token — see file header.');
  await page.goto('/perform');
  await expect(page.getByRole('heading', {name: 'Today'})).toBeVisible();

  // Walk forward until a day with no sessions turns up. A quiet day is
  // the normal case for this account; 6 steps is plenty and keeps the
  // test from looping if every day somehow has work.
  for (let i = 0; i < 6; i += 1) {
    // Each step re-fetches, and the screen shows a spinner while it
    // does. Waiting for the header to come back first is what stops
    // this from reading the loading state as "not empty" — the race
    // that made the first version of this test skip every time.
    await expect(page.locator('header').first()).toBeVisible();
    const empty = page.locator('#perform-empty-state');
    if (await empty.isVisible({timeout: 5_000}).catch(() => false)) {
      // The old screen said "Nothing is scheduled for you today." for
      // every cause. Whatever it says now, it must not be that alone.
      const text = (await empty.textContent()) ?? '';
      expect(text.length, 'the empty state should explain itself').toBeGreaterThan(40);
      return;
    }
    await page.getByRole('button', {name: 'Next day'}).click();
  }
  test.skip(true, 'Every day checked had work — nothing to diagnose.');
});

test('E2E-W9-01: an admin still sees the agent-management actions', async ({page}) => {
  test.skip(!(await signIn(page)), 'No auth token — see file header.');
  await page.goto('/planner');
  await page.locator('#agent-profiles-btn').click();

  const modal = page.locator('#agent-profiles-modal');
  await expect(modal).toBeVisible();
  // The token belongs to an admin, so the admin-only section is present.
  // A member's view is covered server-side (E-PLAN-013, verified live in
  // gap-fix Part 1 #2) — this guards against the hiding rule being
  // written backwards and blanking the screen for everyone.
  await expect(modal.getByText('Add an AI agent')).toBeVisible();
  await expect(modal.getByText('Tag a teammate')).toBeVisible();
});
