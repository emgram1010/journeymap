/**
 * UI-COP-9 — "How I work" (the copilot's skill library) and its approval level.
 *
 * Runs against the LIVE test account (account 13), which holds the COP-9 test items: skill #1
 * with an exception #2 under it. Read-mostly: it opens history and the level screen; it does not
 * press Undo (the HTTP probe product/stories/Epic-23/tests/cop9_skills_probe.py covers that).
 */
import {expect, test} from '@playwright/test';

test.describe('UI-COP-9 skill library', () => {
  test('UI-COP-9-01 the copilot panel lists its skills, with history and Undo', async ({page}) => {
    await page.goto('/');
    await page.locator('#copilot-open-btn').click();
    const panel = page.locator('#copilot-panel');
    await expect(panel).toBeVisible();
    await panel.getByRole('button', {name: 'How I work'}).click();
    const section = panel.getByTestId('copilot-skills');
    await expect(section).toBeVisible();
    const skill = section.getByTestId('skill-1');
    await expect(skill).toContainText('Skill #1');
    await expect(skill).toContainText('On trial');
    await expect(section.getByTestId('skill-2')).toContainText('When:');
    await skill.getByRole('button', {name: 'History'}).click();
    const history = skill.getByRole('list', {name: 'History'});
    await expect(history).toContainText('created it');
    await expect(history.getByRole('button', {name: 'Undo'}).first()).toBeVisible();
    await page.screenshot({path: 'e2e/screenshots/cop9-skills-panel.png'});
  });

  test('UI-COP-9-02 "Write its own skills" shows only on the copilot\'s own business', async ({page}) => {
    await page.goto('/approvals');
    await page.getByRole('tab', {name: /levels/i}).click();
    const picker = page.locator('#approval-levels-business');
    await picker.selectOption({label: "Copilot's own: how I work"});
    await expect(page.locator('#level-skill_write')).toBeVisible();
    await expect(page.locator('#level-skill_write')).toContainText("Write its own skills");
    await page.screenshot({path: 'e2e/screenshots/cop9-skills-level.png'});
    const other = await picker.locator('option').evaluateAll((os) =>
      os.map((o) => ({v: (o as HTMLOptionElement).value, t: o.textContent ?? ''})).find((o) => o.v !== '0' && !o.t.includes('how I work')),
    );
    test.skip(!other, 'the test account has only the copilot business');
    await picker.selectOption(other!.v);
    await expect(page.locator('#level-map_read')).toBeVisible();
    await expect(page.locator('#level-skill_write')).toHaveCount(0);
  });
});

/**
 * UI-COP-11 — lock, kind of work, last used, the item counter, filters and the limits.
 * Live test account 13: item #10 is the locked COP-11 test item (kind: planning). The test unlocks
 * and re-locks it, so it ends as it started.
 */
test.describe('UI-COP-11 locks and a tidy library', () => {
  test('UI-COP-11-01 each item shows its lock, kind and last used; the header counts items', async ({page}) => {
    await page.goto('/');
    await page.locator('#copilot-open-btn').click();
    const panel = page.locator('#copilot-panel');
    await panel.getByRole('button', {name: 'How I work'}).click();
    const section = panel.getByTestId('copilot-skills');
    await expect(section.getByTestId('skills-counter')).toContainText(/\d+ of \d+ items/);
    const item = section.getByTestId('skill-10');
    await expect(item).toContainText('Locked');
    await expect(item).toContainText('Planning');
    await expect(item).toContainText(/Never used|Used /);
    await page.screenshot({path: 'e2e/screenshots/cop11-skills-lock.png'});
  });

  test('UI-COP-11-02 the owner unlocks and locks an item, and the kind filter narrows the list', async ({page}) => {
    await page.goto('/');
    await page.locator('#copilot-open-btn').click();
    const panel = page.locator('#copilot-panel');
    await panel.getByRole('button', {name: 'How I work'}).click();
    const section = panel.getByTestId('copilot-skills');
    const item = section.getByTestId('skill-10');
    await item.getByRole('button', {name: 'Unlock'}).click();
    await expect(item).toContainText('AI may change');
    await item.getByRole('button', {name: 'Lock', exact: true}).click();
    await expect(item).toContainText('Locked');
    await section.getByLabel('Kind of work').selectOption('planning');
    await expect(section.getByTestId('skill-10')).toBeVisible();
    await expect(section.getByTestId('skill-1')).toHaveCount(0);
    await section.getByLabel('Kind of work').selectOption('all');
    await expect(section.getByTestId('skill-1')).toBeVisible();
  });

  test('UI-COP-11-03 a limit outside the bounds is refused on the screen and the typing is kept', async ({page}) => {
    await page.goto('/');
    await page.locator('#copilot-open-btn').click();
    const panel = page.locator('#copilot-panel');
    await panel.getByRole('button', {name: 'How I work'}).click();
    const section = panel.getByTestId('copilot-skills');
    await section.getByRole('button', {name: 'Limits'}).click();
    const most = section.getByLabel('Most items');
    await most.fill('5');
    await section.getByRole('button', {name: 'Save limits'}).click();
    await expect(section.getByRole('alert')).toContainText('10 and 200');
    await expect(most).toHaveValue('5');
  });
});
