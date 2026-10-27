// EST-1 (US-EST-1-03) — The DB-reading wrapper real callers use. Loads
// the job, its PINNED version and its order lines, resolves each
// line's item_type_id to the stable key `estimate/compute_estimate`
// matches rates by, and hands everything to the one formula.
//
// READ-ONLY, LOGS NOTHING. This can be called many times per page
// (every job-detail read, every backlog read, every schedule attempt)
// and must not flood event_log the way a heartbeat bug once did
// (CLAUDE.md). The epic's estimate_computed / estimate_incomplete
// events are logged by the WRITE paths that act on a fresh result —
// the lines PUT (US-EST-1-02) — not by this read.
//
// THROWS ONLY FOR A MISSING JOB OR VERSION (PRD §6.2). A missing rate
// is `missing`/`complete`, never an exception.
function "estimate/estimate_job" {
  input {
    int work_item_id filters=min:1
  }

  stack {
    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    precondition ($job != null) {
      error_type = "notfound"
      error = "Job not found"
    }

    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $version

    precondition ($version != null) {
      error_type = "notfound"
      error = "Version not found"
    }

    db.query work_item_line {
      where = $db.work_item_line.work_item_id == $input.work_item_id
      return = {type: "list"}
    } as $line_rows

    var $lines {
      value = []
    }

    conditional {
      if (($line_rows|count) > 0) {
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

        var $item_key_by_id {
          value = {}
        }

        foreach ($item_rows) {
          each as $it {
            var $it_id_key {
              value = $it.id|to_text
            }

            var.update $item_key_by_id {
              value = $item_key_by_id|set:$it_id_key:$it.key
            }
          }
        }

        foreach ($line_rows) {
          each as $lr {
            var $lr_id_key {
              value = $lr.item_type_id|to_text
            }

            var $lr_quantity_key {
              value = $item_key_by_id|get:$lr_id_key:""
            }

            array.push $lines {
              value = {
                quantity_key    : $lr_quantity_key
                quantity        : $lr.quantity
                flagged_quantity: $lr.flagged_quantity
              }
            }
          }
        }
      }
    }

    function.run "estimate/compute_estimate" {
      input = {snapshot: $version.snapshot, lines: $lines}
    } as $estimate
  }

  response = {
    work_item_id          : $input.work_item_id
    journey_map_version_id: $version.id
    has_items_row         : $estimate.has_items_row
    complete              : $estimate.complete
    total_minutes         : $estimate.total_minutes
    stages                : $estimate.stages
    missing               : $estimate.missing
    reasons               : $estimate.reasons
  }
}
