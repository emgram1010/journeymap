/**
 * items-row.spec.ts — ITEM-1 (US-ITEM-1-04)
 *
 * E2E-ITEM-1-01: add the Items row, choose items, set a stage's cell to
 * per unit, type rates; the cell summary updates and survives a reload.
 * E2E-ITEM-1-02: an out-of-range minutes value is rejected client-side
 * (E-ITM-004) and the typed value stays in the box — never cleared on a
 * rejected save (same rule every cell editor in this app follows).
 * E2E-ITEM-1-03: "Save & Close" persists the Items draft. REGRESSION for
 * the bug found live on map 193 (2026-10-25): it used to run only the
 * generic cell persist, which never saw this editor's draft, so the
 * typing was dropped silently.
 * E2E-ITEM-1-04: the editor's own Save button is actually hittable once
 * item lines are on screen. The same bug had it clipped by the panel's
 * scroll box — 19 of its 32 pixels below the fold, and a click on its
 * centre landing on the "Link to map" label underneath. The two tests
 * above pass with .click(), which auto-scrolls, so only an explicit
 * hit test catches this.
 *
 * FIXTURE: map 215 ("E2E-ITEM-1 fixture clone of item-turnaround — safe
 * to delete"), a dedicated clone of map 193, and two active catalog
 * items on account 2 (`ft-active-item`, `ft-active-item-2`) created for
 * ITEM-1's own live verification. Both are reused rather than duplicated
 * — see ITEM-1's Test Results for how they were made.
 *
 * AUTH comes from the suite's shared storageState (e2e/global-setup.ts,
 * E2E_AUTH_TOKEN) — no per-spec login needed.
 */
import {test, expect, type Page} from '@playwright/test';

const MAP_ID = 215;

async function openMap(page: Page) {
  await page.goto(`/maps/${MAP_ID}`);
  await page.waitForSelector('[class*="tabulator"]', {timeout: 30_000}).catch(() => {});
  await page.waitForTimeout(1_000);

  // PRE-EXISTING BUG (found live building this spec, not an ITEM-1
  // regression): JourneyHealthWidget and the Cell Detail panel are both
  // `fixed right-0 top-12 bottom-0 w-64 z-40` — identical stacking — so
  // whichever mounts later in the DOM intercepts every click on the
  // other, including Save, for ANY cell editor in the app. Closing
  // Journey Health here is the same workaround a real user would need.
  // Flagged separately; out of ITEM-1's scope to fix.
  const healthPanelCloseBtn = page
    .locator('div.flex.items-center.justify-between', {hasText: 'Journey Health'})
    .locator('button')
    .last();
  if (await healthPanelCloseBtn.isVisible().catch(() => false)) {
    await healthPanelCloseBtn.click();
  }
}

async function ensureItemsRow(page: Page) {
  const addItemsRowBtn = page.locator('button', {hasText: 'Add Items Row'});
  await addItemsRowBtn.waitFor({timeout: 15_000});
  if (!(await addItemsRowBtn.isDisabled())) {
    await addItemsRowBtn.click();
    await expect(page.locator('.jm-items-row').first()).toBeVisible({timeout: 15_000});
  } else {
    await expect(page.locator('.jm-items-row').first()).toBeVisible({timeout: 15_000});
  }
}

test.describe('ITEM-1 — Items row', () => {
  test.setTimeout(120_000);

  test('E2E-ITEM-1-01: choose items, set per unit, type rates, summary updates and survives reload', async ({page}) => {
    await openMap(page);
    await ensureItemsRow(page);

    // "Choose items" on the row header.
    await page.locator('.jm-items-choose-btn').first().click();
    const pickerHeading = page.getByRole('heading', {name: 'Choose items'});
    await expect(pickerHeading).toBeVisible({timeout: 10_000});
    await page.locator('label', {hasText: 'FT Active Item'}).first().locator('input[type="checkbox"]').check();
    await page.locator('label', {hasText: 'FT Active Item 2'}).first().locator('input[type="checkbox"]').check();
    await page.locator('div.fixed button', {hasText: 'Save'}).click();
    await expect(pickerHeading).not.toBeVisible({timeout: 10_000});

    // Open the first Items cell (per-stage column) and switch to per unit.
    const itemsCell = page.locator('.jm-grid-cell:has(.jm-items-summary)').first();
    await itemsCell.click();
    await expect(page.locator('text=Time scales with')).toBeVisible({timeout: 10_000});
    await page.locator('input[name="items-scales-with"][value="per_unit"]').check();

    // Switching to per unit with 2 chosen items and no prior lines
    // pre-fills one line per item (US-ITEM-1-04).
    const minuteInputs = page.locator('input[type="number"][placeholder="—"]');
    await expect(minuteInputs).toHaveCount(2, {timeout: 5_000});
    await minuteInputs.nth(0).fill('2.5');
    await minuteInputs.nth(1).fill('4');

    // Exact match — the outer cell-detail panel ALSO has a "Save & Close"
    // button that `hasText: 'Save'` would also match.
    await page.getByRole('button', {name: 'Save', exact: true}).click();

    // The compact cell summary reflects the save.
    await expect(itemsCell.locator('.jm-items-summary')).toHaveText('per unit · 2 lines', {timeout: 10_000});

    // Reload — the summary is read back from the server, not local state.
    await openMap(page);
    const reloadedCell = page.locator('.jm-grid-cell:has(.jm-items-summary)').first();
    await expect(reloadedCell.locator('.jm-items-summary')).toHaveText('per unit · 2 lines', {timeout: 15_000});
  });

  test('E2E-ITEM-1-02: an out-of-range rate is rejected and the typed value stays', async ({page}) => {
    await openMap(page);
    await ensureItemsRow(page);

    // Use the SECOND Items cell so this test doesn't collide with the
    // first test's saved state when the suite runs against the same
    // fixture map.
    const itemsCell = page.locator('.jm-grid-cell:has(.jm-items-summary)').nth(1);
    await itemsCell.click();
    await expect(page.locator('text=Time scales with')).toBeVisible({timeout: 10_000});
    await page.locator('input[name="items-scales-with"][value="per_unit"]').check();

    const minuteInputs = page.locator('input[type="number"][placeholder="—"]');
    await expect(minuteInputs.first()).toBeVisible({timeout: 5_000});
    await minuteInputs.first().fill('9999');
    await page.getByRole('button', {name: 'Save', exact: true}).click();

    await expect(page.locator('text=Enter minutes for one item, like 2.5, or leave it empty for now.')).toBeVisible({
      timeout: 5_000,
    });
    // Never cleared on a rejected save.
    await expect(minuteInputs.first()).toHaveValue('9999');
  });

  // ── Regression: the two ways to save must agree ──────────────────────

  test('E2E-ITEM-1-03: Save & Close persists the Items draft', async ({page}) => {
    await openMap(page);
    await ensureItemsRow(page);

    // A third cell, so this never collides with the two tests above.
    const itemsCell = page.locator('.jm-grid-cell:has(.jm-items-summary)').nth(2);
    await itemsCell.click();
    await expect(page.locator('text=Time scales with')).toBeVisible({timeout: 10_000});
    await page.locator('input[name="items-scales-with"][value="per_unit"]').check();

    const minuteInputs = page.locator('input[type="number"][placeholder="—"]');
    await expect(minuteInputs.first()).toBeVisible({timeout: 5_000});
    const lineCount = await minuteInputs.count();
    await minuteInputs.first().fill('3');

    // The panel's own button — NOT the editor's Save. This is the button a
    // real person reaches for, and the one that used to discard the draft.
    await page.getByRole('button', {name: 'Save & Close', exact: true}).click();
    await expect(page.locator('text=Time scales with')).not.toBeVisible({timeout: 10_000});

    // Read it back from the server, not from local state.
    await openMap(page);
    const reloadedCell = page.locator('.jm-grid-cell:has(.jm-items-summary)').nth(2);
    await expect(reloadedCell.locator('.jm-items-summary')).toHaveText(
      `per unit · ${lineCount} ${lineCount === 1 ? 'line' : 'lines'}`,
      {timeout: 15_000},
    );
  });

  test('E2E-ITEM-1-04: the Save button stays hittable once item lines appear', async ({page}) => {
    await openMap(page);
    await ensureItemsRow(page);

    const itemsCell = page.locator('.jm-grid-cell:has(.jm-items-summary)').nth(3);
    await itemsCell.click();
    await expect(page.locator('text=Time scales with')).toBeVisible({timeout: 10_000});
    await page.locator('input[name="items-scales-with"][value="per_unit"]').check();
    await expect(page.locator('input[type="number"][placeholder="—"]').first()).toBeVisible({timeout: 5_000});

    // What actually broke: the button existed, was "visible" to Playwright,
    // and still could not be clicked by a person, because its own centre
    // belonged to the element painted over it.
    const hit = await page.evaluate(() => {
      const button = Array.from(document.querySelectorAll('button')).find((b) => /^(Save|Saving)/.test(b.textContent?.trim() ?? ''));
      if (!button) return {found: false, hitsSelf: false, topElement: null as string | null};
      const r = button.getBoundingClientRect();
      const atCentre = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      return {
        found: true,
        hitsSelf: button === atCentre || button.contains(atCentre),
        topElement: atCentre ? `${atCentre.tagName}.${String(atCentre.className).slice(0, 40)}` : null,
      };
    });

    expect(hit.found).toBe(true);
    expect(hit.hitsSelf, `Save button's centre is covered by ${hit.topElement}`).toBe(true);
  });
});
