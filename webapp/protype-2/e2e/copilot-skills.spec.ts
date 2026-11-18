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
