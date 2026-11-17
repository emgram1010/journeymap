/**
 * Shared helper for specs that need the journey-map editor.
 *
 * WHY: before the new-ui redesign, `page.goto('/')` landed on the map
 * editor. Now `/` redirects to the Architectures list, so specs open a
 * map by id instead. The id comes from E2E_MAP_ID (default: a dedicated
 * draft map 269 "E2E editor fixture 2 (safe to delete)" in the test account, which has stages, lenses
 * and cells, created for these specs so they never write into other fixtures).
 */
import {test, type Page} from '@playwright/test';

export const E2E_MAP_ID = process.env.E2E_MAP_ID ?? '269';

/**
 * ITEM-1 specs get their OWN map (it ends up with an Items row, which would change
 * "the last row" for every other editor spec). Map 266 "E2E editor fixture".
 */
export const E2E_ITEMS_MAP_ID = process.env.E2E_ITEMS_MAP_ID ?? '266';

/**
 * Open the journey-map editor for the fixture map and wait for the matrix.
 *
 * It also closes the Journey Health side panel. That panel opens by
 * default as a fixed 256px column on the right edge and, at 1280px wide,
 * sits on top of the AI chat panel (its New Session and Send buttons).
 * Specs here test the chat, not the panel, so a user would close it
 * first. (App issue noted in EPIC-COP-8 US-COP-8-06 results.)
 */
export async function gotoMap(page: Page, mapId: string = E2E_MAP_ID) {
  await page.goto(`/maps/${mapId}`);
  await page.waitForSelector('[class*="tabulator"]', {timeout: 30_000});
  const closeHealth = page.locator('div.fixed.right-0.w-64').locator('button:has(svg.lucide-x)');
  // The panel mounts a moment after the matrix does — wait for it, then close it.
  await closeHealth.waitFor({state: 'visible', timeout: 8_000}).catch(() => {});
  if (await closeHealth.isVisible().catch(() => false)) {
    await closeHealth.click();
    await page.waitForTimeout(300); // slide-out transition
  }
}

/**
 * Switch the AI chat panel between Interview and Chat mode.
 *
 * new-ui: the two old Interview / Chat buttons are now ONE mode badge in
 * the panel header that opens a "Switch Mode" popover.
 */
export async function setChatMode(page: Page, mode: 'Interview' | 'Chat') {
  const panel = page.locator('div.w-96');
  // header buttons with a chevron: [0] session picker, [1] mode badge
  const badge = panel.locator('button:has(svg.lucide-chevron-down)').nth(1);
  if (((await badge.innerText()).trim().toLowerCase()) === mode.toLowerCase()) return;
  await badge.click();
  await panel.locator('div.absolute.w-56').getByRole('button', {name: mode, exact: true}).click();
  // close the popover (its backdrop swallows clicks until it is closed)
  await page.locator('div.fixed.inset-0.z-40').click({position: {x: 5, y: 5}, force: true}).catch(() => {});
}

/**
 * The AI specs exercise the LIVE AI backend. When that backend answers
 * with its provider-billing error instead of a real reply (seen
 * 2026-11-16: "Your credit balance is too low to access the Anthropic
 * API"), nothing about the chat screens can be judged, so skip with the
 * reason rather than fail on (or, worse, pass on) an error string. The
 * specs run again as soon as the backend answers properly.
 */
export function skipIfAiUnavailable(reply: unknown) {
  const text = typeof reply === 'string' ? reply : '';
  test.skip(
    /credit balance is too low|plans & billing|insufficient credits/i.test(text),
    'Live AI backend is returning its provider-billing error ("credit balance is too low") — not a screen problem; re-run after the AI account is topped up.',
  );
}

/**
 * Some specs were built on fixture maps that lived in another account
 * (EXC-1's map 219 and its Triage/Repair partners). The shared test
 * account does not have them, and a spec cannot judge a screen without
 * its fixture — so skip, saying which map is missing, instead of
 * creating plans against nothing and failing deep inside the flow.
 */
export async function skipIfMapMissing(
  request: import('@playwright/test').APIRequestContext,
  mapId: number | string,
  token: string | undefined,
) {
  const res = await request.get(`https://xdjc-i7zz-jhm2.n7e.xano.io/api:ER4MRRWZ/journey_map/${mapId}`, {
    headers: {Authorization: `Bearer ${token}`},
  });
  test.skip(!res.ok(), `Fixture map ${mapId} is not in the test account (HTTP ${res.status()}) — re-create the EXC-1 fixture maps there to run this.`);
}
