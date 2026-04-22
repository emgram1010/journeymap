import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyMatrixSearchFilter,
  findMatrixCellIdFromClickTarget,
  formatLensCellMarkup,
  formatMatrixCellMarkup,
  syncSelectedMatrixCellClasses,
  resolveEmotionColor,
  resolveFinancialPriorityColor,
  formatCustomerTileMarkup,
  formatInternalTileMarkup,
  formatEngineeringTileMarkup,
  formatAiAgentTileMarkup,
  formatFinancialTileMarkup,
  formatVendorTileMarkup,
  formatHandoffTileMarkup,
} from './journeyMatrixTabulatorHelpers';
import type {MatrixCell, Stage} from './types';

const baseCell: MatrixCell = {
  id: 'cell-1',
  stageId: 'stage-a',
  lensId: 'lens-a',
  content: '',
  status: 'open',
  isLocked: false,
};

const searchStages: Stage[] = [
  {id: 'stage-a', label: 'Stage A'},
  {id: 'stage-b', label: 'Stage B'},
];

test('formatLensCellMarkup escapes lens labels and renders actor pill and edit button', () => {
  const markup = formatLensCellMarkup({label: '<Customer & Ops>', actorType: 'internal', lensId: 'lens-42'});

  assert.ok(markup.includes('&lt;Customer &amp; Ops&gt;'));
  assert.ok(markup.includes('jm-lens-cell'));
  assert.ok(markup.includes('jm-lens-actor-pill'));
  assert.ok(markup.includes('internal'));
  assert.ok(markup.includes('data-edit-lens-id="lens-42"'));
  assert.ok(markup.includes('jm-lens-edit-btn'));
});

test('formatLensCellMarkup renders without pill or edit button when actorType and lensId are absent', () => {
  const markup = formatLensCellMarkup({label: 'Plain Row'});

  assert.ok(markup.includes('Plain Row'));
  assert.ok(!markup.includes('jm-lens-actor-pill'));
  assert.ok(!markup.includes('jm-lens-edit-btn'));
});

test('formatMatrixCellMarkup renders selected confirmed cells with escaped content and data-cell-id', () => {
  const markup = formatMatrixCellMarkup({
    content: '<draft>',
    meta: {...baseCell, status: 'confirmed'},
    selectedCellId: 'cell-1',
  });

  assert.ok(markup.includes('jm-grid-cell is-selected'));
  assert.ok(markup.includes('data-cell-id="cell-1"'));
  assert.ok(markup.includes('&lt;draft&gt;'));
  assert.ok(markup.includes('jm-status-indicator confirmed'));
});

test('formatMatrixCellMarkup shows lock indicator for locked cells', () => {
  const markup = formatMatrixCellMarkup({
    content: '',
    meta: {...baseCell, isLocked: true, status: 'draft'},
    selectedCellId: null,
  });

  assert.ok(markup.includes('jm-status-indicator lock'));
  assert.ok(markup.includes('🔒'));
  assert.ok(markup.includes('No data'));
});

test('findMatrixCellIdFromClickTarget resolves delegated selection only within the matrix container', () => {
  const gridCell = {dataset: {cellId: 'cell-99'}};
  const target = {closest: (selector: string) => (selector === '.jm-grid-cell[data-cell-id]' ? gridCell : null)};
  const container = {contains: (node: unknown) => node === gridCell};

  assert.equal(findMatrixCellIdFromClickTarget(target as unknown as EventTarget, container), 'cell-99');
  assert.equal(findMatrixCellIdFromClickTarget(target as unknown as EventTarget, {contains: () => false}), null);
});

test('syncSelectedMatrixCellClasses toggles only matching data cells', () => {
  const selectedToggles: Array<{className: string; force?: boolean}> = [];
  const otherToggles: Array<{className: string; force?: boolean}> = [];

  const selectedGridCell = {
    classList: {toggle: (className: string, force?: boolean) => selectedToggles.push({className, force})},
  };
  const otherGridCell = {
    classList: {toggle: (className: string, force?: boolean) => otherToggles.push({className, force})},
  };

  syncSelectedMatrixCellClasses(
    {
      getRows: () => [
        {
          getData: () => ({id: 'lens-a'}),
          getCells: () => [
            {getField: () => 'lensLabel', getElement: () => ({querySelector: () => selectedGridCell})},
            {getField: () => 'stage-a', getElement: () => ({querySelector: () => selectedGridCell})},
            {getField: () => 'stage-b', getElement: () => ({querySelector: () => otherGridCell})},
          ],
        },
      ],
    },
    new Map([
      ['stage-a:lens-a', {...baseCell, id: 'cell-1'}],
      ['stage-b:lens-a', {...baseCell, id: 'cell-2', stageId: 'stage-b'}],
    ]),
    'cell-1',
  );

  assert.deepEqual(selectedToggles, [{className: 'is-selected', force: true}]);
  assert.deepEqual(otherToggles, [{className: 'is-selected', force: false}]);
});

test('applyMatrixSearchFilter clears existing filters for blank queries', () => {
  let clearCalls = 0;
  let setCalls = 0;

  applyMatrixSearchFilter(
    {
      clearFilter: () => {
        clearCalls += 1;
      },
      setFilter: () => {
        setCalls += 1;
      },
    },
    '   ',
    searchStages,
  );

  assert.equal(clearCalls, 1);
  assert.equal(setCalls, 0);
});

// ── US-ICT-00: resolveEmotionColor ──────────────────────────────────────────

test('resolveEmotionColor returns red for frustrated emotions', () => {
  const {color, label} = resolveEmotionColor('Frustrated — waiting too long');
  assert.equal(color, '#ef4444');
  assert.ok(label.endsWith('\u2026'));
  assert.ok(label.length <= 19); // 18 chars + ellipsis
});

test('resolveEmotionColor returns green for confident emotions', () => {
  const {color, label} = resolveEmotionColor('Confident');
  assert.equal(color, '#22c55e');
  assert.equal(label, 'Confident');
});

test('resolveEmotionColor returns yellow default for null', () => {
  const {color, label} = resolveEmotionColor(null);
  assert.equal(color, '#f59e0b');
  assert.equal(label, 'Neutral');
});

test('resolveEmotionColor returns yellow default for neutral emotions', () => {
  const {color} = resolveEmotionColor('Neutral. Mild reassurance.');
  assert.equal(color, '#f59e0b');
});

// ── US-ICT-00: resolveFinancialPriorityColor ─────────────────────────────────

test('resolveFinancialPriorityColor returns red for high priority', () => {
  assert.equal(resolveFinancialPriorityColor('High — $7K/mo recoverable'), '#ef4444');
});

test('resolveFinancialPriorityColor returns yellow for medium priority', () => {
  assert.equal(resolveFinancialPriorityColor('Medium impact'), '#f59e0b');
});

test('resolveFinancialPriorityColor returns green for low priority', () => {
  assert.equal(resolveFinancialPriorityColor('Low priority'), '#22c55e');
});

test('resolveFinancialPriorityColor returns grey for null', () => {
  assert.equal(resolveFinancialPriorityColor(null), '#a1a1aa');
});

// ── US-ICT-01: formatCustomerTileMarkup ─────────────────────────────────────

test('formatCustomerTileMarkup renders emotion badge and entry trigger', () => {
  const markup = formatCustomerTileMarkup({emotions: 'Neutral', entry_trigger: 'Order placed', friction_points: null});
  assert.ok(markup.includes('jm-tile-emotion-badge'));
  assert.ok(markup.includes('#f59e0b'));
  assert.ok(markup.includes('Order placed'));
  assert.ok(!markup.includes('Pain Point'));
});

test('formatCustomerTileMarkup shows Pain Point tag when friction_points is filled', () => {
  const markup = formatCustomerTileMarkup({emotions: 'Frustrated', entry_trigger: 'Waiting', friction_points: 'Long wait time'});
  assert.ok(markup.includes('Pain Point'));
  assert.ok(markup.includes('#ef4444'));
});

test('formatCustomerTileMarkup returns empty state when all fields null', () => {
  const markup = formatCustomerTileMarkup({});
  assert.ok(markup.includes('No data yet'));
  assert.ok(!markup.includes('jm-tile-emotion-badge'));
});

// ── US-ICT-02: formatInternalTileMarkup ─────────────────────────────────────

test('formatInternalTileMarkup renders task and omits tools when null', () => {
  const markup = formatInternalTileMarkup({task_objective: 'Match driver', tools_systems: null});
  assert.ok(markup.includes('Task: Match driver'));
  assert.ok(!markup.includes('Tools:'));
});

test('formatInternalTileMarkup renders both Pain Point and Handoff tags simultaneously', () => {
  const markup = formatInternalTileMarkup({pain_points: 'Manual process', handoff_dependencies: 'Driver app'});
  assert.ok(markup.includes('Pain Point'));
  assert.ok(markup.includes('Handoff'));
});

test('formatInternalTileMarkup returns empty state when all fields null', () => {
  assert.ok(formatInternalTileMarkup({}).includes('No data yet'));
});

// ── US-ICT-03: formatEngineeringTileMarkup ───────────────────────────────────

test('formatEngineeringTileMarkup renders system and data flow', () => {
  const markup = formatEngineeringTileMarkup({system_service_owner: 'Match Service', data_inputs: 'Order', data_outputs: 'Driver ID'});
  assert.ok(markup.includes('System: Match Service'));
  assert.ok(markup.includes('In:'));
  assert.ok(markup.includes('Out:'));
});

test('formatEngineeringTileMarkup omits flow line when both data fields are null', () => {
  const markup = formatEngineeringTileMarkup({system_service_owner: 'Auth Service', data_inputs: null, data_outputs: null});
  assert.ok(!markup.includes('jm-tile-flow'));
});

test('formatEngineeringTileMarkup shows error tag when error_states_edge_cases filled', () => {
  const markup = formatEngineeringTileMarkup({error_states_edge_cases: 'Timeout on 3rd retry'});
  assert.ok(markup.includes('Error States'));
});

// ── US-ICT-04: formatAiAgentTileMarkup ──────────────────────────────────────

test('formatAiAgentTileMarkup falls back to AI Agent label when model is null', () => {
  const markup = formatAiAgentTileMarkup({decision_output: 'Match score'});
  assert.ok(markup.includes('AI Agent'));
});

test('formatAiAgentTileMarkup shows Escalates tag when escalation_logic filled', () => {
  const markup = formatAiAgentTileMarkup({ai_model_agent: 'GPT-4o', escalation_logic: 'Route to human if < 70%'});
  assert.ok(markup.includes('Escalates'));
  assert.ok(markup.includes('escalation'));
});

test('formatAiAgentTileMarkup returns empty state when all fields null', () => {
  assert.ok(formatAiAgentTileMarkup({}).includes('No data yet'));
});

// ── US-ICT-05: formatFinancialTileMarkup ─────────────────────────────────────

test('formatFinancialTileMarkup applies priority color to badge', () => {
  const markup = formatFinancialTileMarkup({priority_score: 'High — $7K/mo', cost_to_serve: '$1.20'});
  assert.ok(markup.includes('#ef4444'));
  assert.ok(markup.includes('Priority:'));
});

test('formatFinancialTileMarkup shows Revenue Leakage tag when filled', () => {
  const markup = formatFinancialTileMarkup({revenue_leakage: '18% drop-off'});
  assert.ok(markup.includes('Revenue Leakage'));
});

test('formatFinancialTileMarkup omits cost or risk independently when null', () => {
  const markupCostOnly = formatFinancialTileMarkup({cost_to_serve: '$1.20', revenue_at_risk: null});
  assert.ok(markupCostOnly.includes('Cost:'));
  assert.ok(!markupCostOnly.includes('Risk:'));
});

// ── US-ICT-06: formatVendorTileMarkup ───────────────────────────────────────

test('formatVendorTileMarkup renders vendor and role, shows failure tag', () => {
  const markup = formatVendorTileMarkup({vendor_name_type: 'Google Maps', role_at_step: 'Routing', failure_scenario: 'API timeout'});
  assert.ok(markup.includes('Vendor: Google Maps'));
  assert.ok(markup.includes('Role: Routing'));
  assert.ok(markup.includes('Failure Risk'));
});

test('formatVendorTileMarkup omits SLA line when both sla and cost are null', () => {
  const markup = formatVendorTileMarkup({vendor_name_type: 'Stripe', sla_performance_metrics: null, cost_impact: null});
  assert.ok(!markup.includes('SLA:'));
  assert.ok(!markup.includes('Cost:'));
});

// ── US-ICT-07: formatHandoffTileMarkup ──────────────────────────────────────

test('formatHandoffTileMarkup renders trigger and full flow', () => {
  const markup = formatHandoffTileMarkup({trigger_event: 'Order confirmed', upstream_actor: 'Retail Partner', downstream_actor: 'Driver'});
  assert.ok(markup.includes('Trigger: Order confirmed'));
  assert.ok(markup.includes('Retail Partner'));
  assert.ok(markup.includes('Driver'));
});

test('formatHandoffTileMarkup renders partial flow with upstream only', () => {
  const markup = formatHandoffTileMarkup({upstream_actor: 'Retail Partner', downstream_actor: null});
  assert.ok(markup.includes('Retail Partner'));
  assert.ok(markup.includes('\u2192'));
  assert.ok(!markup.includes('null'));
});

test('formatHandoffTileMarkup shows failure recovery tag', () => {
  const markup = formatHandoffTileMarkup({failure_recovery: 'Retry 3x then alert ops'});
  assert.ok(markup.includes('Failure Recovery'));
});

// ── US-ICT-08: formatMatrixCellMarkup delegation ────────────────────────────

test('formatMatrixCellMarkup delegates to customer tile when actorType is customer', () => {
  const markup = formatMatrixCellMarkup({
    content: 'ignored text',
    meta: {...baseCell, actorFields: {emotions: 'Confident', entry_trigger: 'App opened', friction_points: null}},
    selectedCellId: null,
    actorType: 'customer',
  });
  assert.ok(markup.includes('jm-tile-emotion-badge'));
  assert.ok(markup.includes('#22c55e'));
  assert.ok(!markup.includes('ignored text'));
});

test('formatMatrixCellMarkup falls through to content text for operations actorType', () => {
  const markup = formatMatrixCellMarkup({
    content: 'Some ops notes',
    meta: baseCell,
    selectedCellId: null,
    actorType: 'operations',
  });
  assert.ok(markup.includes('Some ops notes'));
  assert.ok(!markup.includes('jm-tile-emotion-badge'));
});

test('applyMatrixSearchFilter matches lens labels and stage cell content case-insensitively', () => {
  let predicate: ((rowData: Record<string, string>) => boolean) | null = null;

  applyMatrixSearchFilter(
    {
      clearFilter: () => {
        assert.fail('blank-query clearFilter path should not run');
      },
      setFilter: (nextPredicate) => {
        predicate = nextPredicate;
      },
    },
    ' Ops ',
    searchStages,
  );

  assert.ok(predicate);
  assert.equal(predicate?.({lensLabel: 'Customer Ops', 'stage-a': '', 'stage-b': ''}), true);
  assert.equal(predicate?.({lensLabel: 'Customer', 'stage-a': 'Needs OPS review', 'stage-b': ''}), true);
  assert.equal(predicate?.({lensLabel: 'Customer', 'stage-a': '', 'stage-b': 'No match'}), false);
});