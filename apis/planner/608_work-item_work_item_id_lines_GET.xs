// EST-1 (US-EST-1-02) — Read-only convenience: this job's lines with
// the item's label/unit and, per line, its own per-stage contribution
// (quantity x the version's rate for that item, at every per_unit /
// per_flagged_unit stage). Also returns the job's whole estimate, so
// a single call can paint both "what's in this order" and "what it
// currently adds up to" without a second round trip.
//
// THE PER-LINE BREAKDOWN IS A DISPLAY CONVENIENCE, NOT A SECOND
// FORMULA: it is the same multiply-by-rate idea `estimate/compute_
// estimate` uses, but at single-item granularity (one line's own
// minutes at each stage) rather than the job-level totals/missing/
// source that function owns. The job's REAL numbers always come from
// `estimate/estimate_job`, called once below.
query "work-item/{work_item_id}/lines" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int work_item_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Job not found"
    }

    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $version

    var $rates {
      value = []
    }

    conditional {
      if ($version != null) {
        var.update $rates {
          value = $version.snapshot.rates ?? []
        }
      }
    }

    db.query work_item_line {
      where = $db.work_item_line.work_item_id == $input.work_item_id
      sort = {work_item_line.id: "asc"}
      return = {type: "list"}
    } as $line_rows

    var $item_type_ids {
      value = [-1]
    }

    foreach ($line_rows) {
      each as $lr {
        array.push $item_type_ids {
          value = $lr.item_type_id
        }
      }
    }

    db.query item_type {
      where = $db.item_type.id in $item_type_ids
      return = {type: "list"}
    } as $item_rows

    var $item_by_id {
      value = {}
    }

    foreach ($item_rows) {
      each as $it {
        var $it_id_key {
          value = $it.id|to_text
        }

        var.update $item_by_id {
          value = $item_by_id|set:$it_id_key:$it
        }
      }
    }

    var $lines_out {
      value = []
    }

    foreach ($line_rows) {
      each as $lr {
        var $lr_id_key {
          value = $lr.item_type_id|to_text
        }

        var $item {
          value = $item_by_id|get:$lr_id_key:null
        }

        var $item_key {
          value = $item.key ?? ""
        }

        var $by_stage {
          value = []
        }

        var $stage_minutes {
          value = {}
        }

        var $stage_order {
          value = []
        }

        var $stage_seen {
          value = {}
        }

        foreach ($rates) {
          each as $rate {
            conditional {
              if ($rate.quantity_key == $item_key) {
                var $contribution {
                  value = ($lr.quantity ?? 0) * $rate.minutes_per_unit
                }

                var $existing {
                  value = $stage_minutes|get:$rate.stage_key:null
                }

                var $existing_val {
                  value = 0
                }

                conditional {
                  if ($existing != null) {
                    var.update $existing_val {
                      value = $existing
                    }
                  }
                }

                var.update $stage_minutes {
                  value = $stage_minutes|set:$rate.stage_key:($existing_val + $contribution)
                }

                var $seen {
                  value = $stage_seen|get:$rate.stage_key:null
                }

                conditional {
                  if ($seen == null) {
                    array.push $stage_order {
                      value = $rate.stage_key
                    }

                    var.update $stage_seen {
                      value = $stage_seen|set:$rate.stage_key:true
                    }
                  }
                }
              }
            }
          }
        }

        foreach ($stage_order) {
          each as $sk {
            var $raw {
              value = $stage_minutes|get:$sk:0
            }

            array.push $by_stage {
              value = {stage_key: $sk, minutes: ($raw + 0.5)|floor}
            }
          }
        }

        array.push $lines_out {
          value = {
            id              : $lr.id
            item_type_id    : $lr.item_type_id
            item_key        : $item_key
            item_label      : ($item.label ?? "")
            unit            : ($item.unit ?? "")
            is_active       : ($item.is_active ?? true)
            quantity        : $lr.quantity
            flagged_quantity: $lr.flagged_quantity
            by_stage        : $by_stage
          }
        }
      }
    }

    function.run "estimate/estimate_job" {
      input = {work_item_id: $input.work_item_id}
    } as $estimate

    // EST-1 Opus review fix (finding #8a, 2026-10-25) — the item
    // picker in JobLinesEditor.tsx was reading the account's WHOLE
    // catalog (listCatalogItemTypes), not what THIS job's pinned
    // version can actually price. `available_items` is sourced from
    // `stage_rate` (written only at publish, keyed by item `key`),
    // never `journey_lens_item` (a live draft, never pinned to a
    // version) — same reasoning 607's own header already gives for
    // E-EST-003. Seeded with a sentinel key so `in` is never run
    // against an empty array (CLAUDE.md).
    var $version_item_keys {
      value = ["__none__"]
    }

    conditional {
      if ($version != null) {
        db.query stage_rate {
          where = $db.stage_rate.journey_map_version_id == $version.id
          return = {type: "list"}
        } as $avail_rates

        foreach ($avail_rates) {
          each as $ar {
            array.push $version_item_keys {
              value = $ar.quantity_key
            }
          }
        }
      }
    }

    db.query item_type {
      where = $db.item_type.account_id == $actor.account_id && $db.item_type.key in $version_item_keys
      return = {type: "list"}
    } as $avail_item_rows

    var $available_items {
      value = []
    }

    foreach ($avail_item_rows) {
      each as $ai {
        array.push $available_items {
          value = {
            item_type_id: $ai.id
            key         : $ai.key
            label       : $ai.label
            unit        : $ai.unit
            is_active   : $ai.is_active
          }
        }
      }
    }

    // EST-1 Opus review fix (finding #8c) — whether this job's lines
    // are locked, same rule as 607's own E-EST-007 refusal. The UI
    // should show this proactively (disable the editor), not only
    // discover it after a failed save.
    db.query work_task {
      where = $db.work_task.work_item_id == $input.work_item_id && $db.work_task.status != "not_started"
      return = {type: "count"}
    } as $frozen_count

    var $frozen {
      value = ($frozen_count > 0)
    }
  }

  response = {
    work_item_id   : $input.work_item_id
    lines          : $lines_out
    estimate       : $estimate
    available_items: $available_items
    frozen         : $frozen
  }
}
