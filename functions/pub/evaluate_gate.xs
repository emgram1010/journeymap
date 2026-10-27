// PUB-1 (US-PUB-1-02) — The publish gate: AUTH-1's readiness rules plus
// the one extra rule publishing adds, a real map title (D-39).
//
// Kept separate from pub/evaluate_readiness so that function stays a pure
// mirror of AUTH-1 and can be diffed against its golden fixtures. The
// title rule lives here because it is about publishing, not authoring: a
// map called "Untitled Journey Map" is fine to keep working on, and only
// becomes a problem the moment someone tries to freeze it as a version
// other work will pin to.
//
// Output shape is the gate_failures[] contract from the earlier
// publishing initiative (code, stage_key, lens_key, message).
function "pub/evaluate_gate" {
  description = "Publish gate over a map snapshot: AUTH-1 readiness blockers plus the real-title rule."

  input {
    json snapshot {
      description = "From pub/build_map_snapshot."
    }

    // ITEM-1 (US-ITEM-1-05) — additive passthrough to evaluate_readiness.
    json items_cells? {
      description = "Optional. See pub/evaluate_readiness's own input for the shape."
    }

    // RATE-1 (US-RATE-1-04) — the map's account, for the inactive-item
    // rule. 0 (omitted) skips that rule, so older callers are unchanged.
    int account_id? {
      description = "Optional. The map's account_id; enables the E-RATE-001 inactive-item check."
    }

    // EXC-1 (US-EXC-1-01) — optional passthrough to evaluate_readiness
    // (from exceptions/exception_targets). Warnings only; never a gate failure.
    json exception_targets?
  }

  stack {
    function.run "pub/evaluate_readiness" {
      input = {snapshot: $input.snapshot, items_cells: $input.items_cells, exception_targets: $input.exception_targets}
    } as $readiness

    var $gate_failures {
      value = $readiness.blockers
    }

    // A placeholder title is not a real name. Compared lower-cased and
    // trimmed so "  Untitled Journey Map " is caught too. An empty title
    // is already a NO_WORK_TYPE_NAME blocker from readiness, so it is not
    // repeated here.
    var $title_normalised {
      value = ($input.snapshot.title ?? "")|trim|lower
    }

    var $is_placeholder {
      value = ($title_normalised == "untitled" || $title_normalised == "untitled map" || $title_normalised == "untitled journey map" || $title_normalised == "new map" || $title_normalised == "new journey map")
    }

    conditional {
      if ($is_placeholder == true) {
        array.push $gate_failures {
          value = {
            code     : "PLACEHOLDER_TITLE"
            stage_key: null
            lens_key : null
            message  : "Give this map a real name before publishing it."
          }
        }
      }
    }

    // RATE-1 (US-RATE-1-04, PRD EC-3) — a NEW version may not pin a rate
    // for an item that has since been deactivated. Old versions keep
    // theirs. Checks snapshot.rates (what would actually be frozen); a
    // line with an empty minutes box pins nothing and stays ITEM-1's
    // warning. One query with `in`, no conditional inside a loop.
    var $rate_item_keys {
      value = ["__none__"]
    }

    var $gate_rates {
      value = $input.snapshot.rates ?? []
    }

    foreach ($gate_rates) {
      each as $gate_rate {
        array.push $rate_item_keys {
          value = $gate_rate.quantity_key
        }
      }
    }

    conditional {
      if ($input.account_id != 0 && ($gate_rates|count) > 0) {
        db.query item_type {
          where = $db.item_type.account_id == $input.account_id && $db.item_type.key in $rate_item_keys && $db.item_type.is_active == false
          sort = {key: "asc"}
          return = {type: "list"}
        } as $inactive_items

        foreach ($inactive_items) {
          each as $inactive_item {
            array.push $gate_failures {
              value = {
                code      : "INACTIVE_ITEM"
                error_code: "E-RATE-001"
                stage_key : null
                lens_key  : null
                item_key  : $inactive_item.key
                message   : "An item on this map was deactivated: " ~ ($inactive_item.label ?? $inactive_item.key) ~ ". Remove its line or reactivate it, then publish."
              }
            }
          }
        }
      }
    }

    var $failure_count {
      value = $gate_failures|count
    }

    var $ready {
      value = ($failure_count == 0 && $readiness.total > 0)
    }
  }

  response = {
    ready        : $ready
    gate_failures: $gate_failures
    warnings     : $readiness.warnings
    ready_count  : $readiness.ready_count
    total        : $readiness.total
  }
}
