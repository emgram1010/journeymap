import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// COP-11 story 01, "the AI can suggest instead": a copilot change to a LOCKED item becomes an approval
// request (forced to "waits for you", showing before and after); the item changes only if the owner
// approves. The rules live in XanoScript; these tests read the source.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

test('UT-COP-11-S-01: the gate can force "waits for you", and only ever towards waiting', () => {
  const ag = read('functions/copilot/action_gate.xs');
  assert.match(ag, /bool act_force_wait\?/);
  assert.match(ag, /\(\$input\.act_force_wait == true\) \? "wait" : \$level/, 'forcing can only make it wait');
  const tg = read('functions/journey/tool_gate.xs');
  assert.match(tg, /bool act_force_wait\?/);
  assert.match(tg, /act_force_wait\s*: \$input\.act_force_wait/, 'passed through explicitly (never inherited)');
});

test('UT-COP-11-S-02: save_skill forces waiting for a locked item (or locked parent) and shows before and after', () => {
  const t = read('ai/tool/save_skill.xs');
  assert.match(t, /function\.run "usr\/tool_caller"/, 'the lock is looked up in the caller\'s own account');
  assert.match(t, /db\.query copilot_skill_meta \{[\s\S]*?is_locked == true/);
  assert.match(t, /act_force_wait: \$force_wait/);
  assert.match(t, /Before: /);
  assert.match(t, /After: /);
  assert.match(t, /owner_approved_action_id: \$approved_action_id/, 'an approved re-send tells the writer which approval');
  assert.match(t, /\$input\.approval_id != 0\) \? \$act_action_id : 0/, 'only a re-send with an approval passes one');
});

test('UT-COP-11-S-03: the writer accepts a locked change only for a real, approved skill_write item for THIS change', () => {
  const w = read('functions/copilot/skill_write.xs');
  assert.match(w, /int owner_approved_action_id\?/);
  const block = w.slice(w.indexOf('var $owner_ok'), w.indexOf('E-COP-089"'));
  assert.match(block, /db\.query copilot_action \{/);
  assert.match(block, /\$db\.copilot_action\.account_id == \$input\.account_id/);
  assert.match(block, /\$db\.copilot_action\.action_type == "skill_write"/);
  assert.match(block, /\$db\.copilot_action\.status == "approved" \|\| \$db\.copilot_action\.status == "edited"/);
  assert.match(block, /\$appr_skill == \$input\.skill_id/);
  assert.match(block, /\$appr_parent == \$input\.parent_skill_id/);
  assert.match(w, /\$owner_ok == false/, 'the lock refusal still applies without it');
});

test('UT-COP-11-S-04: retire is not part of this: a locked item still cannot be retired by the copilot', () => {
  const w = read('functions/copilot/skill_write.xs');
  assert.match(w, /\$input\.op == "retire" && \$is_locked\) \|\| /, 'retiring a locked item is refused even with an approval');
});

test('UT-COP-11-S-05: the decision branches read the (possibly forced) level, so a forced wait really waits', () => {
  // Found by the push-time review: forcing only changed the reported level while the branches still read
  // $lv.effective_level, so at "tell"/"own" a locked change went straight through (and was then refused).
  const ag = read('functions/copilot/action_gate.xs');
  assert.match(ag, /elseif \(\$level == "tell"\)/);
  assert.match(ag, /elseif \(\$level == "wait"\)/);
  assert.ok(!/elseif \(\$lv\.effective_level == "(tell|wait)"\)/.test(ag));
});

test('UT-COP-11-S-06: get_approval finds a skill change filed under the account\'s copilot home, from any business chat', () => {
  // Skill changes are filed under the copilot home (COP-9 story 06), but get_approval only accepted items
  // of the chat's own business, so an approved skill change could never be finished (E-COP-036), live 2026-11-19.
  const t = read('ai/tool/get_approval.xs');
  assert.match(t, /db\.query copilot_home \{/);
  assert.match(t, /\$act_type_v == "skill_write" && \$home_arch != 0 && \$act_arch == \$home_arch/);
  assert.match(t, /\$db\.copilot_home\.account_id == \$cop1_gate\.account_id/, 'only this account\'s home');
});
