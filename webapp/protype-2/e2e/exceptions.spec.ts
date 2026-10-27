/**
 * exceptions.spec.ts — EXC-1 (phase 7): work leaves the happy path.
 *
 * FIXTURES (all "safe to delete", account 2, built 2026-10-26 — see the
 * epic's Test Results): map 219 (parent, Triage has exception links to
 * 220 / 222 / 218), 220 (published "Repair" map with an Items row), 222
 * (never published), 218 (published, no Items row), 223 (no-items
 * parent), plan 34 ("EXC-1 test plan").
 *
 * AUTH: token injection like the other specs (E2E_AUTH_TOKEN or
 * PERFORM_TEST_AUTH_TOKEN); skips cleanly without one.
 *
 * WRITES REAL DATA in plan 34 only: each run creates one parent job
 * ("EXC-1 e2e parent <ts>") and the child job its send creates.
 *
 * WHY THE SEND FLOW IS DRIVEN FROM THE PLANNER, NOT /perform: the
 * performer screen only shows PUBLISHED days for an agent linked to the
 * signed-in user. The only users in account 2 are the founder and a
 * real teammate, so a perform fixture would put test work into a real
 * person's "My work today". The sheet is ONE component
 * (`exceptions/ExceptionSendPanel`) on both screens; only its trigger
 * differs. The /perform trigger needs a dedicated test login — flagged
 * in the epic's Test Results.
 *
 * REACHABILITY (E2E-EXC-1-06): `.click()` scrolls an element into view
 * and dispatches at it, so it passes on a button no person can press
 * (ITEM-1, 2026-10-25). Every action button here is HIT-TESTED: the
 * element at its own centre must be the button, and no scroll box may
 * clip it.
 */
import {test, expect, type Locator, type Page, type Route} from '@playwright/test';

const AUTH_TOKEN = process.env.E2E_AUTH_TOKEN ?? process.env.PERFORM_TEST_AUTH_TOKEN;
const PLANNER_API = process.env.VITE_XANO_PLANNER_BASE_URL ?? 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:PE5iDldw';
// Each run makes its OWN small plan and archives it afterwards: every
// job in a plan costs the board/backlog an estimate per read (EST-1), and
// a shared plan that grew per run slowed other specs past their timeouts.
// Plan 34 (the build-time fixture plan) is archived for the same reason.
// Fakes are scoped to the Xano host: an unscoped `**/ops/health*` also
// matched the app's own module `src/ops/healthStatus.ts` and blanked the page.
const XANO = 'https://xdjc-i7zz-jhm2.n7e.xano.io';
const PARENT_MAP = 219;
const REPAIR_MAP_TITLE = /EXC-1 Repair fixture/;
const NO_ITEMS_MAP_TITLE = /RATE-1 FT-08 no-Items-row/;

async function signIn(page: Page): Promise<boolean> {
  if (!AUTH_TOKEN) return false;
  await page.goto('/');
  await page.evaluate((token) => localStorage.setItem('authToken', token), AUTH_TOKEN);
  return true;
}

/** A cross-origin fake response the browser will accept (preflight included). */
async function fulfillJson(route: Route, body: unknown) {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  };
  if (route.request().method() === 'OPTIONS') return route.fulfill({status: 204, headers: cors});
  return route.fulfill({status: 200, headers: cors, contentType: 'application/json', body: JSON.stringify(body)});
}

/** The element at the button's own centre is the button, and nothing clips it. */
async function expectHittable(button: Locator) {
  await expect(button).toBeVisible();
  const verdict = await button.evaluate((el) => {
    const r = el.getBoundingClientRect();
    const atCentre = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    // Walk the ancestors that can actually clip: every scroll/overflow box
    // up to and including the first `position: fixed` one. Boxes above a
    // fixed element don't clip it (none of these ancestors is transformed).
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

test.describe('EXC-1 — readiness (US-EXC-1-01)', () => {
  test('E2E-EXC-1-01: the parent map warns about the unpublished and item-less targets; a clean map does not', async ({page}) => {
    test.skip(!(await signIn(page)), 'No auth token — see file header.');

    await page.goto(`/maps/${PARENT_MAP}?arch=31`);
    await page.waitForLoadState('networkidle');
    // The stage header names where Triage can send work.
    await expect(page.locator('.jm-stage-exception-chip').first()).toContainText('exception →');

    await page.getByRole('button', {name: 'Checklist'}).click();
    const warnings = page.getByTestId('exception-warnings');
    await expect(warnings).toBeVisible();
    await expect(warnings).toContainText('has never been published');
    await expect(warnings).toContainText('has no Items row');

    await page.goto('/maps/223?arch=31');
    await page.waitForLoadState('networkidle');
    await page.getByRole('button', {name: 'Checklist'}).click();
    await expect(page.getByTestId('exception-warnings')).toHaveCount(0);
  });
});

test.describe('EXC-1 — send part of a job to a linked map (US-EXC-1-03/05/06)', () => {
  test('E2E-EXC-1-02/03/04/06: refuse with typing kept, send, see the link both ways', async ({page}) => {
    test.setTimeout(180_000);
    test.skip(!(await signIn(page)), 'No auth token — see file header.');
    const auth = {Authorization: `Bearer ${AUTH_TOKEN}`};

    // A fresh plan that accepts the parent map, and a fresh parent with 3
    // items in it, so the test owns its numbers.
    const stamp = Date.now();
    const plan = await (await page.request.post(`${PLANNER_API}/workspace`, {headers: auth, data: {name: `EXC-1 e2e ${stamp}`}})).json();
    const PLAN_ID: number = plan.workspace.id;
    const accepted = await page.request.post(`${PLANNER_API}/workspace/${PLAN_ID}/map`, {headers: auth, data: {map_ids: [PARENT_MAP]}});
    expect(accepted.ok()).toBe(true);
    const title = `EXC-1 e2e parent ${stamp}`;
    const created = await (
      await page.request.post(`${PLANNER_API}/work_item`, {headers: auth, data: {workspace_id: PLAN_ID, journey_map_id: PARENT_MAP, title}})
    ).json();
    const parentId: number = created.work_item.id;
    const linesRes = await page.request.put(`${PLANNER_API}/work-item/${parentId}/lines`, {
      headers: auth,
      data: {lines: [{item_type_id: 13, quantity: 3}]},
    });
    expect(linesRes.ok()).toBe(true);

    await page.goto('/planner');
    await page.locator('#workspace-switcher-btn').click();
    await page.locator(`#workspace-item-${PLAN_ID}`).click();
    await page.locator('#jobs-btn').click();
    const modal = page.locator('#jobs-modal');
    await expect(modal).toBeVisible();
    await page.waitForLoadState('networkidle');

    const row = modal.locator(`#job-row-${parentId}`);
    await row.getByText(title).click();
    // Inline buttons live in a scrolling list, which a person scrolls: bring
    // it on screen the way they would, THEN hit-test. The sheet's confirm
    // gets no such help — it must be reachable as it lands.
    const sendButton = row.getByTestId('exception-send-button');
    await sendButton.scrollIntoViewIfNeeded();
    await expectHittable(sendButton);
    await sendButton.click();

    const sheet = page.getByTestId('exception-sheet');
    await expect(sheet).toBeVisible();

    // Fill EVERYTHING, then prove the confirm button is reachable (E2E-EXC-1-06).
    await sheet.locator('label', {hasText: NO_ITEMS_MAP_TITLE}).locator('input[type=radio]').check();
    await sheet.getByTestId('exception-reason-something_went_wrong').click();
    await sheet.getByRole('button', {name: /More FT Active Item/}).click();
    await sheet.getByRole('button', {name: /More FT Active Item/}).click();
    await sheet.locator('#exception-note').fill('Two are torn');
    const confirm = sheet.getByTestId('exception-confirm');
    await expectHittable(confirm);

    // E2E-EXC-1-03: the server refuses (that map has no Items row) — the
    // message shows and nothing typed is lost.
    await confirm.click();
    await expect(sheet.getByTestId('exception-error')).toContainText("doesn't track items");
    await expect(sheet.getByTestId('exception-reason-something_went_wrong')).toHaveAttribute('aria-pressed', 'true');
    await expect(sheet.locator('#exception-note')).toHaveValue('Two are torn');
    await expect(sheet.getByLabel('FT Active Item to send')).toHaveValue('2');
    await expectHittable(confirm);

    // E2E-EXC-1-02: pick the Repair map and send for real.
    await sheet.locator('label', {hasText: REPAIR_MAP_TITLE}).locator('input[type=radio]').check();
    // The send (~4 s) is followed by the job list's own reload, whose
    // backlog read estimates every job in the plan (~14 s for this 20-job
    // test plan — EST-1's cost, flagged in the epic). Wait for the reload
    // itself rather than a fixed number of seconds.
    const listReloaded = page.waitForResponse((r) => r.url().includes(`/workspace/${PLAN_ID}/backlog_work`), {timeout: 60_000});
    await confirm.click();
    await expect(sheet).toHaveCount(0);
    const toast = row.getByTestId('exception-toast');
    await expect(toast).toContainText('Sent 2 FT Active Item to');
    const childId = Number((await toast.textContent())!.match(/#(\d+)\)/)![1]);
    await listReloaded;
    await expect(row.getByTestId('exception-chip')).toContainText(`2 → #${childId}`);

    // The parent still has 1 left, and its step did not stop (D-1).
    const after = await (await page.request.get(`${PLANNER_API}/work-item/${parentId}/lines`, {headers: auth})).json();
    expect(after.lines.map((l: {quantity: number}) => l.quantity)).toEqual([1]);

    // E2E-EXC-1-04: the child's row says where it came from, and the chip opens the parent.
    const childRow = modal.locator(`#job-row-${childId}`);
    await expect(childRow.getByTestId('job-parent-chip')).toHaveText(`from #${parentId}`);
    await childRow.getByTestId('job-parent-chip').scrollIntoViewIfNeeded();
    await expectHittable(childRow.getByTestId('job-parent-chip'));
    await childRow.getByTestId('job-parent-chip').click();
    await expect(row.getByTestId('exception-chip')).toBeVisible();
    await expect(row.getByTestId('job-children-chip')).toContainText('1 sent on');

    // Tidy up: cancel (never delete) what this run created and archive its
    // plan, so it drops out of the planner's default list (restorable).
    for (const id of [childId, parentId]) {
      await page.request.post(`${PLANNER_API}/work_item/${id}/cancel`, {headers: auth, data: {}});
    }
    await page.request.post(`${PLANNER_API}/workspace/${PLAN_ID}/archive`, {headers: auth, data: {is_archived: true}});
  });
});

test.describe('EXC-1 — Health page (US-EXC-1-07)', () => {
  // RENDER TEST, said plainly: `ops/exceptions` and the /health route both
  // require is_platform_admin, and NO user in this workspace has it (found
  // 2026-10-26 — the founder's own login gets "You don't have access").
  // So this serves the page the panel function's real output (captured
  // live, e2e/fixtures/ops-exceptions-live.json) and presents the signed-in
  // user as an admin. The function itself is tested live in FT-EXC-1-G04 /
  // FT-EXC-1-14; the endpoint's 403 for a non-admin was checked over HTTP.
  test('E2E-EXC-1-05: the Exceptions panel lists the open child with age and reason, and what needs attention', async ({page}) => {
    test.skip(!(await signIn(page)), 'No auth token — see file header.');
    const fixture = (await import('./fixtures/ops-exceptions-live.json', {with: {type: 'json'}})).default;

    // The real signed-in user, presented as a platform admin.
    const meRes = await page.request.get('https://xdjc-i7zz-jhm2.n7e.xano.io/api:RPonubWS/auth/me', {
      headers: {Authorization: `Bearer ${AUTH_TOKEN}`},
    });
    const me = await meRes.json();
    await page.route(`${XANO}/**/auth/me*`, (route) => fulfillJson(route, {...me, is_platform_admin: true}));
    await page.route(`${XANO}/**/ops/health*`, (r) =>
      fulfillJson(r, {last_heartbeat_at: new Date().toISOString(), failures_24h: 0, open_issues_count: 0, checked_at: new Date().toISOString()}),
    );
    await page.route(`${XANO}/**/ops/issues*`, (r) => fulfillJson(r, {issues: []}));
    await page.route(`${XANO}/**/ops/estimates*`, (r) => fulfillJson(r, {since: '', count: 0, jobs: []}));
    await page.route(`${XANO}/**/ops/exceptions*`, (r) => fulfillJson(r, fixture));

    await page.goto('/health');
    const panel = page.getByTestId('health-exceptions');
    await expect(panel).toBeVisible();
    await expect(panel.getByTestId('health-exception-row').first()).toContainText(
      'EXC-1 parent A (safe to delete) (#56) sent 2 items to EXC-1 Repair fixture — safe to delete (#57) at Triage, today — still open.',
    );
    await expect(panel.getByTestId('health-exception-row').first()).toContainText('Why: Something went wrong — “Two are torn”');
    await expect(panel.getByTestId('health-exception-row').nth(1)).toContainText('(a child of a child)');
    const attention = panel.getByTestId('health-exceptions-attention');
    await expect(attention).toContainText('Order #56 was cancelled');
    await expect(attention).toContainText('has never been published');
    await expect(attention).toContainText('E-EXC-008 × 5');
  });
});
