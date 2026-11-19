import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {buildDigest} from './skillsModel';

// COP-9 story 07 - one weekly "what I learned" summary. The server returns the week's raw history
// (copilot/skill_digest); buildDigest sorts it into flagged lines (need reading) and the rest (collapsed).

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

const T = 1_800_000_000_000;
const skills = [
  {id: 1, title: 'Weekly plan', kind: 'skill', version_no: 3, status: 'trial'},
  {id: 2, title: 'Rush jobs', kind: 'exception', version_no: 2, status: 'trusted'},
  {id: 3, title: 'Old idea', kind: 'lesson', version_no: 4, status: 'retired'},
  {id: 4, title: 'Fresh', kind: 'lesson', version_no: 1, status: 'trial'},
];
const v = (id: number, skill_id: number, version_no: number, change: string, changed_by: string, reason = '', at = T) =>
  ({id, created_at: at, skill_id, version_no, change, changed_by, reason, undo_of_version_no: 0});
const versions = [
  v(1, 4, 1, 'create', 'copilot'),
  v(2, 1, 3, 'edit', 'copilot', 'learned from a run'),
  v(3, 2, 2, 'edit', 'copilot', 'Trial rule: trusted after enough uses in different chats or runs, never overridden.'),
  v(4, 3, 4, 'retire', 'copilot', 'Trial rule: switched off because the owner overrode it. Kept; Undo brings it back.'),
  v(5, 1, 2, 'edit', 'owner', 'locked'),
];
const refusals = [{created_at: T, error_code: 'E-COP-083', message: 'A skill cannot contain logins...', step: 'skill_create'}];

test('UT-COP-9-07-01: new, changed, promoted and switched off are each named in plain words', () => {
  const d = buildDigest({versions, skills, refusals});
  const all = [...d.flagged, ...d.other];
  const kinds = Object.fromEntries(all.filter((l) => l.skillId).map((l) => [l.versionId, l.kind]));
  assert.equal(kinds[1], 'new');
  assert.equal(kinds[2], 'changed');
  assert.equal(kinds[3], 'promoted');
  assert.equal(kinds[4], 'switched_off');
  assert.match(all.find((l) => l.versionId === 3)!.text, /Rush jobs.*trusted/i);
});

test('UT-COP-9-07-02: only switched-off items and refusals are flagged; everything else is collapsed', () => {
  const d = buildDigest({versions, skills, refusals});
  assert.deepEqual(d.flagged.map((l) => l.kind).sort(), ['refused', 'switched_off']);
  assert.ok(d.other.every((l) => l.kind !== 'switched_off' && l.kind !== 'refused'));
});

test('UT-COP-9-07-03: the owner pressing Lock / Unlock is not news in "what I learned"', () => {
  const d = buildDigest({versions, skills, refusals});
  assert.ok(![...d.flagged, ...d.other].some((l) => l.versionId === 5));
});

test('UT-COP-9-07-04: Undo is offered only where it makes sense - the item is still at that version and an earlier one exists', () => {
  const d = buildDigest({versions, skills, refusals});
  const byV = Object.fromEntries([...d.flagged, ...d.other].filter((l) => l.versionId).map((l) => [l.versionId, l.undoTo]));
  assert.equal(byV[2], 2, 'copilot edit at the current version: undo puts back v2');
  assert.equal(byV[3], 1, 'promotion: undo puts back v1 (trial)');
  assert.equal(byV[4], 3, 'switched off: undo brings it back');
  assert.equal(byV[1], 0, 'a brand-new item has nothing earlier to put back');
  const stale = buildDigest({versions: [v(9, 1, 2, 'edit', 'copilot', 'older')], skills, refusals: []});
  assert.equal(stale.other[0].undoTo, 0, 'the item has moved on since this line: no Undo (it would throw away the later change)');
});

test('UT-COP-9-07-05: a quiet week says so instead of disappearing', () => {
  const d = buildDigest({versions: [], skills, refusals: []});
  assert.equal(d.empty, true);
  assert.equal(d.flagged.length + d.other.length, 0);
});

test('UT-COP-9-07-06: the digest endpoint is a read-only account-scoped look at the last N days (1-31)', () => {
  const ep = read('apis/journey_map/669_copilot_skill_digest_GET.xs');
  assert.match(ep, /query "copilot\/skill_digest" verb=GET/);
  assert.match(ep, /auth = "user"/);
  assert.match(ep, /copilot_skill_version/);
  assert.match(ep, /event_log/);
  assert.match(ep, /"rejected"/);
  assert.ok(!/db\.(add|patch|del) /.test(ep), 'read-only');
  assert.match(ep, /31/);
});

test('UT-COP-9-07-07: the same refusal repeated is one flagged line with a count', () => {
  const r = {created_at: T, error_code: 'E-COP-081', message: 'Outside its business.', step: 'skill_create'};
  const d = buildDigest({versions: [], skills, refusals: [r, {...r, created_at: T + 1}, {...r, created_at: T + 2}, {...r, error_code: 'E-COP-083'}]});
  assert.equal(d.flagged.length, 2);
  assert.match(d.flagged.find((l) => l.text.includes('E-COP-081'))!.text, /3 times/);
});
