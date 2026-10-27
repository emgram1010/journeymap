// EST-1 — estimate_job / compute_estimate over every golden fixture.
//
// NOT RUN AS A WORKFLOW TEST. There is no exposed tool to execute a
// workflow_test from an AI session (CLAUDE.md). Every assertion below
// was driven live through `runWorkspaceFunction` against
// `estimate/compute_estimate` (function id 236) on 2026-10-25, with
// the full request/response pairs recorded in EPIC-EST-1's Test
// Results. This file is the durable form of those checks.
//
// The frontend twin is webapp/protype-2/src/estimate/estimateJob.test.ts
// and src/fixtures/estimate-golden.json — this file runs the SAME
// fixtures through the backend. See that JSON file's header for why
// the numbers here are hand-verified, not copied from the epic's own
// (self-inconsistent) illustrative sample.
workflow_test estimate {
  stack {
    // ── UT-EST-1-01 / 08: a real order over 8 stages ────────────────────
    function.run "estimate/compute_estimate" {
      input = {
        snapshot: {
          schema_version: 2
          stages: [
            {key: "s1", owner_lens_key: "lens-1"}
            {key: "s2", owner_lens_key: "lens-1"}
            {key: "s3", owner_lens_key: "lens-1"}
            {key: "s4", owner_lens_key: "lens-1"}
            {key: "s5", owner_lens_key: "lens-1"}
            {key: "s6", owner_lens_key: "lens-1"}
            {key: "s7", owner_lens_key: "lens-1"}
            {key: "s8", owner_lens_key: "lens-1"}
          ]
          cells: [
            {stage_key: "s1", lens_key: "lens-1", duration_minutes: 15}
            {stage_key: "s2", lens_key: "lens-1", duration_minutes: 5}
            {stage_key: "s3", lens_key: "lens-1", duration_minutes: 10}
            {stage_key: "s4", lens_key: "lens-1", duration_minutes: 8}
            {stage_key: "s5", lens_key: "lens-1", duration_minutes: 12}
            {stage_key: "s6", lens_key: "lens-1", duration_minutes: 6}
            {stage_key: "s8", lens_key: "lens-1", duration_minutes: 10}
          ]
          scaling: [
            {stage_key: "s1", scales_with: "per_order"}
            {stage_key: "s2", scales_with: "per_unit"}
            {stage_key: "s3", scales_with: "per_order"}
            {stage_key: "s4", scales_with: "per_order"}
            {stage_key: "s5", scales_with: "per_order"}
            {stage_key: "s6", scales_with: "per_order"}
            {stage_key: "s7", scales_with: "per_order"}
            {stage_key: "s8", scales_with: "per_unit"}
          ]
          rates: [
            {stage_key: "s2", quantity_key: "chair-resin", method_key: "basic", minutes_per_unit: 0.5, source: "seed"}
            {stage_key: "s2", quantity_key: "table-6ft", method_key: "basic", minutes_per_unit: 1.5, source: "seed"}
            {stage_key: "s8", quantity_key: "chair-resin", method_key: "hard-goods", minutes_per_unit: 2.0, source: "seed"}
            {stage_key: "s8", quantity_key: "table-6ft", method_key: "hard-goods", minutes_per_unit: 4.0, source: "seed"}
          ]
        }
        lines: [
          {quantity_key: "chair-resin", quantity: 20, flagged_quantity: 0}
          {quantity_key: "table-6ft", quantity: 3, flagged_quantity: 0}
        ]
      }
    } as $simple

    expect.to_equal ($simple.total_minutes) {
      value = 133
    }
    expect.to_equal ($simple.complete) {
      value = true
    }

    // ── UT-EST-1-02: two orders, same s8 rates ──────────────────────────
    function.run "estimate/compute_estimate" {
      input = {
        snapshot: {
          schema_version: 2
          stages: [{key: "s8", owner_lens_key: "lens-1"}]
          cells: [{stage_key: "s8", lens_key: "lens-1", duration_minutes: 10}]
          scaling: [{stage_key: "s8", scales_with: "per_unit"}]
          rates: [
            {stage_key: "s8", quantity_key: "chair-resin", method_key: "hard-goods", minutes_per_unit: 2.0, source: "seed"}
            {stage_key: "s8", quantity_key: "table-6ft", method_key: "hard-goods", minutes_per_unit: 4.0, source: "seed"}
          ]
        }
        lines: [{quantity_key: "chair-resin", quantity: 12, flagged_quantity: 0}]
      }
    } as $order_a

    expect.to_equal ($order_a.total_minutes) {
      value = 34
    }

    // ── UT-EST-1-04: missing rate at a per-unit stage ───────────────────
    function.run "estimate/compute_estimate" {
      input = {
        snapshot: {
          schema_version: 2
          stages: [{key: "s2", owner_lens_key: "lens-1"}]
          cells: [{stage_key: "s2", lens_key: "lens-1", duration_minutes: 5}]
          scaling: [{stage_key: "s2", scales_with: "per_unit"}]
          rates: [{stage_key: "s2", quantity_key: "chair-resin", method_key: "basic", minutes_per_unit: 0.5, source: "seed"}]
        }
        lines: [{quantity_key: "ghost-item", quantity: 2, flagged_quantity: 0}]
      }
    } as $missing_case

    expect.to_equal ($missing_case.complete) {
      value = false
    }

    // ── UT-EST-1-06: no Items row, lines ignored ────────────────────────
    function.run "estimate/compute_estimate" {
      input = {
        snapshot: {
          schema_version: 1
          stages: [{key: "s1", owner_lens_key: "lens-1"}]
          cells: [{stage_key: "s1", lens_key: "lens-1", duration_minutes: 15}]
        }
        lines: [{quantity_key: "chair-resin", quantity: 999, flagged_quantity: 0}]
      }
    } as $no_items

    expect.to_equal ($no_items.has_items_row) {
      value = false
    }
    expect.to_equal ($no_items.total_minutes) {
      value = 15
    }
  }
}
