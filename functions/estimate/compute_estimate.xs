// EST-1 (US-EST-1-03) — THE ONE FORMULA, pure. The backend half of
// webapp/protype-2/src/estimate/estimateJob.ts; the two MUST produce
// the same result for the same input, and workflow_tests/32_estimate.xs
// drives both over the identical golden fixtures (FT-EST-1-01).
//
// PURE BY INPUT SHAPE ON PURPOSE (same reason as pub/canonical_hash):
// taking {snapshot, lines} directly, instead of a work_item_id, is
// what makes this testable against a golden fixture with
// runWorkspaceFunction. `estimate/estimate_job` is the thin DB-reading
// wrapper real callers use; it loads the job, the pinned version and
// the order lines, then calls this.
//
// D-1 (RATE-1): a v1 snapshot (no Items row, no scaling/rates keys at
// all) makes every stage per_order and the job unconditionally
// complete. Lines are never even read in that case.
//
// WHY A SEPARATE "RATE PRESENCE" PASS, NOT A SINGLE NESTED LOOP: the
// CLAUDE.md trap ("every write in the branch lost, no error") is about
// a var declared OUTSIDE a loop, var.update'd on an earlier iteration,
// and read back to gate a write on a LATER iteration — a cross-
// iteration cursor. A var declared FRESH inside the current iteration
// (`var $x {value=...}`, not var.update), even one built from a
// lookup, is safe and used constantly below ($count, $present,
// $scales_with all read this same iteration they're set). The
// presence map itself is still built in its own completed pass before
// any stage is walked, the same shape as functions/ops/
// group_issues.xs's accumulator — not because reading it later would
// hit the trap, but because every rate needs to be seen once before
// any "is this item missing" question can be answered.
//
// Rounding: round the stage's VARIABLE minutes half-up (TIME-1's
// family), then add the already-whole baseline. Rounding commutes
// with adding an integer, so this is identical to "round the whole
// stage sum," one fewer place to get wrong.
function "estimate/compute_estimate" {
  input {
    json snapshot {
      description = "A journey_map_version.snapshot: schema_version, stages[], cells[], and (v2 only) scaling[] + rates[]."
    }

    json lines {
      description = "[{quantity_key, quantity, flagged_quantity}]. Ignored entirely when the snapshot has no Items row."
    }
  }

  stack {
    var $schema_version {
      value = $input.snapshot.schema_version ?? 1
    }

    var $has_items_row {
      value = ($schema_version >= 2)
    }

    var $stages {
      value = $input.snapshot.stages ?? []
    }

    var $cells {
      value = $input.snapshot.cells ?? []
    }

    var $scaling {
      value = $input.snapshot.scaling ?? []
    }

    var $rates {
      value = $input.snapshot.rates ?? []
    }

    // ── Pre-pass 1: cell lookup, stage_key::lens_key -> cell ───────────
    var $cell_by_key {
      value = {}
    }

    foreach ($cells) {
      each as $c {
        var $cell_key {
          value = $c.stage_key ~ "::" ~ $c.lens_key
        }

        var.update $cell_by_key {
          value = $cell_by_key|set:$cell_key:$c
        }
      }
    }

    // ── Pre-pass 2: scaling lookup, stage_key -> scales_with ───────────
    var $scaling_by_stage {
      value = {}
    }

    foreach ($scaling) {
      each as $sc {
        var.update $scaling_by_stage {
          value = $scaling_by_stage|set:$sc.stage_key:$sc.scales_with
        }
      }
    }

    // ── Pre-pass 3: rate presence, stage_key::quantity_key -> true ─────
    // Built from ALL rates before any stage is walked — see header.
    var $rate_present {
      value = {}
    }

    foreach ($rates) {
      each as $r {
        var $rp_key {
          value = $r.stage_key ~ "::" ~ $r.quantity_key
        }

        var.update $rate_present {
          value = $rate_present|set:$rp_key:true
        }
      }
    }

    var $lines {
      value = []
    }

    conditional {
      if ($has_items_row == true) {
        var.update $lines {
          value = $input.lines ?? []
        }
      }
    }

    var $stage_results {
      value = []
    }

    var $all_missing {
      value = []
    }

    var $grand_total {
      value = 0
    }

    foreach ($stages) {
      each as $stage {
        var $owner_key {
          value = $stage.owner_lens_key ?? ""
        }

        var $cell_lookup_key {
          value = $stage.key ~ "::" ~ $owner_key
        }

        var $owner_cell {
          value = $cell_by_key|get:$cell_lookup_key:null
        }

        var $baseline {
          value = $owner_cell.duration_minutes ?? 0
        }

        var $scales_with {
          value = "per_order"
        }

        conditional {
          if ($has_items_row == true) {
            var $sw_lookup {
              value = $scaling_by_stage|get:$stage.key:null
            }

            conditional {
              if ($sw_lookup != null) {
                var.update $scales_with {
                  value = $sw_lookup
                }
              }
            }
          }
        }

        var $variable_raw {
          value = 0
        }

        var $by_method {
          value = {}
        }

        var $method_order {
          value = []
        }

        var $method_seen {
          value = {}
        }

        var $used_any {
          value = false
        }

        var $used_seed {
          value = false
        }

        var $stage_missing {
          value = []
        }

        conditional {
          if ($scales_with == "per_unit" || $scales_with == "per_flagged_unit") {
            foreach ($lines) {
              each as $line {
                var $count {
                  value = 0
                }

                conditional {
                  if ($scales_with == "per_unit") {
                    var.update $count {
                      value = $line.quantity ?? 0
                    }
                  }

                  else {
                    var.update $count {
                      value = $line.flagged_quantity ?? 0
                    }
                  }
                }

                var $sq_key {
                  value = $stage.key ~ "::" ~ $line.quantity_key
                }

                var $present {
                  value = $rate_present|get:$sq_key:null
                }

                conditional {
                  if ($present == null) {
                    conditional {
                      if ($scales_with != "per_flagged_unit" || $count != 0) {
                        array.push $stage_missing {
                          value = $line.quantity_key
                        }
                      }
                    }
                  }
                }

                conditional {
                  if ($present != null && $count != 0) {
                    foreach ($rates) {
                      each as $rate {
                        conditional {
                          if ($rate.stage_key == $stage.key && $rate.quantity_key == $line.quantity_key) {
                            var $contribution {
                              value = $count * $rate.minutes_per_unit
                            }

                            var.update $variable_raw {
                              value = $variable_raw + $contribution
                            }

                            var $existing_method {
                              value = $by_method|get:$rate.method_key:null
                            }

                            var $existing_method_val {
                              value = 0
                            }

                            conditional {
                              if ($existing_method != null) {
                                var.update $existing_method_val {
                                  value = $existing_method
                                }
                              }
                            }

                            var.update $by_method {
                              value = $by_method|set:$rate.method_key:($existing_method_val + $contribution)
                            }

                            var $already_seen {
                              value = $method_seen|get:$rate.method_key:null
                            }

                            conditional {
                              if ($already_seen == null) {
                                array.push $method_order {
                                  value = {method_key: $rate.method_key}
                                }

                                var.update $method_seen {
                                  value = $method_seen|set:$rate.method_key:true
                                }
                              }
                            }

                            var.update $used_any {
                              value = true
                            }

                            conditional {
                              if ($rate.source == "seed") {
                                var.update $used_seed {
                                  value = true
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        var $variable_minutes {
          value = ($variable_raw + 0.5)|floor
        }

        var $stage_total {
          value = $baseline + $variable_minutes
        }

        var $source {
          value = "n/a"
        }

        conditional {
          if ($used_any == true) {
            conditional {
              if ($used_seed == true) {
                var.update $source {
                  value = "seed"
                }
              }

              else {
                var.update $source {
                  value = "measured"
                }
              }
            }
          }
        }

        var $method_order_sorted {
          value = $method_order|sort:"method_key":"text":true
        }

        var $by_method_out {
          value = []
        }

        foreach ($method_order_sorted) {
          each as $mo {
            var $raw_method_minutes {
              value = $by_method|get:$mo.method_key:0
            }

            array.push $by_method_out {
              value = {method_key: $mo.method_key, minutes: ($raw_method_minutes + 0.5)|floor}
            }
          }
        }

        foreach ($stage_missing) {
          each as $mk {
            array.push $all_missing {
              value = {stage_key: $stage.key, quantity_key: $mk}
            }
          }
        }

        array.push $stage_results {
          value = {
            stage_key       : $stage.key
            owner_lens_key  : $stage.owner_lens_key
            scales_with     : $scales_with
            baseline_minutes: $baseline
            variable_minutes: $variable_minutes
            total_minutes   : $stage_total
            source          : $source
            by_method       : $by_method_out
            missing         : $stage_missing
          }
        }

        var.update $grand_total {
          value = $grand_total + $stage_total
        }
      }
    }

    var $reasons {
      value = []
    }

    conditional {
      if ($has_items_row == true && ($lines|count) == 0) {
        array.push $reasons {
          value = "no_lines"
        }
      }
    }

    var $complete {
      value = true
    }

    conditional {
      if ($has_items_row == true) {
        var $missing_count {
          value = $all_missing|count
        }

        var $reason_count {
          value = $reasons|count
        }

        conditional {
          if ($missing_count > 0 || $reason_count > 0) {
            var.update $complete {
              value = false
            }
          }
        }
      }
    }
  }

  response = {
    has_items_row: $has_items_row
    complete     : $complete
    total_minutes: $grand_total
    stages       : $stage_results
    missing      : $all_missing
    reasons      : $reasons
  }
}
