// RATE-1 — Publish the rate card: canonical hash v1/v2 goldens, the
// snapshot's rates section, verify_version's rate count and the audit.
//
// NOT RUN AS A WORKFLOW TEST. There is no exposed tool to execute a
// workflow_test from an AI session (CLAUDE.md). Every assertion below was
// driven through `runWorkspaceFunction` or real HTTP on 2026-10-25, with
// the live results recorded in EPIC-RATE-1's Test Results. This file is
// the durable form of the function-level checks. The publish / delete
// endpoint checks (FT-RATE-1-03/04/05/09, G01/G02) need an authenticated
// HTTP caller and are recorded in Test Results only.
//
// FIXTURES: map 216 (RATE-1 clone of 193, Items row, versions 17 and 18
// with 6 rates each) and map 218 (clone of 193 with no Items row,
// version 19). Replace the ids if those have been cleaned up.
//
// The frontend twin is webapp/protype-2/src/versionHash.test.ts
// (UT-RATE-1-01..05) and fixtures/version-hash-golden-v2.json.
workflow_test publish_rates {
  stack {
    // ── FT-RATE-1-01: canonical_hash on the v2 golden ───────────────────
    function.run "pub/canonical_hash" {
      input = {
        snapshot: {
          schema_version: 2
          title         : "Item turnaround"
          stages        : [{key: "s1", label: "Receive", owner_lens_key: "lens-1"}, {key: "s2", label: "Clean", owner_lens_key: "lens-1"}]
          lenses        : [{key: "lens-1", label: "Crew", actor_type: "internal", does_planned_work: true}, {key: "items", label: "Items", actor_type: "", does_planned_work: false}]
          cells         : [{stage_key: "s1", lens_key: "lens-1", task: "Count the load", done_when: "Count logged", duration_minutes: 10}, {stage_key: "s2", lens_key: "lens-1", task: "Wash", done_when: null, duration_minutes: 30}]
          links         : []
          scaling       : [{stage_key: "s1", scales_with: "per_order"}, {stage_key: "s2", scales_with: "per_unit"}]
          rates         : [{stage_key: "s2", quantity_key: "chair-resin", method_key: "hand-wash", minutes_per_unit: 2.5, source: "seed"}, {stage_key: "s2", quantity_key: "chair-resin", method_key: "pressure-wash", minutes_per_unit: 0.5, source: "seed"}, {stage_key: "s2", quantity_key: "table-6ft", method_key: "hand-wash", minutes_per_unit: 12.25, source: "seed"}]
        }
      }
    } as $v2

    expect.to_equal ($v2.hash) {
      value = "5ecc3e7eef1b1155ecb9659f01dff21cf5e253e14c5a0e19bc0498b632741c54"
    }

    // ── FT-RATE-1-02: canonical_hash on the v1 golden (rates ignored) ───
    function.run "pub/canonical_hash" {
      input = {
        snapshot: {
          schema_version: 1
          title         : "Leads to sales"
          stages        : [{key: "s1", label: "Initial contact", owner_lens_key: "lens-2"}, {key: "s2", label: "Quote", owner_lens_key: "lens-2"}]
          lenses        : [{key: "lens-1", label: "Customer", actor_type: "customer", does_planned_work: false}, {key: "lens-2", label: "Sales Coordinator", actor_type: "internal", does_planned_work: true}]
          cells         : [{stage_key: "s1", lens_key: "lens-2", task: "Log the lead", done_when: "CRM record exists", duration_minutes: 15}, {stage_key: "s2", lens_key: "lens-2", task: "Draft the quote", done_when: null, duration_minutes: 90}]
          links         : [{stage_key: "s2", lens_key: "lens-2", link_type: "exception", target_map_id: 42}]
          rates         : [{stage_key: "s1", quantity_key: "x", method_key: "y", minutes_per_unit: 1, source: "seed"}]
        }
      }
    } as $v1

    expect.to_equal ($v1.hash) {
      value = "0c62343204f24db1f11a906693f342101ee41122eaa7402f25cb3d3db9c97109"
    }

    // ── US-RATE-1-02: a map with an Items row snapshots as v2 ───────────
    function.run "pub/build_map_snapshot" {
      input = {journey_map_id: 216}
    } as $rated

    expect.to_equal ($rated.snapshot.schema_version) {
      value = 2
    }

    expect.to_equal ($rated.snapshot.rates|count) {
      value = 6
    }

    // ── D-1: a map with no Items row stays v1 (no false "stale") ────────
    function.run "pub/build_map_snapshot" {
      input = {journey_map_id: 218}
    } as $plain

    expect.to_equal ($plain.snapshot.schema_version) {
      value = 1
    }

    // ── FT-RATE-1-04 / -06: both rated versions verify, rates intact ────
    function.run "pub/verify_version" {
      input = {journey_map_version_id: 17}
    } as $ver17

    expect.to_equal ($ver17.valid) {
      value = true
    }
    expect.to_equal ($ver17.rates_ok) {
      value = true
    }

    function.run "pub/verify_version" {
      input = {journey_map_version_id: 18}
    } as $ver18

    expect.to_equal ($ver18.valid) {
      value = true
    }
    expect.to_equal ($ver18.rates_ok) {
      value = true
    }

    // ── FT-RATE-1-06: the audit finds no rate mismatches ────────────────
    // (Hash mismatches on map 200's three hand-built JOB-1 fixture
    // versions are pre-existing and expected; see Test Results.)
    function.run "ops/audit_rates" {
      input = {}
    } as $audit

    expect.to_equal ($audit.rate_mismatch_count) {
      value = 0
    }
  }
}
