// ITEM-0 (US-ITEM-0-05) — Guard tests for the Items row.
//
// These exist to FAIL if a future change ever treats the Items row as an
// actor row. The Items row is a `journey_lens` with actor_type = "" and
// template_key = "items-v1" (PRD §2.4, D-IR-11, O-1). It must never do
// planned work, never produce a task, never block readiness, and never
// contribute cost to leakage.
//
// NOT RUN AS A WORKFLOW TEST. There is no exposed tool to execute a
// workflow_test from an AI session (CLAUDE.md): runUnitTest rejects a
// workflow-test id and no runWorkflowTest exists. Every assertion below
// was instead driven through `runWorkspaceFunction` against map 213 (a
// clone of 193) on 2026-10-24, with the live results recorded in
// EPIC-ITEM-0's Test Results. This file is the durable form of those
// checks, for whoever can run it.
//
// FIXTURE ASSUMPTION: a map whose id is passed in $map_id has one actor
// row that owns every stage, and one Items row with key "items". Build it
// with scratch/item0_add_items_row (see Test Results) or ITEM-1's own
// endpoint once that exists.
//
// The frontend twin is webapp/protype-2/src/itemsRowGuards.test.ts.
workflow_test items_row_guards {
  stack {
    // The audit clone. Replace with a fixture the runner creates if 213
    // has been cleaned up.
    var $map_id {
      value = 213
    }

    // ── FT-ITEM-0-01: the Items row is in lenses[] but produces no cells ──
    function.run "pub/build_map_snapshot" {
      input = {
        journey_map_id: $map_id
      }
    } as $snap

    var $items_lens_seen {
      value = 0
    }

    foreach ($snap.snapshot.lenses) {
      each as $l {
        conditional {
          if ($l.key == "items") {
            var.update $items_lens_seen {
              value = $items_lens_seen + 1
            }
          }
        }
      }
    }

    expect.to_equal ($items_lens_seen) {
      value = 1
    }

    var $items_cells_seen {
      value = 0
    }

    foreach ($snap.snapshot.cells) {
      each as $c {
        conditional {
          if ($c.lens_key == "items") {
            var.update $items_cells_seen {
              value = $items_cells_seen + 1
            }
          }
        }
      }
    }

    // The whole reason RATE-1 needs its own snapshot section: Items cells
    // are NOT hashed today, however much data they hold.
    expect.to_equal ($items_cells_seen) {
      value = 0
    }

    // ── FT-ITEM-0-01b: and it resolves to does_planned_work = false ──
    var $items_does_work {
      value = true
    }

    foreach ($snap.snapshot.lenses) {
      each as $l2 {
        conditional {
          if ($l2.key == "items") {
            var.update $items_does_work {
              value = $l2.does_planned_work
            }
          }
        }
      }
    }

    expect.to_equal ($items_does_work) {
      value = false
    }

    // ── FT-ITEM-0-02: readiness is unaffected ──
    function.run "pub/evaluate_readiness" {
      input = {
        snapshot: $snap.snapshot
      }
    } as $ready

    expect.to_equal ($ready.ready) {
      value = true
    }

    expect.to_equal ($ready.blockers|count) {
      value = 0
    }

    // 8 stages, 8 ready work cells — the Items row adds nothing to either
    // side of the count.
    expect.to_equal ($ready.total) {
      value = 8
    }

    expect.to_equal ($ready.ready_count) {
      value = 8
    }

    // ── FT-ITEM-0-03: no task is generated for the Items row ──
    function.run "jobs/tasks_from_version" {
      input = {
        snapshot: $snap.snapshot
      }
    } as $tasks

    var $items_tasks {
      value = 0
    }

    foreach ($tasks.tasks) {
      each as $t {
        conditional {
          if ($t.lens_key == "items") {
            var.update $items_tasks {
              value = $items_tasks + 1
            }
          }
        }
      }
    }

    expect.to_equal ($items_tasks) {
      value = 0
    }

    expect.to_equal ($tasks.tasks|count) {
      value = 8
    }

    // Nothing silently dropped: a stage whose owner does no planned work is
    // reported, and the Items row must never cause such a report.
    expect.to_equal ($tasks.skipped|count) {
      value = 0
    }

    // ── FT-ITEM-0-05: leakage must not charge the Items row ──
    //
    // ⚠️ This assertion currently passes only because the Items row has no
    // cost_rate and its cells have no time_duration. ITEM-0 proved live
    // that giving it both makes calculate_leakage charge it (50/event at
    // s8 on map 213). The guard belongs in calculate_leakage itself —
    // skip rows that do no planned work — and until that is added, this
    // assertion is protecting an accident, not a rule. See ITEM-0's audit
    // finding L-1 and ITEM-1 US-ITEM-1-06.
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $map_id && $db.journey_lens.key == "items"
      return = {type: "single"}
    } as $items_row

    expect.to_equal ($items_row.cost_rate_value) {
      value = 0
    }
  }
}
