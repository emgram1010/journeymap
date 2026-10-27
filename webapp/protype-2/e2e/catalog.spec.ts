/**
 * catalog.spec.ts — CAT-1 (US-CAT-1-04)
 *
 * E2E-CAT-1-01: add an item + a method, set the item's default method,
 * deactivate the item, see it hidden, re-show it with the toggle.
 * E2E-CAT-1-02: save with a bad key — the message shows, the label and
 * other fields keep what was typed.
 *
 * AUTH: the repo's shared TEST_EMAIL/TEST_PASSWORD UI-login fixture is
 * broken in this environment — already documented in
 * perform-sessions-mobile.spec.ts and health-page.spec.ts, confirmed
 * again here (both tests timed out on the login form, stuck on a
 * disabled Sign-in button). Not a CAT-1 regression. Using the same
 * workaround: inject a real bearer token into localStorage (the
 * `authToken` key `xano.ts::getAuthToken` reads) from
 * CATALOG_TEST_AUTH_TOKEN, minted the same way CLAUDE.md documents for
 * backend HTTP testing (generate_magic_link + reset/magic-link-login).
 * Skips with a clear reason when that's not set.
 */
import {test, expect, type Page} from '@playwright/test';

const AUTH_TOKEN = process.env.CATALOG_TEST_AUTH_TOKEN;

async function ensureLoggedIn(page: Page): Promise<boolean> {
  if (!AUTH_TOKEN) return false;
  await page.goto('/');
  await page.evaluate((token) => localStorage.setItem('authToken', token), AUTH_TOKEN);
  return true;
}

test('E2E-CAT-1-01: add item + method, set default, deactivate, toggle', async ({page}) => {
  const loggedIn = await ensureLoggedIn(page);
  test.skip(!loggedIn, 'CATALOG_TEST_AUTH_TOKEN not set — see file header for how to mint one.');
  await page.goto('/settings/catalog');

  const suffix = Date.now().toString(36);
  const itemLabel = `E2E Chair ${suffix}`;
  const methodLabel = `E2E Method ${suffix}`;

  // Add a method first, so it's available as the item's default.
  await page.click('button:has-text("Methods")');
  await page.fill('input[placeholder^="Label, e.g. Hard goods"]', methodLabel);
  await page.click('button:has-text("Add method")');
  await expect(page.locator('li', {hasText: methodLabel})).toBeVisible({timeout: 10_000});

  // Add the item, then set its default method via the edit form.
  await page.click('button:has-text("Items")');
  await page.fill('input[placeholder^="Label, e.g. 6-ft"]', itemLabel);
  await page.click('button:has-text("Add item")');
  const itemRow = page.locator('li', {hasText: itemLabel});
  await expect(itemRow).toBeVisible({timeout: 10_000});

  await itemRow.locator('button:has-text("Edit")').click();
  // itemRow (hasText) stops matching once editing starts: the label moves
  // into an <input value="...">, which doesn't count as text content for
  // `hasText`. Re-scope by presence of that input instead (`has` checks
  // for a matching descendant, not rendered text).
  const editingRow = page.locator('li').filter({has: page.locator(`input[value="${itemLabel}"]`)});
  await editingRow.locator('select').nth(1).selectOption({label: methodLabel});
  await editingRow.locator('button:has-text("Save")').click();
  await expect(itemRow.locator('button:has-text("Edit")')).toBeVisible();

  // Deactivate — confirm dialog, then the row disappears from the
  // default (active-only) list entirely, since `showInactive` defaults
  // to false and nothing auto-enables it (correct product behaviour —
  // confirmed in CatalogPage.tsx; an earlier version of this comment
  // assumed otherwise and that was a bug in the TEST, not the product).
  // Turn the toggle on FIRST so the row stays visible to check "inactive".
  const showInactiveToggle = page.locator('label:has-text("Show deactivated") input[type="checkbox"]');
  await showInactiveToggle.check();

  await itemRow.locator('button[title="Deactivate"]').click();
  await page.click('button:has-text("Deactivate")');
  await expect(page.locator('li', {hasText: itemLabel}).locator('text=inactive')).toBeVisible({timeout: 10_000});

  await showInactiveToggle.uncheck();
  await expect(page.locator('li', {hasText: itemLabel})).toHaveCount(0);

  await showInactiveToggle.check();
  await expect(page.locator('li', {hasText: itemLabel})).toBeVisible();
});

test('E2E-CAT-1-02: a bad key shows the message and keeps the other typing', async ({page}) => {
  const loggedIn = await ensureLoggedIn(page);
  test.skip(!loggedIn, 'CATALOG_TEST_AUTH_TOKEN not set — see file header for how to mint one.');
  await page.goto('/settings/catalog');

  const label = `Bad Key Item ${Date.now().toString(36)}`;

  await page.click('button:has-text("Items")');
  await page.fill('input[placeholder^="Label, e.g. 6-ft"]', label);
  // Touch the key field directly with something the pattern rejects —
  // a space is never valid (CAT-1's E-CAT-001).
  const keyInput = page.locator('input[placeholder="key-like-this"]').first();
  await keyInput.fill('not a valid key');
  await page.click('button:has-text("Add item")');

  await expect(page.locator('text=letters, numbers and hyphens')).toBeVisible({timeout: 5_000});
  // The label is still there — nothing was cleared on the rejected save.
  await expect(page.locator('input[placeholder^="Label, e.g. 6-ft"]')).toHaveValue(label);
});
