// Orders — unit tests for the pure rules behind the "Outside products" and
// "Incoming orders" tabs.
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  toLink,
  refStatus,
  sourceNameProblem,
  mapsForPlan,
  outcomeLabel,
  flagLabel,
  liveMemberOptions,
  liveMemberLabel,
  type PlanAgent,
  type ExternalRef,
} from './ordersModel';

const ref = (over: Partial<ExternalRef>): ExternalRef => ({
  ref_id: 1,
  source_system: 'shop',
  external_id: 'p-1',
  external_name: 'Chair',
  item_type_id: 0,
  not_an_item: false,
  seen_count: 1,
  last_seen_at: null,
  ...over,
});

test('UT-ORD-01: toLink keeps only products with no item that are not marked "not an item"', () => {
  const refs = [
    ref({ref_id: 1}),
    ref({ref_id: 2, item_type_id: 7}),
    ref({ref_id: 3, not_an_item: true}),
    ref({ref_id: 4}),
  ];
  assert.deepEqual(
    toLink(refs).map((r) => r.ref_id),
    [1, 4],
  );
});

test('UT-ORD-02: toLink is safe on an empty list', () => {
  assert.deepEqual(toLink([]), []);
});

test('UT-ORD-03: refStatus names the three states', () => {
  assert.equal(refStatus(ref({item_type_id: 7})), 'Linked');
  assert.equal(refStatus(ref({not_an_item: true})), 'Not an item');
  assert.equal(refStatus(ref({})), 'Needs linking');
});

test('UT-ORD-04: refStatus treats "not an item" as the answer even if an item id is left over', () => {
  assert.equal(refStatus(ref({item_type_id: 7, not_an_item: true})), 'Not an item');
});

test('UT-ORD-05: sourceNameProblem accepts well-formed names', () => {
  assert.equal(sourceNameProblem('shopify'), null);
  assert.equal(sourceNameProblem('booking-system-2'), null);
  assert.equal(sourceNameProblem('ab'), null);
  assert.equal(sourceNameProblem('9lives'), null);
  assert.equal(sourceNameProblem('a'.repeat(40)), null);
  assert.equal(sourceNameProblem('  shopify  '), null); // surrounding spaces are trimmed
});

test('UT-ORD-06: sourceNameProblem gives a reason for each bad name', () => {
  assert.equal(typeof sourceNameProblem(''), 'string');
  assert.equal(typeof sourceNameProblem('   '), 'string');
  assert.equal(typeof sourceNameProblem('a'), 'string');
  assert.equal(typeof sourceNameProblem('a'.repeat(41)), 'string');
  assert.equal(typeof sourceNameProblem('Shopify'), 'string');
  assert.equal(typeof sourceNameProblem('my shop'), 'string');
  assert.equal(typeof sourceNameProblem('shop_1'), 'string');
  assert.equal(typeof sourceNameProblem('-shop'), 'string');
  assert.equal(typeof sourceNameProblem('<b>shop</b>'), 'string');
});

test('UT-ORD-07: mapsForPlan returns only that plan\'s maps, without repeats', () => {
  const planMaps = [
    {workspace_id: 1, journey_map_id: 10},
    {workspace_id: 2, journey_map_id: 20},
    {workspace_id: 1, journey_map_id: 11},
    {workspace_id: 1, journey_map_id: 10},
  ];
  assert.deepEqual(mapsForPlan(1, planMaps), [10, 11]);
  assert.deepEqual(mapsForPlan(2, planMaps), [20]);
  assert.deepEqual(mapsForPlan(3, planMaps), []);
  assert.deepEqual(mapsForPlan(1, []), []);
});

test('UT-ORD-08: outcomeLabel uses plain words', () => {
  assert.equal(outcomeLabel('no_route'), 'No routing rule matched');
  assert.equal(outcomeLabel('held'), 'Held while AI is paused');
  assert.equal(outcomeLabel('failed'), 'Could not be added');
  assert.equal(outcomeLabel('refused'), 'Refused');
});

test('UT-ORD-09: outcomeLabel never shows a raw code for an outcome it does not know', () => {
  assert.equal(outcomeLabel('something_new'), 'Needs a look');
  assert.equal(outcomeLabel(''), 'Needs a look');
});

test('UT-ORD-10: flagLabel uses plain words, with a safe fallback', () => {
  assert.equal(flagLabel('order_changed'), 'Order changed after work started');
  assert.equal(flagLabel('order_cancelled'), 'Order cancelled');
  assert.equal(flagLabel('other'), 'Needs a check');
});

const agents: PlanAgent[] = [
  {agent_id: 1, name: 'Ana', workspace_id: 10, has_login: true},
  {agent_id: 2, name: 'Ben', workspace_id: 10, has_login: false},
  {agent_id: 3, name: 'Cy', workspace_id: 11, has_login: true},
];

test('UT-ORD-11: only members of the rule plan who can sign in may take same-day orders', () => {
  assert.deepEqual(liveMemberOptions(10, agents).map((a) => a.name), ['Ana']);
  assert.deepEqual(liveMemberOptions(99, agents), []);
});

test('UT-ORD-12: the same-day setting reads Off, a name, or a safe fallback', () => {
  assert.equal(liveMemberLabel(0, agents), 'Off');
  assert.equal(liveMemberLabel(undefined, agents), 'Off');
  assert.equal(liveMemberLabel(1, agents), 'Ana');
  assert.equal(liveMemberLabel(77, agents), 'A member who was removed');
});
