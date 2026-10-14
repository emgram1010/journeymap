// PUB-1 — Functional tests for the publish gate and version integrity.
//
// SCOPE, AND WHY: these cases are side-effect free on purpose. They drive
// the pure functions (pub/canonical_hash, pub/evaluate_readiness,
// pub/evaluate_gate) with fixed snapshots, plus a read-only verification
// of a stored version. They can therefore run repeatedly against the live
// workspace without publishing anything or changing a map's status.
//
// The write path (gate rejection leaves nothing behind, version 1 then 2,
// link to the automation snapshot, tamper detection, access denial,
// placeholder title) was exercised end-to-end over real authenticated
// HTTP on 2026-10-14 and recorded in EPIC-PUB-1's Test Results. It is not
// re-driven here because every run would publish a real map and append
// real version rows — a test that mutates live definition data each time
// it runs is worse than one that documents what was verified.
//
// THE HASH ASSERTION IS A CONTRACT, NOT A SNAPSHOT TEST: the pinned hash
// below is the same value pinned in webapp/protype-2/src/versionHash.test.ts.
// Those two files are the only thing keeping the frontend and backend
// serialisations byte-identical. If this fails, do not "update the
// expected value" — find out which side moved, because every version row
// written before the change will stop verifying.
workflow_test publish_version {
  stack {
    // ── The shared fixture both implementations are pinned to ────────────
    var $fixture {
      value = {
        schema_version: 1
        title         : "Leads to sales"
        stages        : [
          {key: "s1", label: "Initial contact", owner_lens_key: "lens-2"}
          {key: "s2", label: "Quote", owner_lens_key: "lens-2"}
        ]
        lenses        : [
          {key: "lens-1", label: "Customer", actor_type: "customer", does_planned_work: false}
          {key: "lens-2", label: "Sales Coordinator", actor_type: "internal", does_planned_work: true}
        ]
        cells         : [
          {stage_key: "s1", lens_key: "lens-2", task: "Log the lead", done_when: "CRM record exists", duration_minutes: 15}
          {stage_key: "s2", lens_key: "lens-2", task: "Draft the quote", done_when: null, duration_minutes: 90}
        ]
        links         : [
          {stage_key: "s2", lens_key: "lens-2", link_type: "exception", target_map_id: 42}
        ]
      }
    }

    // ── UT-PUB-1-01 (backend half): the pinned canonical string and hash ──
    function.run "pub/canonical_hash" {
      input = {snapshot: $fixture}
    } as $hashed

    expect.to_equal ($hashed.hash) {
      value = "0c62343204f24db1f11a906693f342101ee41122eaa7402f25cb3d3db9c97109"
    }

    expect.to_equal ($hashed.canonical) {
      value = "v1\ntitle|Leads to sales\nstage|s1|Initial contact|lens-2\nstage|s2|Quote|lens-2\nlens|lens-1|Customer|customer|0\nlens|lens-2|Sales Coordinator|internal|1\ncell|s1|lens-2|Log the lead|CRM record exists|15\ncell|s2|lens-2|Draft the quote||90\nlink|s2|lens-2|exception|42\n"
    }

    // ── UT-PUB-1-02: one minute of difference changes the hash ───────────
    var $fixture_one_minute_later {
      value = {
        schema_version: 1
        title         : "Leads to sales"
        stages        : [
          {key: "s1", label: "Initial contact", owner_lens_key: "lens-2"}
          {key: "s2", label: "Quote", owner_lens_key: "lens-2"}
        ]
        lenses        : [
          {key: "lens-1", label: "Customer", actor_type: "customer", does_planned_work: false}
          {key: "lens-2", label: "Sales Coordinator", actor_type: "internal", does_planned_work: true}
        ]
        cells         : [
          {stage_key: "s1", lens_key: "lens-2", task: "Log the lead", done_when: "CRM record exists", duration_minutes: 16}
          {stage_key: "s2", lens_key: "lens-2", task: "Draft the quote", done_when: null, duration_minutes: 90}
        ]
        links         : [
          {stage_key: "s2", lens_key: "lens-2", link_type: "exception", target_map_id: 42}
        ]
      }
    }

    function.run "pub/canonical_hash" {
      input = {snapshot: $fixture_one_minute_later}
    } as $hashed_changed

    expect.to_not_equal ($hashed_changed.hash) {
      value = $hashed.hash
    }

    // ── UT-PUB-1-03: escaping — a separator inside a value cannot forge
    // structure, and the bytes are pinned on both sides. ─────────────────
    function.run "pub/canonical_hash" {
      input = {
        snapshot: {
          schema_version: 1
          title         : "Leads|to\nsales \\ back"
          stages        : [{key: "s1", label: "A|B", owner_lens_key: null}]
          lenses        : []
          cells         : [{stage_key: "s1", lens_key: "l1", task: null, done_when: null, duration_minutes: null}]
          links         : []
        }
      }
    } as $hashed_escaped

    expect.to_equal ($hashed_escaped.hash) {
      value = "5c2e823ffb28c9f34090532733b3ec4c4846948d5334a238e9c53d8746d3160e"
    }

    // ── FT-PUB-1-01 / FT-PUB-1-04: the AUTH-1 golden fixture (map 178's
    // shape) produces exactly the codes AUTH-1's readiness.ts produces:
    // customer-owned stages are OWNER_NOT_WORK_ROLE, the internal-owned
    // ones are missing their task and duration. ──────────────────────────
    var $map178_fixture {
      value = {
        schema_version: 1
        title         : "leads-to-sales-baseline"
        stages        : [
          {key: "s1", label: "Initial Contact", owner_lens_key: "lens-2"}
          {key: "s2", label: "Event Details Gathering", owner_lens_key: "lens-2"}
          {key: "s3", label: "Item Specification", owner_lens_key: "lens-2"}
          {key: "s4", label: "Clarification & Refinement", owner_lens_key: "lens-2"}
          {key: "s5", label: "Quote Preparation", owner_lens_key: "lens-3"}
          {key: "s6", label: "Quote Delivery", owner_lens_key: "lens-3"}
          {key: "s7", label: "Follow-Up & Negotiation", owner_lens_key: "lens-2"}
          {key: "s8", label: "Booking Confirmation", owner_lens_key: "lens-3"}
        ]
        lenses        : [
          {key: "lens-2", label: "Customer", actor_type: "customer", does_planned_work: false}
          {key: "lens-3", label: "Sales Coordinator", actor_type: "internal", does_planned_work: true}
        ]
        cells         : []
        links         : []
      }
    }

    function.run "pub/evaluate_readiness" {
      input = {snapshot: $map178_fixture}
    } as $map178_readiness

    expect.to_equal ($map178_readiness.ready) {
      value = false
    }

    expect.to_equal ($map178_readiness.total) {
      value = 8
    }

    expect.to_equal ($map178_readiness.ready_count) {
      value = 0
    }

    // 5 customer-owned stages × OWNER_NOT_WORK_ROLE, plus 3 internal-owned
    // stages × (NO_TASK + NO_DURATION) = 11 blockers.
    expect.to_equal ($map178_readiness.blockers|count) {
      value = 11
    }

    // ── A fully ready map passes with no blockers ────────────────────────
    function.run "pub/evaluate_readiness" {
      input = {snapshot: $fixture}
    } as $ready_readiness

    expect.to_equal ($ready_readiness.ready) {
      value = true
    }

    expect.to_equal ($ready_readiness.blockers|count) {
      value = 0
    }

    // Done-when is a warning, never a blocker (the s2 cell has none).
    expect.to_equal ($ready_readiness.warnings|count) {
      value = 1
    }

    // ── FT-PUB-1-14: a placeholder title is a gate failure even though the
    // map is otherwise ready. The title rule belongs to the gate, not to
    // readiness, which is why readiness above passed the same shape. ─────
    function.run "pub/evaluate_gate" {
      input = {
        snapshot: {
          schema_version: 1
          title         : "  Untitled Journey Map  "
          stages        : [{key: "s1", label: "Stage 1", owner_lens_key: "lens-2"}]
          lenses        : [{key: "lens-2", label: "Internal", actor_type: "internal", does_planned_work: true}]
          cells         : [{stage_key: "s1", lens_key: "lens-2", task: "Do it", done_when: "Done", duration_minutes: 15}]
          links         : []
        }
      }
    } as $placeholder_gate

    expect.to_equal ($placeholder_gate.ready) {
      value = false
    }

    expect.to_equal ($placeholder_gate.gate_failures|count) {
      value = 1
    }

    // ── FT-PUB-1-08 (read-only half): every stored version still verifies
    // against its own hash. A failure here means a row changed outside the
    // publish path — see E-PUB-003. ──────────────────────────────────────
    db.query journey_map_version {
      return = {type: "list"}
    } as $all_versions

    var $unverified_count {
      value = 0
    }

    foreach ($all_versions) {
      each as $version_row {
        function.run "pub/verify_version" {
          input = {journey_map_version_id: $version_row.id}
        } as $verification

        conditional {
          if ($verification.valid != true) {
            var.update $unverified_count {
              value = $unverified_count + 1
            }
          }
        }
      }
    }

    expect.to_equal ($unverified_count) {
      value = 0
    }
  }
}
