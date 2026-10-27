import assert from 'node:assert/strict';
import test from 'node:test';
import {canonicalizeSnapshot, escapeField, formatRateMinutes, hashSnapshot} from './versionHash';
import goldenV2Json from './fixtures/version-hash-golden-v2.json';
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

// Added in the PUB-1 review pass. The first two goldens are pure ASCII, so
// they would not have caught a UTF-8 encoding difference between
// TextEncoder here and sha256 on Xano — and a map title with an accent in
// it is not an edge case, it is Tuesday. Confirmed identical on both sides.
test('golden: non-ASCII text hashes identically on both sides', async () => {
  const unicode: MapSnapshot = {
    schema_version: 1,
    title: 'Café → Niño 日本語 🚀 naïve',
    stages: [{key: 's1', label: 'Étape un', owner_lens_key: 'lens-é'}],
    lenses: [{key: 'lens-é', label: 'Rôle', actor_type: 'internal', does_planned_work: true}],
    cells: [{stage_key: 's1', lens_key: 'lens-é', task: 'Prüfen — 検査', done_when: '✅ done', duration_minutes: 15}],
    links: [],
  };

  assert.equal(
    await hashSnapshot(unicode),
    'dc1dc9e52f44dae0230d378944a3e6b8aaccd285d130a4b9d026f38a2748e7c0',
  );
});

// ── RATE-1 — schema v2 (scaling + rates) ─────────────────────────────

const goldenV2 = goldenV2Json as unknown as {snapshot: MapSnapshot; expected_canonical: string; expected_hash: string};

test('UT-RATE-1-01: the v1 golden is untouched by the v2 serialiser', async () => {
  // Same pinned hash as the PUB-1 golden above, asserted again here so a
  // v2 change that leaks into v1 output fails under RATE-1's own name.
  assert.equal(
    await hashSnapshot(base),
    '0c62343204f24db1f11a906693f342101ee41122eaa7402f25cb3d3db9c97109',
  );
  // A v1 snapshot that happens to carry rates still ignores them — the
  // serialiser follows the snapshot's own schema_version, nothing else.
  const v1WithRates = {...clone(base), scaling: goldenV2.snapshot.scaling, rates: goldenV2.snapshot.rates};
  assert.equal(await hashSnapshot(v1WithRates), await hashSnapshot(base));
});

test('UT-RATE-1-02: the v2 golden is pinned (Xano must match byte for byte)', async () => {
  assert.equal(canonicalizeSnapshot(goldenV2.snapshot), goldenV2.expected_canonical);
  assert.equal(await hashSnapshot(goldenV2.snapshot), goldenV2.expected_hash);
});

test('UT-RATE-1-03: rate minutes render as fixed 2 decimals', () => {
  assert.deepEqual(
    [0, 0.5, 2, 12.25, 1440].map(formatRateMinutes),
    ['0.00', '0.50', '2.00', '12.25', '1440.00'],
  );
});

test('UT-RATE-1-04: two snapshots differing in one rate hash differently', async () => {
  const changed = clone(goldenV2.snapshot);
  changed.rates![0].minutes_per_unit = 2.75;
  assert.notEqual(await hashSnapshot(changed), goldenV2.expected_hash);

  const source = clone(goldenV2.snapshot);
  source.rates![0].source = 'measured';
  assert.notEqual(await hashSnapshot(source), goldenV2.expected_hash);

  const scaling = clone(goldenV2.snapshot);
  scaling.scaling![0].scales_with = 'per_unit';
  assert.notEqual(await hashSnapshot(scaling), goldenV2.expected_hash);
});

test('UT-RATE-1-05: a v2 snapshot with no Items row still hashes, with only the header changed', async () => {
  const noItems: MapSnapshot = {...clone(base), schema_version: 2, scaling: [], rates: []};
  const canonical = canonicalizeSnapshot(noItems);
  assert.equal(canonical, canonicalizeSnapshot(base).replace(/^v1\n/, 'v2\n'));
  assert.match(await hashSnapshot(noItems), /^[0-9a-f]{64}$/);
  // scaling/rates absent entirely behaves the same as empty.
  const absent: MapSnapshot = {...clone(base), schema_version: 2};
  assert.equal(canonicalizeSnapshot(absent), canonical);
});

// Confirmed byte-identical against live pub/canonical_hash on 2026-10-25
// (RATE-1 review pass) — the spec asked for 0 / 0.5 / 2 / 12.25 / 1440 to
// be proven on BOTH sides, not just here.
test('UT-RATE-1-03b: rate minutes 0..1440 hash identically on both sides (pinned)', async () => {
  const snap: MapSnapshot = {
    schema_version: 2,
    title: 'm',
    stages: [],
    lenses: [],
    cells: [],
    links: [],
    scaling: [],
    rates: (
      [
        ['a', 0, 'seed'],
        ['b', 0.5, 'seed'],
        ['c', 2, 'seed'],
        ['d', 12.25, 'seed'],
        ['e', 1440, 'measured'],
      ] as const
    ).map(([q, m, src]) => ({stage_key: 's', quantity_key: q, method_key: 'm', minutes_per_unit: m, source: src})),
  };
  assert.equal(
    canonicalizeSnapshot(snap),
    'v2\ntitle|m\nrate|s|a|m|0.00|seed\nrate|s|b|m|0.50|seed\nrate|s|c|m|2.00|seed\nrate|s|d|m|12.25|seed\nrate|s|e|m|1440.00|measured\n',
  );
  assert.equal(await hashSnapshot(snap), 'a1b42ddc4d22e4a4b291e8b438ade1f0c272435c4534a4e21d75660c7909ce77');
  assert.equal(formatRateMinutes(null), '0.00');
});
