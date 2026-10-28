/**
 * card-scheduling.spec.ts — BLK-1 / US-BLK-1-07.
 *
 * ONE CARD, NOT EIGHT ROWS, DRIVEN THROUGH THE REAL SCREEN. Stories
 * 01–03 built the card endpoints and proved them over HTTP; story 07
 * pointed the planner's own Jobs screen at them. This drives that
 * screen, because the lesson from the walkthrough that produced
 * `jobs-and-day-navigation.spec.ts` applies exactly here: the backend
 * passed its own tests and the loop still did not join up, because
 * nobody had clicked the buttons.
 *
 * WHAT IT PROVES, in one pass (BOARD-1 moved the screen: the backlog is
 * the Jobs COLUMN beside the board now, and Unschedule lives on the
 * day's own card — the semantics being proven are unchanged):
 *   - a job's steps for one actor row arrive as ONE card in the Jobs column
 *   - the card can be expanded to read every stage it covers
 *   - Place… creates ONE slot covering every step, positioned 1..n
 *   - the placed card leaves the Jobs column
 *   - the day board shows it ONCE, with one Unschedule
 *   - Unschedule releases EVERY step and leaves no orphan link
 *
 * The orphan check is the one that matters most. Before story 03 the
 * cascade deleted one link and the whole slot, which would have left a
 * card's other steps pointing at a slot that no longer existed —
 * invisible to the backlog forever, with nothing logged.
 *
 * AUTH: token injection, same as the sibling specs. Set E2E_AUTH_TOKEN
 * (or PERFORM_TEST_AUTH_TOKEN); the spec skips cleanly without one.
 *
 * WRITES REAL DATA: leaves one job named "E2E card <timestamp>" per map
 * it had to try, plus the steps those jobs generate, in the first plan
 * that has maps. Nothing is deleted (every delete needs the founder's
 * approval).
 */
import {test, expect, type Page} from '@playwright/test';

const AUTH_TOKEN = process.env.E2E_AUTH_TOKEN ?? process.env.PERFORM_TEST_AUTH_TOKEN;

/** Same planner group the app itself targets — see `perform/performApi.ts`. */
const PLANNER_API = process.env.VITE_XANO_PLANNER_BASE_URL ?? 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:PE5iDldw';

interface BacklogCard {
  card_key: string;
  work_item_id: number;
  job_title: string | null;
  lens_key: string;
  lens_label: string;
  step_count: number;
  expected_minutes: number;
  work_task_ids: number[];
  steps: Array<{work_task_id: number; stage_label: string; expected_minutes: number | null}>;
}

interface LinkedStep {
  planner_task_id: number;
  work_task_id: number;
  position?: number | null;
}

async function signIn(page: Page): Promise<boolean> {
  if (!AUTH_TOKEN) return false;
  await page.goto('/');
  await page.evaluate((token) => localStorage.setItem('authToken', token), AUTH_TOKEN);
  return true;
}

test('E2E-BLK-1-07-01: place a whole card on a day from the Jobs screen, then release every step of it', async ({
  page,
}) => {
  test.skip(!(await signIn(page)), 'No auth token — see file header.');
  const auth = {Authorization: `Bearer ${AUTH_TOKEN}`};

  const readBacklog = async (planId: number): Promise<BacklogCard[]> => {
    const res = await page.request.get(`${PLANNER_API}/workspace/${planId}/backlog_work`, {headers: auth});
    return (await res.json()).backlog as BacklogCard[];
  };
  const readLinkedSteps = async (planId: number): Promise<LinkedStep[]> => {
    const res = await page.request.get(`${PLANNER_API}/workspace/${planId}/board`, {headers: auth});
    return ((await res.json()).linked_steps ?? []) as LinkedStep[];
  };

  // WHICH PLAN? The same reasoning as the sibling spec: a job needs a
  // plan that accepts at least one published map, and the planner opens
  // on whichever plan comes first, which may not be one. Ask the API,
  // then select that plan by id — the thing under test is still driven
  // entirely through the UI.
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
  await expect(page.locator('#workspace-switcher-btn')).toBeVisible();
  await page.locator('#workspace-switcher-btn').click();
  await page.locator(`#workspace-item-${planId}`).click();

  const modal = page.locator('#jobs-modal');
  await page.locator('#jobs-btn').click();
  await expect(modal).toBeVisible();
  await expect(modal.locator('#new-job-map-select')).toBeVisible();
  await page.waitForLoadState('networkidle');

  // A CARD WORTH TESTING NEEDS AN ACTOR ROW WITH MORE THAN ONE STAGE,
  // and only the map decides that. Rather than hardcode a map id that
  // will rot, try the plan's maps in turn until one produces a
  // multi-step card. A draft-only map is refused by the server
  // (E-JOB-003) and simply moves the loop on.
  const mapValues = await modal.locator('#new-job-map-select option').evaluateAll((options) =>
    options.map((o) => (o as HTMLOptionElement).value),
  );
  expect(mapValues.length, 'the plan should offer at least one map').toBeGreaterThan(0);

  let card: BacklogCard | null = null;
  let jobTitle = '';
  const attempts: string[] = [];
  for (const mapValue of mapValues.slice(0, 4)) {
    jobTitle = `E2E card ${Date.now()}`;
    await modal.locator('#new-job-map-select').selectOption(mapValue);
    await modal.locator('#new-job-title-input').fill(jobTitle);
    await modal.locator('#create-job-btn').click();
    // The create refetches all three of this modal's lists; typing or
    // clicking into one still re-rendering detaches the node (the
    // sibling spec's own hard-won note).
    await page.waitForLoadState('networkidle');
    await expect(modal.locator('#create-job-btn')).toBeEnabled();

    // THE BACKLOG IS THE AUTHORITY, not the notice banner. An earlier
    // version of this loop checked for the "pinned to version" notice,
    // which is still on screen from the PREVIOUS successful create —
    // so a refusal read as a success and the loop moved on without
    // ever trying the map that would have worked.
    const cards = (await readBacklog(planId as number)).filter((c) => c.job_title === jobTitle);
    if (cards.length === 0) {
      const banner = (await modal.locator('p.text-red-600').first().textContent().catch(() => null)) ?? 'no error shown';
      attempts.push(`map ${mapValue}: no job created (${banner.trim()})`);
      continue;
    }

    const best = cards.sort((a, b) => b.step_count - a.step_count)[0];
    attempts.push(`map ${mapValue}: biggest card ${best.step_count} step(s)`);
    if (best.step_count > 1) {
      card = best;
      break;
    }
  }

  // Nothing pretends to pass: if no map in this plan has an actor row
  // with two stages, the card behaviour cannot be proven and this is a
  // failure of the fixture, not a reason to go green.
  expect(
    card,
    `no map in this plan produced a card with more than one step — the card path cannot be proven without one. Tried: ${attempts.join('; ')}`,
  ).not.toBeNull();
  const multi = card as BacklogCard;
  const stepCount = multi.step_count;

  // ── BOARD-1: scheduling lives on the board, not in the modal ─────────
  await modal.getByRole('button', {name: 'Close'}).click();
  await expect(modal).toBeHidden();
  await page.waitForLoadState('networkidle');

  // ── The Jobs column offers ONE card for those steps, under its job ───
  //
  // Identified by its "N steps" text, because the same job also produces
  // a one-step card for its other actor row — and telling those two
  // apart IS the (job, actor row) rule being tested.
  const stepWord = stepCount === 1 ? 'step' : 'steps';
  const column = page.locator('#jobs-column');
  const jobGroup = column.getByTestId('jobs-column-job').filter({hasText: jobTitle}).first();
  await expect(jobGroup).toBeVisible();
  const cardRow = jobGroup
    .getByTestId('jobs-column-card')
    .filter({hasText: `${stepCount} ${stepWord}`})
    .first();
  await expect(cardRow).toBeVisible();
  // The card names the ACTOR ROW, not just the job: "Clerk · 2 steps ·
  // 1 hr 44 min". That is the (job, actor row) rule showing on screen.
  await expect(
    cardRow.getByText(`${multi.lens_label || multi.lens_key} · ${stepCount} ${stepWord}`, {exact: false}),
  ).toBeVisible();

  // THE SAME JOB'S OTHER ACTOR ROW IS A SEPARATE, ONE-STEP CARD under
  // the same job header. Grouping by job alone would have offered one
  // row mixing two roles; it also guards the pluralisation.
  if ((await readBacklog(planId as number)).filter((c) => c.job_title === jobTitle).length > 1) {
    await expect(jobGroup.getByTestId('jobs-column-card').filter({hasText: '1 step ·'}).first()).toBeVisible();
  }

  // Expanding it reads every stage the card covers, from the job's
  // PINNED version.
  await cardRow.getByRole('button', {name: "Show this card's steps"}).click();
  for (const step of multi.steps) {
    await expect(cardRow.getByText(step.stage_label, {exact: false}).first()).toBeVisible();
  }

  // ── Place it: ONE call, ONE slot, every step ─────────────────────────
  //
  // The click path (D-4). The day is set to the one the board is
  // showing, so the placed slot is on screen for the release below.
  const activeDay = await page.locator('#day-board-view').getAttribute('data-active-day');
  const linksBefore = await readLinkedSteps(planId as number);
  await cardRow.getByTestId('jobs-column-place').click();
  await expect(cardRow.getByText(`All ${stepCount} ${stepWord} go onto that day as one card.`)).toBeVisible();
  await cardRow.locator('input[type=date]').fill(activeDay!);
  await cardRow.getByTestId('jobs-column-place-confirm').click();

  await expect(page.locator('#board-notice-toast')).toContainText(
    new RegExp(`${stepCount} ${stepWord} placed as one card`),
  );
  await page.waitForLoadState('networkidle');

  // One slot, not `stepCount` slots — and positioned 1..n, which is
  // what makes the performer walk the stages in the order the version
  // agreed (ORD-1 made that order mutable).
  const linksAfter = await readLinkedSteps(planId as number);
  const newLinks = linksAfter.filter((l) => !linksBefore.some((b) => b.work_task_id === l.work_task_id));
  expect(newLinks.length, 'every step of the card should now be linked').toBe(stepCount);
  expect(new Set(newLinks.map((l) => l.planner_task_id)).size, 'all of them to ONE slot').toBe(1);
  expect(
    newLinks
      .map((l) => l.position ?? 0)
      .sort((a, b) => a - b),
    'positions should be 1..n',
  ).toEqual(Array.from({length: stepCount}, (_, i) => i + 1));
  expect(
    new Set(newLinks.map((l) => l.work_task_id)),
    'exactly the steps the card named',
  ).toEqual(new Set(multi.work_task_ids));

  // The placed card leaves the Jobs column — all of it, not part of it.
  const backlogAfter = await readBacklog(planId as number);
  expect(
    backlogAfter.some((c) => c.card_key === multi.card_key),
    'a scheduled card should not still be offered for scheduling',
  ).toBe(false);
  await expect(jobGroup.getByTestId('jobs-column-card').filter({hasText: `${stepCount} ${stepWord}`})).toHaveCount(0);

  // ── The day board shows it ONCE, saying what it is ───────────────────
  //
  // 🔴 The provenance line is the `adaptBoard` lesson from BLK-1: its
  // linked-steps Map once kept only whichever step came back last, so a
  // card rendered one arbitrary stage as though it were the whole slot.
  // One slot = one card on the board = one Unschedule; a card listed
  // once per step would offer two buttons for one slot, and pressing
  // either would release both.
  const slotId = newLinks[0].planner_task_id;
  const provenance = page
    .getByTestId('dayboard-job-provenance')
    .filter({hasText: `${jobTitle} · ${stepCount} ${stepWord}`});
  await expect(provenance).toHaveCount(1);
  const slotCard = page.locator('[id^="dayboard-task-"]').filter({has: provenance}).first();

  // ── Release it: every step comes back, no orphan link ────────────────
  await slotCard.getByTitle('Task actions').click();
  await page.getByTestId('dayboard-unschedule-card').click();
  await expect(page.locator('#board-notice-toast')).toContainText(
    new RegExp(`${stepCount} ${stepWord} back in the Jobs column`),
  );
  await page.waitForLoadState('networkidle');

  const linksReleased = await readLinkedSteps(planId as number);
  expect(
    linksReleased.filter((l) => l.planner_task_id === slotId),
    'no link may point at a slot that has been deleted',
  ).toEqual([]);

  const backlogReleased = await readBacklog(planId as number);
  const returned = backlogReleased.find((c) => c.card_key === multi.card_key);
  expect(returned, 'the card should be waiting for a day again').toBeTruthy();
  expect((returned as BacklogCard).step_count, 'and whole, not partly stranded').toBe(stepCount);
});
