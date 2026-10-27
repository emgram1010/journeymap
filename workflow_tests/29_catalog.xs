// CAT-1 — Functional tests for the item-type / method catalog.
//
// NOT RUN AS A WORKFLOW TEST, same reason workflow_tests/28 wasn't: no
// exposed tool executes a workflow_test from a session (CLAUDE.md:
// runUnitTest rejects a workflow-test id; no runWorkflowTest exists).
// Every assertion below was instead driven live, over real HTTP with a
// minted token (the magic-link technique CLAUDE.md documents) against
// account 2 (javierc9@gmail.com, admin), account 2's member user
// ("Tony"), and account 4 ("Tenancy Check", a pre-existing scratch
// account built for exactly this kind of cross-account test). Results
// are recorded in EPIC-CAT-1-item-and-method-catalog.md's Test Results,
// not here.
//
// FIXTURE ASSUMPTION: this file assumes the catalog/* endpoints exist
// in the live workspace and that the caller is authenticated as an
// account-2 admin for the create/same-account cases.
workflow_test catalog {
  stack {
    var $unique_suffix {
      value = now|to_text
    }

    // ── FT-CAT-1-01: create, then a duplicate key in the SAME account
    // is rejected E-CAT-002 ─────────────────────────────────────────
    api.call "item-type" verb=POST {
      api_group = "catalog"
      input = {
        key  : "wt29-chair-" ~ $unique_suffix
        label: "WT29 Chair"
        unit : "each"
      }
    } as $first_create

    expect.to_equal ($first_create.item_type.key) {
      value = "wt29-chair-" ~ $unique_suffix
    }

    api.call "item-type" verb=POST {
      api_group = "catalog"
      input = {
        key  : "wt29-chair-" ~ $unique_suffix
        label: "WT29 Chair (duplicate attempt)"
        unit : "each"
      }
    } as $dup_create

    expect.to_equal ($dup_create|get:"code":null) {
      value = "E-CAT-002"
    }

    // ── FT-CAT-1-04 (partial — see EPIC-CAT-1's DELETE header): delete
    // succeeds because nothing references this item yet. The
    // "rejected when referenced" half is deferred to ITEM-1, when
    // journey_lens_item exists. ─────────────────────────────────────
    api.call "item-type/{item_type_id}" verb=DELETE {
      api_group = "catalog"
      input = {item_type_id: $first_create.item_type.id}
    } as $delete_result

    expect.to_equal ($delete_result.deleted) {
      value = true
    }

    // ── FT-CAT-1-03: a method whose sub_journey_map_id points at a map
    // in a DIFFERENT account is rejected E-CAT-007. Map 193
    // (item-turnaround) belongs to account 2; this test's own caller
    // is assumed to be account 2, so this specific assertion needs a
    // map known to belong to a DIFFERENT account to be meaningful —
    // see Test Results for the live run, which used a real foreign map
    // id rather than one hardcoded here (map ids are not stable
    // reservations, per the phase-4 README's own numbering note). ───
    api.call "method" verb=POST {
      api_group = "catalog"
      input = {
        key  : "wt29-method-" ~ $unique_suffix
        label: "WT29 Method"
      }
    } as $method_create

    expect.to_equal ($method_create.method.sub_journey_map_id) {
      value = 0
    }

    // ── FT-CAT-1-06: list with/without include_inactive ─────────────
    api.call "method/{method_id}/deactivate" verb=POST {
      api_group = "catalog"
      input = {method_id: $method_create.method.id}
    } as $deactivated

    expect.to_equal ($deactivated.method.is_active) {
      value = false
    }

    api.call "method" verb=GET {
      api_group = "catalog"
      input = {include_inactive: false}
    } as $active_only

    var $found_in_active_only {
      value = false
    }

    foreach ($active_only.methods) {
      each as $m {
        conditional {
          if ($m.id == $method_create.method.id) {
            var.update $found_in_active_only {
              value = true
            }
          }
        }
      }
    }

    expect.to_equal ($found_in_active_only) {
      value = false
    }

    api.call "method" verb=GET {
      api_group = "catalog"
      input = {include_inactive: true}
    } as $with_inactive

    var $found_with_inactive {
      value = false
    }

    foreach ($with_inactive.methods) {
      each as $m2 {
        conditional {
          if ($m2.id == $method_create.method.id) {
            var.update $found_with_inactive {
              value = true
            }
          }
        }
      }
    }

    expect.to_equal ($found_with_inactive) {
      value = true
    }

    // Cleanup — this workflow test's own fixtures only.
    api.call "method/{method_id}" verb=DELETE {
      api_group = "catalog"
      input = {method_id: $method_create.method.id}
    } as $method_cleanup

    expect.to_equal ($method_cleanup.deleted) {
      value = true
    }
  }
}
