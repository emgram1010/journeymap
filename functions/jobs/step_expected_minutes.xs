// REPEAT-1 story 04 — How long one job step is expected to take, from the job's version and its estimate. Pure: no database. This is SCHED-1's rule exactly as `planner_ops/schedule_work_task` applies it when no duration is sent (the cell's own minutes; on a map with an Items row, the OWNING row's stage estimate, or its baseline when the stage or the whole job is incomplete; 30 when there is no estimate at all), taken out so a repeat sizes a copied slot the way a person's click would. `estimate` is what `estimate/compute_estimate` returns for the job's lines. FOLLOW-UP (Opus review): `schedule_work_task` still holds its own copy of this rule; switch it to call this function, with a before/after replay, so there is one copy.
function "jobs/step_expected_minutes" {
  input {
    json snapshot
    text stage_key
    text lens_key
    json estimate
  }

  stack {
    var $expected {
      value = 0
    }

    foreach ($input.snapshot.cells) {
      each as $c {
        conditional {
          if ($c.stage_key == $input.stage_key && $c.lens_key == $input.lens_key) {
            var.update $expected {
              value = ($c.duration_minutes ?? 0)
            }
          }
        }
      }
    }

    conditional {
      if ($input.estimate.has_items_row == true) {
        foreach ($input.estimate.stages) {
          each as $se {
            conditional {
              if ($se.stage_key == $input.stage_key && $se.owner_lens_key == $input.lens_key) {
                var $se_incomplete {
                  value = (($se.missing|count) > 0)
                }

                conditional {
                  if ($se.scales_with != "per_order" && $input.estimate.complete == false) {
                    var.update $se_incomplete {
                      value = true
                    }
                  }
                }

                conditional {
                  if ($se_incomplete == true) {
                    var.update $expected {
                      value = $se.baseline_minutes
                    }
                  }

                  else {
                    var.update $expected {
                      value = $se.total_minutes
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    var $minutes {
      value = $expected
    }

    conditional {
      if ($expected < 1) {
        var.update $minutes {
          value = 30
        }
      }
    }
  }

  response = {expected: $expected, minutes: $minutes}
}
