// EXC-1 — the line split and the exception readiness warnings over the
// golden fixtures (FT-EXC-1-01, FT-EXC-1-16).
//
// NOT RUN AS A WORKFLOW TEST. There is no exposed tool to execute a
// workflow_test from an AI session (CLAUDE.md). Every assertion below
// was driven live through `runWorkspaceFunction` on 2026-10-26 (scratch
// harnesses over exceptions/split_lines, fn 246, and
// pub/evaluate_readiness, fn 93), with results recorded in
// EPIC-EXC-1's Test Results. The spawn endpoint's own cases
// (FT-EXC-1-02..14, G01..G05) are HTTP/DB tests recorded there too —
// they need real jobs, so they don't fit a fixture-only file.
//
// Frontend twins: webapp/protype-2/src/exceptions/splitLines.test.ts
// (src/fixtures/exception-split-golden.json) and
// src/readiness.test.ts (src/fixtures/exception-readiness-golden.json).
workflow_test exceptions {
  stack {
    // ── UT-EXC-1-01: 2 of 3 tables move ─────────────────────────────────
    function.run "exceptions/split_lines" {
      input = {
        parent_lines: [{item_type_id: 11, item_key: "table", quantity: 3}, {item_type_id: 12, item_key: "chair", quantity: 100}]
        moved       : [{item_type_id: 11, quantity: 2}]
      }
    } as $two

    expect.to_equal ($two.ok) {
      value = true
    }
    expect.to_equal ($two.parent_after) {
      value = [{item_type_id: 11, item_key: "table", quantity: 1}, {item_type_id: 12, item_key: "chair", quantity: 100}]
    }
    expect.to_equal ($two.child_lines) {
      value = [{item_type_id: 11, item_key: "table", quantity: 2}]
    }

    // ── UT-EXC-1-02: all 3 move, the parent line is removed ─────────────
    function.run "exceptions/split_lines" {
      input = {
        parent_lines: [{item_type_id: 11, item_key: "table", quantity: 3}]
        moved       : [{item_type_id: 11, quantity: 3}]
      }
    } as $all

    expect.to_equal ($all.removed) {
      value = [11]
    }
    expect.to_equal ($all.parent_after) {
      value = []
    }

    // ── UT-EXC-1-03: refusals ───────────────────────────────────────────
    function.run "exceptions/split_lines" {
      input = {parent_lines: [{item_type_id: 11, item_key: "table", quantity: 3}], moved: [{item_type_id: 11, quantity: 4}]}
    } as $too_many

    expect.to_equal ($too_many.code) {
      value = "E-EXC-006"
    }

    function.run "exceptions/split_lines" {
      input = {parent_lines: [{item_type_id: 11, item_key: "table", quantity: 3}], moved: [{item_type_id: 11, quantity: 1}, {item_type_id: 11, quantity: 1}]}
    } as $dup

    expect.to_equal ($dup.code) {
      value = "E-EXC-007"
    }

    function.run "exceptions/split_lines" {
      input = {parent_lines: [{item_type_id: 11, item_key: "table", quantity: 3}], moved: [{item_type_id: 99, quantity: 1}]}
    } as $unknown

    expect.to_equal ($unknown.code) {
      value = "E-EXC-005"
    }

    // ── FT-EXC-1-16: readiness warns, never blocks ──────────────────────
    function.run "pub/evaluate_readiness" {
      input = {
        snapshot         : {schema_version: 2, title: "Parent", stages: [], lenses: [], cells: []}
        exception_targets: [{stage_key: "s2", stage_label: "Triage", lens_key: "description", target_map_id: 220, target_title: "Repair", published: false, has_items_row: false, same_architecture: true}]
      }
    } as $ready

    expect.to_equal (($ready.warnings|first).code) {
      value = "exception_map_unpublished"
    }
  }
}
