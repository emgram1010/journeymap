import test from 'node:test';
import assert from 'node:assert/strict';
import {addProblem, filterByTag, tagKey, tagNameProblem, tagsForMap, type MapTag, type MapTagLink} from './tagModel';

const tags: MapTag[] = [
  {map_tag_id: 1, name: 'Ops', map_count: 2},
  {map_tag_id: 2, name: 'Onboarding', map_count: 1},
  {map_tag_id: 3, name: 'Unused', map_count: 0},
];
const links: MapTagLink[] = [
  {journey_map_id: 10, map_tag_id: 1},
  {journey_map_id: 10, map_tag_id: 2},
  {journey_map_id: 11, map_tag_id: 1},
  {journey_map_id: 12, map_tag_id: 99},
];

test('UT-TAG-01 "Ops", "ops" and " OPS " are one tag', () => {
  assert.equal(tagKey('Ops'), tagKey('ops'));
  assert.equal(tagKey(' OPS '), 'ops');
});

test('UT-TAG-02 name rules: empty, 41 characters and HTML are refused; 40 is fine', () => {
  assert.ok(tagNameProblem('   '));
  assert.ok(tagNameProblem('x'.repeat(41)));
  assert.equal(tagNameProblem('x'.repeat(40)), null);
  assert.ok(tagNameProblem('<b>Ops</b>'));
  assert.equal(tagNameProblem('Ops & Finance'), null);
});

test('UT-TAG-03 a map shows its own tags in name order and ignores a link to a deleted tag', () => {
  assert.deepEqual(tagsForMap(10, tags, links).map((t) => t.name), ['Onboarding', 'Ops']);
  assert.deepEqual(tagsForMap(12, tags, links), []);
  assert.deepEqual(tagsForMap(999, tags, links), []);
});

test('UT-TAG-04 filter by tag keeps only tagged maps; 0 means no filter', () => {
  const maps = [{id: 10}, {id: 11}, {id: 12}];
  assert.deepEqual(filterByTag(maps, links, 1).map((m) => m.id), [10, 11]);
  assert.deepEqual(filterByTag(maps, links, 2).map((m) => m.id), [10]);
  assert.deepEqual(filterByTag(maps, links, 3), []);
  assert.deepEqual(filterByTag(maps, links, 0), maps);
});

test('UT-TAG-05 adding a tag the map already has (any case) is stopped with a reason', () => {
  assert.equal(addProblem(10, ' ops ', tags, links), 'This map already has that tag.');
  assert.equal(addProblem(11, 'Onboarding', tags, links), null);
});

test('UT-TAG-06 a map with 20 tags cannot take another', () => {
  const many: MapTag[] = Array.from({length: 20}, (_, i) => ({map_tag_id: 100 + i, name: `T${i}`, map_count: 1}));
  const manyLinks: MapTagLink[] = many.map((t) => ({journey_map_id: 50, map_tag_id: t.map_tag_id}));
  assert.equal(addProblem(50, 'One more', many, manyLinks), 'This map already has 20 tags, the most allowed.');
});
