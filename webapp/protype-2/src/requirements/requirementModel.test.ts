import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readdirSync, readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {
  nameKey,
  cleanName,
  validateName,
  holdingState,
  endsSoonLabel,
  personLinkLabel,
  strengthLabel,
  nextStrength,
  needsLine,
  NEEDS_PER_STEP_LIMIT,
  REQUIREMENTS_PER_ACCOUNT_LIMIT,
  addNeedAllowed,
  needsCanonicalString,
  NO_NEEDS_HASH,
  type Holding,
  type FrozenNeed,
} from './requirementModel';

// REQ-1 stories 01-04. The server decides and re-checks everything (functions/req/*); this model
// shapes the screens and is the TypeScript twin of the name rule and the date rule. The second half
// reads the XanoScript source for the rules that must never drift. Live proof is in the epic.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');
function findApi(dir: string, verb: string, path: string): string {
  for (const f of readdirSync(repo(dir))) {
    if (!f.endsWith('.xs')) continue;
    const src = read(`${dir}/${f}`);
    if (src.includes(`query "${path}" verb=${verb} `) || src.includes(`query "${path}" verb=${verb}\n`)) return src;
  }
  throw new Error(`no ${verb} ${path} in ${dir}`);
}

// ── story 01: one list, one name ─────────────────────────────────────────────────────────────────
test('UT-REQ-01-01: "Forklift" and " forklift " and "FORKLIFT" are one requirement', () => {
  assert.equal(nameKey('Forklift'), 'forklift');
  assert.equal(nameKey(' forklift '), 'forklift');
  assert.equal(nameKey('FORKLIFT'), 'forklift');
  assert.equal(nameKey('Fork   lift  licence'), 'fork lift licence', 'inner spaces collapse to one');
  assert.equal(cleanName('  Fork   lift  '), 'Fork lift', 'what is shown keeps its case, spaces tidied');
});

test('UT-REQ-01-02: the name rules, with a message that says why and keeps what was typed', () => {
  assert.deepEqual(validateName('Forklift'), {ok: true});
  const empty = validateName('   ');
  assert.equal(empty.ok, false);
  assert.match((empty as {code: string}).code, /E-REQ-001/);
  const long = validateName('x'.repeat(61));
  assert.equal(long.ok, false);
  assert.match((long as {message: string}).message, /60/);
  assert.match((long as {code: string}).code, /E-REQ-008/);
  assert.equal(validateName('x'.repeat(60)).ok, true);
  const html = validateName('<b>Forklift</b>');
  assert.equal(html.ok, false);
  assert.match((html as {code: string}).code, /E-REQ-002/);
  assert.equal(validateName('Speaks Spanish & French').ok, true, 'an ampersand is not HTML');
  assert.equal(validateName('Level 2 < 3').ok, true, 'a lone < is not a tag');
});

test('UT-REQ-01-03: the limits are the epic\'s', () => {
  assert.equal(REQUIREMENTS_PER_ACCOUNT_LIMIT, 200);
  assert.equal(NEEDS_PER_STEP_LIMIT, 10);
});

// ── story 02: held until a date, on the date of the work ─────────────────────────────────────────
const h = (until: string | null | undefined): Holding => ({requirement_id: 1, held_until: until as string});

test('UT-REQ-02-01: the last day counts; the day after does not', () => {
  assert.equal(holdingState(h('2027-03-31'), '2027-03-31').held, true);
  assert.equal(holdingState(h('2027-03-31'), '2027-04-01').held, false);
  assert.equal(holdingState(h('2027-03-31'), '2027-03-30').held, true);
});

test('UT-REQ-02-02: every empty form of "no end date" means no end', () => {
  for (const empty of ['', null, undefined, '   ']) {
    const s = holdingState(h(empty), '2099-01-01');
    assert.equal(s.held, true, `empty ${JSON.stringify(empty)} must not read as ended`);
    assert.equal(s.endsSoon, false);
    assert.equal(s.until, '');
  }
});

test('UT-REQ-02-03: "ends soon" within 30 days, plain words', () => {
  assert.equal(holdingState(h('2027-03-31'), '2027-03-01').endsSoon, true, 'exactly 30 days');
  assert.equal(holdingState(h('2027-03-31'), '2027-02-28').endsSoon, false, '31 days');
  assert.equal(holdingState(h('2027-03-31'), '2027-03-31').endsSoon, true, 'on the last day');
  assert.equal(holdingState(h('2027-03-31'), '2027-04-02').endsSoon, false, 'already ended is not "soon"');
  assert.match(endsSoonLabel(holdingState(h('2027-03-31'), '2027-03-20')), /ends in 11 days/i);
  assert.match(endsSoonLabel(holdingState(h('2027-03-31'), '2027-03-31')), /today/i);
  assert.equal(endsSoonLabel(holdingState(h(''), '2027-03-20')), '');
});

// ── story 03: link to a lasting profile ──────────────────────────────────────────────────────────
test('UT-REQ-03-01: the plan\'s people say whether they have a profile', () => {
  assert.equal(personLinkLabel({profile_id: 0}), 'No profile');
  assert.equal(personLinkLabel({profile_id: null}), 'No profile');
  assert.equal(personLinkLabel({profile_id: 7, profile_name: 'Ana'}), 'Profile: Ana');
});

// ── story 04: hard or soft ───────────────────────────────────────────────────────────────────────
test('UT-REQ-04-01: hard is a must, soft is preferred; switching flips it', () => {
  assert.equal(strengthLabel('hard'), 'Must have');
  assert.equal(strengthLabel('soft'), 'Preferred');
  assert.equal(nextStrength('hard'), 'soft');
  assert.equal(nextStrength('soft'), 'hard');
});

test('UT-REQ-04-02: a step\'s needs in one line; none reads as none', () => {
  assert.equal(needsLine([]), 'No needs');
  assert.equal(needsLine([{name: 'Forklift', strength: 'hard'}]), 'Needs: Forklift (must)');
  assert.equal(needsLine([{name: 'Forklift', strength: 'hard'}, {name: 'Speaks Spanish', strength: 'soft'}]), 'Needs: Forklift (must), Speaks Spanish (preferred)');
});

test('UT-REQ-04-03: no more than 10 on a step, and an archived requirement cannot be newly added', () => {
  assert.equal(addNeedAllowed({currentCount: 9, alreadyOnStep: false, archived: false}).ok, true);
  const full = addNeedAllowed({currentCount: 10, alreadyOnStep: false, archived: false});
  assert.equal(full.ok, false);
  assert.match((full as {message: string}).message, /10/);
  assert.equal(addNeedAllowed({currentCount: 10, alreadyOnStep: true, archived: false}).ok, true, 'changing hard/soft on an existing need is not an add');
  assert.equal(addNeedAllowed({currentCount: 0, alreadyOnStep: false, archived: true}).ok, false);
});

// ── the server rules, read from source ───────────────────────────────────────────────────────────
test('UT-REQ-S1: the name rule is ONE function and the unique index is what settles a race', () => {
  const norm = read('functions/req/normalize_name.xs');
  assert.match(norm, /function "req\/normalize_name"/);
  assert.ok(!/filters=.*lower/.test(read('static/tables/183_requirement.xs')), 'no column filter: the key is stored');
  const create = findApi('apis/catalog', 'POST', 'requirement');
  assert.match(create, /function\.run "req\/validate_name"/, 'the endpoint uses the shared rule');
  assert.match(read('functions/req/validate_name.xs'), /function\.run "req\/normalize_name"/, 'which uses the one name function');
  assert.match(create, /try_catch/, 'the loser of a parallel add reads the winner');
  assert.match(create, /E-REQ-005/, 'the 200 limit');
  assert.match(create, /confirm_similar/, 'near matches are shown before saving, and nothing is created without a yes');
});

test('UT-REQ-S2: only an admin changes the list; delete is blocked while anything uses it', () => {
  for (const [verb, path] of [['POST', 'requirement'], ['PATCH', 'requirement/{requirement_id}'], ['DELETE', 'requirement/{requirement_id}'], ['POST', 'requirement/{requirement_id}/archive']] as const) {
    assert.match(findApi('apis/catalog', verb, path), /function\.run "usr\/assert_team_admin"/, `${verb} ${path} is admin only`);
  }
  const del = findApi('apis/catalog', 'DELETE', 'requirement/{requirement_id}');
  assert.match(del, /function\.run "req\/usage"/);
  assert.match(del, /E-REQ-004/);
  const usage = read('functions/req/usage.xs');
  for (const t of ['journey_cell_requirement', 'agent_profile_requirement', 'journey_map_version_requirement']) {
    assert.match(usage, new RegExp(`db\\.query ${t} `), `usage counts ${t}`);
  }
  assert.ok(/return = \{type: "count"\}/.test(usage), 'counts by query, not by loading rows');
});

test('UT-REQ-S3: holdings are written by an admin PERSON (an AI is refused), compared to the date of the work', () => {
  const put = findApi('apis/planner', 'POST', 'agent-profile/{agent_profile_id}/requirement');
  assert.match(put, /function\.run "copilot\/assert_person_only"/);
  assert.match(put, /E-REQ-011|archived/, 'an archived requirement cannot be newly recorded');
  assert.match(put, /held_until/);
  const state = read('functions/req/holding_state.xs');
  assert.match(state, /on_date/, 'compared to the date of the work, never to now');
  assert.ok(!/\bnow\b/.test(state.replace(/\/\/.*$/gm, '')), 'no clock in the rule');
});

// ── story 05: the frozen needs hash, pinned on BOTH sides ────────────────────────────────────────
const SAMPLE: FrozenNeed[] = [
  {stage_key: 's2', lens_key: 'lens-2', requirement_id: 12, strength: 'soft'},
  {stage_key: 's1', lens_key: 'lens-3', requirement_id: 3, strength: 'hard'},
  {stage_key: 's1', lens_key: 'lens-2', requirement_id: 11, strength: 'hard'},
  {stage_key: 's1', lens_key: 'lens-2', requirement_id: 2, strength: 'soft'},
];
const SAMPLE_CANONICAL = 's1::lens-2::2::soft;s1::lens-2::11::hard;s1::lens-3::3::hard;s2::lens-2::12::soft;';
// The SAME sample is pinned in the live function: req/needs_hash returns this exact hash (REQ-1 epic, Test Results).
export const SAMPLE_HASH = '96fede33ed450ae58b1f0f668a2337060e22aaa11f759dacb2aa50f626ebb3f5';

test('UT-REQ-05-01: the canonical string sorts by stage, row, then NUMERIC requirement id; the hash is pinned', () => {
  assert.equal(needsCanonicalString(SAMPLE), SAMPLE_CANONICAL, 'order does not depend on the input order');
  assert.equal(needsCanonicalString([...SAMPLE].reverse()), SAMPLE_CANONICAL);
  assert.equal(createHash('sha256').update(SAMPLE_CANONICAL).digest('hex'), SAMPLE_HASH);
  assert.ok(SAMPLE_CANONICAL.indexOf('::2::') < SAMPLE_CANONICAL.indexOf('::11::'), '2 sorts before 11 (numeric, not text)');
});

test('UT-REQ-05-02: no needs is the empty string and its pinned hash; no pipe, no JSON', () => {
  assert.equal(needsCanonicalString([]), '');
  assert.equal(createHash('sha256').update('').digest('hex'), NO_NEEDS_HASH);
  assert.ok(!SAMPLE_CANONICAL.includes('|') && !SAMPLE_CANONICAL.includes('{'));
});

test('UT-REQ-05-03: a stage "s10" sorts before "s2" exactly as the server sorts text', () => {
  const rows: FrozenNeed[] = [
    {stage_key: 's2', lens_key: 'l', requirement_id: 1, strength: 'hard'},
    {stage_key: 's10', lens_key: 'l', requirement_id: 1, strength: 'hard'},
  ];
  assert.equal(needsCanonicalString(rows), 's10::l::1::hard;s2::l::1::hard;');
});

// ── story 05: the rules read from the server source ──────────────────────────────────────────────
test('UT-REQ-05-S1: freezing happens inside the publish transaction by plain writes, never touching the snapshot', () => {
  const freeze = read('functions/req/freeze_needs.xs');
  assert.match(freeze, /db\.add journey_map_version_requirement/);
  assert.match(freeze, /db\.add journey_map_version_needs_hash/);
  assert.ok(!/function\.run "(?!req\/needs_hash)/.test(freeze.replace(/\/\/.*$/gm, '')), 'only the hash rule is called: plain writes');
  assert.ok(!/canonical_hash|build_map_snapshot|snapshot\s*[:=]/.test(freeze.replace(/\/\/.*$/gm, '')), 'the snapshot and its hash are not touched');
  assert.ok(!/db\.(patch|del)\s+journey_map_version_/.test(freeze), 'frozen rows are never edited or deleted');
  assert.match(freeze, /stage_key/);
  assert.match(freeze, /lens_key/);
  assert.ok(!/journey_cell_id\s*:/.test(freeze.slice(freeze.indexOf('db.add journey_map_version_requirement'), freeze.indexOf('} as $_frozen'))), 'frozen by keys, never by cell id');
});

test('UT-REQ-05-S2: ONLY req/step_needs (and the version plumbing) reads the frozen needs', () => {
  const allowed = new Set(['functions/req/step_needs.xs', 'functions/req/freeze_needs.xs', 'functions/req/verify_needs.xs', 'functions/req/audit_needs.xs', 'functions/req/usage.xs', 'apis/catalog/req_requirement_GET.xs' /* only counts how many versions froze each requirement */]);
  const bad: string[] = [];
  const walk = (dir: string) => {
    for (const e of readdirSync(repo(dir), {withFileTypes: true})) {
      const rel = `${dir}/${e.name}`;
      if (e.isDirectory()) walk(rel);
      else if (e.name.endsWith('.xs')) {
        const src = read(rel).replace(/\/\/.*$/gm, '');
        // a read of the frozen table, outside the allowed files, for the cascade delete and the table itself
        if (/db\.query journey_map_version_requirement/.test(src) && !allowed.has(rel) && !/delete_map_cascade/.test(rel)) bad.push(rel);
      }
    }
  };
  walk('functions');
  walk('apis');
  assert.deepEqual(bad, [], `these read the frozen needs without going through req/step_needs: ${bad.join(', ')}`);
  const job = read('functions/req/job_step_needs.xs');
  assert.match(job, /function\.run "req\/step_needs"/);
  assert.match(job, /journey_map_version_id/, 'a job reads through its pinned version');
});

test('UT-REQ-05-S3: Publish freezes the needs INSIDE its transaction and reports how many', () => {
  const pub = read('apis/journey_map/201_journey_map_journey_map_id_publish_POST.xs');
  assert.match(pub, /function\.run "req\/freeze_needs"/);
  assert.match(pub, /needs_frozen/);
  const tx = pub.indexOf('db.transaction');
  assert.ok(tx > 0 && pub.indexOf('req/freeze_needs') > tx, 'the call sits after the transaction opens');
  assert.ok(pub.indexOf('req/freeze_needs') < pub.indexOf('} as $_rate_added') + 400, 'and next to the rate card write, inside the same block');
});
