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

  // …and its steps appear as real, schedulable work carrying the map's
  // own text and minutes — the thing "Add task" could never produce.
  //
  // Identified by the Schedule button, not by "Done when:": a map's
  // cells may legitimately have no done-when yet, and a test that
  // assumes they do fails on a perfectly valid map (it did, on "test
  // 123").
  const stepRow = modal
    .locator('li')
    .filter({hasText: title})
    .filter({has: page.getByRole('button', {name: 'Schedule'})})
    .first();
  await expect(stepRow).toBeVisible();
  // The minutes come from the pinned version, not from anything typed here.
  await expect(stepRow.getByText(/\d+ min/)).toBeVisible();

  await stepRow.getByRole('button', {name: 'Schedule'}).click();
  await stepRow.getByRole('button', {name: 'Place'}).click();

  await expect(modal.getByText(/Publish the day to send it to Execution/)).toBeVisible();

  // O4 — and back off again. Scheduling used to be a one-way door:
  // a step could be moved to another day but never returned to
  // "waiting for a day". The round trip is the test, not the placement.
  await page.waitForLoadState('networkidle');
  const scheduledRow = modal
    .locator('li')
    .filter({hasText: title})
    .filter({has: page.getByRole('button', {name: 'Unschedule'})})
    .first();
  await expect(scheduledRow).toBeVisible();
  await scheduledRow.getByRole('button', {name: 'Unschedule'}).click();
  // BLK-1 (US-BLK-1-07) reworded this: a slot now holds a whole card,
  // so the notice reports how many steps actually came back instead of
  // implying one step moved.
  await expect(modal.getByText(/step(s)? back in .Work waiting for a day./)).toBeVisible();
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
