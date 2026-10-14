import assert from 'node:assert/strict';
import test from 'node:test';
import {canonicalizeSnapshot, escapeField, hashSnapshot} from './versionHash';
import type {MapSnapshot} from './versionHash';

const base: MapSnapshot = {
  schema_version: 1,
  title: 'Leads to sales',
  stages: [
    {key: 's1', label: 'Initial contact', owner_lens_key: 'lens-2'},
    {key: 's2', label: 'Quote', owner_lens_key: 'lens-2'},
  ],
  lenses: [
    {key: 'lens-1', label: 'Customer', actor_type: 'customer', does_planned_work: false},
    {key: 'lens-2', label: 'Sales Coordinator', actor_type: 'internal', does_planned_work: true},
  ],
  cells: [
    {stage_key: 's1', lens_key: 'lens-2', task: 'Log the lead', done_when: 'CRM record exists', duration_minutes: 15},
    {stage_key: 's2', lens_key: 'lens-2', task: 'Draft the quote', done_when: null, duration_minutes: 90},
  ],
  links: [{stage_key: 's2', lens_key: 'lens-2', link_type: 'exception', target_map_id: 42}],
};

const clone = (s: MapSnapshot): MapSnapshot => JSON.parse(JSON.stringify(s)) as MapSnapshot;

test('UT-PUB-1-01: the same definition with its object keys in a different order hashes the same', async () => {
  // Same values, every object literal written with its keys reversed.
  const reordered: MapSnapshot = {
    links: [{target_map_id: 42, link_type: 'exception', lens_key: 'lens-2', stage_key: 's2'}],
    cells: [
      {duration_minutes: 15, done_when: 'CRM record exists', task: 'Log the lead', lens_key: 'lens-2', stage_key: 's1'},
      {duration_minutes: 90, done_when: null, task: 'Draft the quote', lens_key: 'lens-2', stage_key: 's2'},
    ],
    lenses: [
      {does_planned_work: false, actor_type: 'customer', label: 'Customer', key: 'lens-1'},
      {does_planned_work: true, actor_type: 'internal', label: 'Sales Coordinator', key: 'lens-2'},
    ],
    stages: [
      {owner_lens_key: 'lens-2', label: 'Initial contact', key: 's1'},
      {owner_lens_key: 'lens-2', label: 'Quote', key: 's2'},
    ],
    title: 'Leads to sales',
    schema_version: 1,
  } as MapSnapshot;

  assert.equal(canonicalizeSnapshot(reordered), canonicalizeSnapshot(base));
  assert.equal(await hashSnapshot(reordered), await hashSnapshot(base));
});

test('UT-PUB-1-02: changing a duration by one minute changes the hash', async () => {
  const changed = clone(base);
  changed.cells[0].duration_minutes = 16;

  assert.notEqual(canonicalizeSnapshot(changed), canonicalizeSnapshot(base));
  assert.notEqual(await hashSnapshot(changed), await hashSnapshot(base));
});

test('UT-PUB-1-03: fields that are not part of the definition are ignored', async () => {
  // Timestamps and row ids ride along on real records; none of them may
  // reach the canonical string.
  const withNoise = clone(base) as MapSnapshot & Record<string, unknown>;
  withNoise.created_at = '2026-10-14T00:00:00Z';
  withNoise.published_at = '2026-10-14T00:00:01Z';
  withNoise.id = 999;
  (withNoise.stages[0] as unknown as Record<string, unknown>).id = 1447;
  (withNoise.stages[0] as unknown as Record<string, unknown>).updated_at = '2026-10-14';
  (withNoise.lenses[0] as unknown as Record<string, unknown>).id = 1200;
  (withNoise.cells[0] as unknown as Record<string, unknown>).id = 9625;

  assert.equal(canonicalizeSnapshot(withNoise), canonicalizeSnapshot(base));
  assert.equal(await hashSnapshot(withNoise), await hashSnapshot(base));
});

test('reordering stages DOES change the hash — stage order is part of the definition', async () => {
  const swapped = clone(base);
  swapped.stages = [swapped.stages[1], swapped.stages[0]];

  assert.notEqual(await hashSnapshot(swapped), await hashSnapshot(base));
});

test('a separator inside a value cannot forge structure', () => {
  // Without escaping, this title would read as extra fields.
  const sneaky = clone(base);
  sneaky.title = 'Leads|to\nsales';

  const canonical = canonicalizeSnapshot(sneaky);
  const titleLine = canonical.split('\n').find((l) => l.startsWith('title|'))!;

  assert.equal(titleLine, 'title|Leads\\pto\\nsales');
  // One title line only — the embedded newline did not create a second line.
  assert.equal(canonical.split('\n').filter((l) => l.startsWith('title|')).length, 1);
});

test('escapeField escapes backslash before the other two, so escapes round-trip unambiguously', () => {
  assert.equal(escapeField('a\\b'), 'a\\\\b');
  assert.equal(escapeField('a|b'), 'a\\pb');
  assert.equal(escapeField('a\nb'), 'a\\nb');
  // A literal backslash-p in the source must not be confused with an escaped pipe.
  assert.equal(escapeField('a\\pb'), 'a\\\\pb');
  assert.equal(escapeField(null), '');
  assert.equal(escapeField(undefined), '');
});

test('null task, done-when and duration serialise as empty fields, not the word null', () => {
  const sparse: MapSnapshot = {
    schema_version: 1,
    title: 'T',
    stages: [{key: 's1', label: 'S', owner_lens_key: null}],
    lenses: [],
    cells: [{stage_key: 's1', lens_key: 'l1', task: null, done_when: null, duration_minutes: null}],
    links: [],
  };

  const canonical = canonicalizeSnapshot(sparse);
  assert.ok(canonical.includes('stage|s1|S|\n'));
  assert.ok(canonical.includes('cell|s1|l1|||\n'));
  assert.ok(!canonical.includes('null'));
});

test('the canonical string is stable across runs for the same input (no clock, no randomness)', async () => {
  const first = await hashSnapshot(base);
  const second = await hashSnapshot(clone(base));
  assert.equal(first, second);
});

// Pins the exact bytes the Xano implementation must reproduce. If this
// expectation ever changes, functions/pub/canonical_hash.xs has to change
// with it, and every stored content_hash written before the change stops
// verifying — so treat a failure here as a breaking-change alarm, not a
// test to update casually.
test('golden: the canonical string and hash are pinned (Xano must match byte for byte)', async () => {
  const expectedCanonical =
    'v1\n' +
    'title|Leads to sales\n' +
    'stage|s1|Initial contact|lens-2\n' +
    'stage|s2|Quote|lens-2\n' +
    'lens|lens-1|Customer|customer|0\n' +
    'lens|lens-2|Sales Coordinator|internal|1\n' +
    'cell|s1|lens-2|Log the lead|CRM record exists|15\n' +
    'cell|s2|lens-2|Draft the quote||90\n' +
    'link|s2|lens-2|exception|42\n';

  assert.equal(canonicalizeSnapshot(base), expectedCanonical);
  assert.equal(
    await hashSnapshot(base),
    '0c62343204f24db1f11a906693f342101ee41122eaa7402f25cb3d3db9c97109',
  );
});

// Both pinned hashes above and below were confirmed byte-identical against
// the live Xano function pub/canonical_hash on 2026-10-14 — not assumed.
// Escaping is the easiest half of a dual implementation to get subtly
// wrong, so it gets its own pin.
test('golden: the escaping edge case is pinned (Xano must match byte for byte)', async () => {
  const sneaky: MapSnapshot = {
    schema_version: 1,
    title: 'Leads|to\nsales \\ back',
    stages: [{key: 's1', label: 'A|B', owner_lens_key: null}],
    lenses: [],
    cells: [{stage_key: 's1', lens_key: 'l1', task: null, done_when: null, duration_minutes: null}],
    links: [],
  };

  assert.equal(
    canonicalizeSnapshot(sneaky),
    'v1\ntitle|Leads\\pto\\nsales \\\\ back\nstage|s1|A\\pB|\ncell|s1|l1|||\n',
  );
  assert.equal(
    await hashSnapshot(sneaky),
    '5c2e823ffb28c9f34090532733b3ec4c4846948d5334a238e9c53d8746d3160e',
  );
});
