import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {COPILOT_CACHE_MS, shouldReloadCopilot} from './useAccountCopilot';

// Final review R12 - the copilot lookup is no longer kept for the life of the page.

test('R12: nothing kept yet -> load', () => {
  assert.equal(shouldReloadCopilot(null, 1_800_000_000_000), true);
});

test('R12: a failed lookup is never reused - the next view asks again', () => {
  assert.equal(shouldReloadCopilot({loadedAt: 1_800_000_000_000, failed: true}, 1_800_000_000_001), true);
});

test('R12: a good answer is reused for one minute, then asked again', () => {
  const t = 1_800_000_000_000;
  assert.equal(shouldReloadCopilot({loadedAt: t, failed: false}, t + COPILOT_CACHE_MS - 1), false);
  assert.equal(shouldReloadCopilot({loadedAt: t, failed: false}, t + COPILOT_CACHE_MS), true);
});

test('R12: switching a user on or off on Manage users refreshes the planner', () => {
  const page = readFileSync(fileURLToPath(new URL('../team/TeamPage.tsx', import.meta.url)), 'utf8');
  assert.match(page, /setUserActive\(member\.id, nextActive\)\.then\(\(r\) => \{\s*announceCopilotChanged\(\);/);
  const hook = readFileSync(fileURLToPath(new URL('./useAccountCopilot.ts', import.meta.url)), 'utf8');
  assert.ok(hook.includes('window.addEventListener(COPILOT_CHANGED_EVENT, onChanged)'), 'every planner view listens');
});
